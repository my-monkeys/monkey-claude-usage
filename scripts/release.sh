#!/usr/bin/env bash
#
# Cuts a release: universal build → signed DMG → notarization → git tag →
# GitHub release → Homebrew cask bump.
#
#   ./scripts/release.sh 1.2.3
#   ./scripts/release.sh 1.2.3 --dry-run          # builds and notarizes, publishes nothing
#   ./scripts/release.sh 1.2.3 --skip-notarize    # local disk image, not distributable
#
# Every step is idempotent: re-running after a failure picks up where it stopped.
# Notarization credentials are read from .release.env (git-ignored) — see
# docs/RELEASING.md.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

REPO="my-monkeys/monkey-claude-usage"
TAP_REPO="my-monkeys/homebrew-tap"
CASK_PATH="Casks/monkey-claude-usage.rb"
DIST="$REPO_ROOT/dist"

DRY_RUN=false
SKIP_NOTARIZE=false
VERSION=""

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
skip() { printf '\033[1;35m[dry-run]\033[0m %s\n' "$*"; }

usage() {
  cat >&2 <<USAGE
usage: scripts/release.sh <X.Y.Z> [--dry-run] [--skip-notarize]

  --dry-run        build (and notarize) but create no tag, release or cask commit
  --skip-notarize  skip notarization entirely — the disk image will be refused by
                   Gatekeeper on any other Mac
USAGE
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)       DRY_RUN=true ;;
    --skip-notarize) SKIP_NOTARIZE=true ;;
    -h|--help)       usage ;;
    -*)              die "unknown option: $1" ;;
    *)               [[ -z "$VERSION" ]] || die "unexpected argument: $1"; VERSION="$1" ;;
  esac
  shift
done

[[ -n "$VERSION" ]] || usage
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be X.Y.Z, got: $VERSION"

TAG="v$VERSION"
DMG="$DIST/MonkeyClaudeUsage-$VERSION.dmg"

# ---------------------------------------------------------------- preflight

info "Checking the working tree"

[[ -z "$(git status --porcelain)" ]] || die "working tree is dirty — commit or stash first"

DEFAULT_BRANCH="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[[ "$CURRENT_BRANCH" == "$DEFAULT_BRANCH" ]] \
  || die "releases are cut from $DEFAULT_BRANCH, currently on $CURRENT_BRANCH"

command -v gh > /dev/null || die "gh is required — brew install gh"
gh auth status > /dev/null 2>&1 || die "gh is not authenticated — run: gh auth login"

if [[ -f "$REPO_ROOT/.release.env" ]]; then
  info "Reading .release.env"
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.release.env"
  set +a
fi

NOTARY_ARGS=()
if [[ "$SKIP_NOTARIZE" == true ]]; then
  warn "notarization skipped — the disk image is signed but not notarized"
elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
  NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" && -n "${NOTARY_KEY_PATH:-}" ]]; then
  NOTARY_KEY_PATH="${NOTARY_KEY_PATH/#\~/$HOME}"
  [[ -f "$NOTARY_KEY_PATH" ]] || die "NOTARY_KEY_PATH does not exist: $NOTARY_KEY_PATH"
  NOTARY_ARGS=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
else
  cat >&2 <<'SETUP'
error: no notarization credentials.

Create .release.env at the repository root (it is git-ignored) with the App Store
Connect API key used for notarization:

    NOTARY_KEY_ID=XXXXXXXXXX
    NOTARY_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    NOTARY_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8

Or store the credentials in the keychain once and name the profile instead:

    xcrun notarytool store-credentials monkey-claude-usage \
      --key ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8 \
      --key-id XXXXXXXXXX --issuer xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    echo 'NOTARY_PROFILE=monkey-claude-usage' >> .release.env

To build a disk image for local use only, re-run with --skip-notarize.
SETUP
  exit 1
fi

# ------------------------------------------------------------------- build

info "Building the disk image for $TAG"
VERSION="$VERSION" "$REPO_ROOT/scripts/build-dmg.sh"
[[ -f "$DMG" ]] || die "$DMG was not produced"

# -------------------------------------------------------------- notarize

if [[ "$SKIP_NOTARIZE" == false ]]; then
  if xcrun stapler validate "$DMG" > /dev/null 2>&1; then
    info "Disk image already stapled — skipping notarization"
  else
    info "Submitting to Apple for notarization (this takes a few minutes)"
    xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait

    info "Stapling the notarization ticket"
    xcrun stapler staple "$DMG"
  fi

  info "Verifying Gatekeeper acceptance"
  ASSESSMENT="$(spctl -a -vvv -t install "$DMG" 2>&1 || true)"
  printf '%s\n' "$ASSESSMENT"
  grep -q 'source=Notarized Developer ID' <<< "$ASSESSMENT" \
    || die "Gatekeeper did not report a notarized Developer ID signature"
fi

# ---------------------------------------------------------------- git tag

PREVIOUS_TAG="$(git tag --list 'v*' --sort=-version:refname | grep -vx "$TAG" | head -n 1 || true)"
if [[ -n "$PREVIOUS_TAG" ]]; then
  RELEASE_NOTES="$(git log --no-merges --pretty='- %s' "$PREVIOUS_TAG..HEAD")"
else
  RELEASE_NOTES="$(git log --no-merges --pretty='- %s')"
fi
[[ -n "$RELEASE_NOTES" ]] || RELEASE_NOTES="- $TAG"

if EXISTING_TAG_SHA="$(git rev-parse --quiet --verify "refs/tags/$TAG^{commit}")"; then
  [[ "$EXISTING_TAG_SHA" == "$(git rev-parse HEAD)" ]] \
    || die "$TAG already exists and points elsewhere — delete it or bump the version"
  info "Tag $TAG already exists on HEAD"
elif [[ "$DRY_RUN" == true ]]; then
  skip "git tag -a $TAG"
else
  info "Tagging $TAG"
  git tag -a "$TAG" -m "$TAG"
fi

if [[ "$DRY_RUN" == true ]]; then
  skip "git push origin $TAG"
else
  info "Pushing $TAG"
  git push origin "$TAG"
fi

# --------------------------------------------------------- github release

if [[ "$DRY_RUN" == true ]]; then
  skip "gh release create $TAG with $(basename "$DMG")"
  printf '%s\n' "$RELEASE_NOTES"
elif gh release view "$TAG" --repo "$REPO" > /dev/null 2>&1; then
  info "Release $TAG already exists — replacing its disk image"
  gh release upload "$TAG" "$DMG" --repo "$REPO" --clobber
else
  info "Creating GitHub release $TAG"
  gh release create "$TAG" "$DMG" --repo "$REPO" --title "$TAG" --notes "$RELEASE_NOTES"
fi

# ------------------------------------------------------------ homebrew cask

TAP_DIR="$DIST/homebrew-tap"
SHA256="$(shasum -a 256 "$DMG" | awk '{print $1}')"

info "Updating $TAP_REPO ($CASK_PATH)"
if [[ -d "$TAP_DIR/.git" ]]; then
  git -C "$TAP_DIR" fetch --quiet origin
else
  rm -rf "$TAP_DIR"
  gh repo clone "$TAP_REPO" "$TAP_DIR" -- --quiet
fi
TAP_BRANCH="$(git -C "$TAP_DIR" symbolic-ref --quiet --short HEAD)"
git -C "$TAP_DIR" reset --quiet --hard "origin/$TAP_BRANCH"

cat > "$TAP_DIR/$CASK_PATH" <<CASK
cask "monkey-claude-usage" do
  version "$VERSION"
  sha256 "$SHA256"

  # No \`verified:\` — Homebrew 6 deprecated it, and the download URL already sits under
  # the homepage host, which is what the default verification checks.
  url "https://github.com/$REPO/releases/download/v#{version}/MonkeyClaudeUsage-#{version}.dmg"
  name "Monkey Claude Usage"
  desc "Menu bar tracker for Claude usage limits across several accounts"
  homepage "https://github.com/$REPO"

  depends_on macos: :sonoma

  app "Monkey Claude Usage.app"

  zap trash: [
    "~/Library/Application Support/fr.mymonkey.monkeyclaudeusage",
    "~/Library/Caches/fr.mymonkey.monkeyclaudeusage",
    "~/Library/HTTPStorages/fr.mymonkey.monkeyclaudeusage",
    "~/Library/Preferences/fr.mymonkey.monkeyclaudeusage.plist",
  ]
end
CASK

git -C "$TAP_DIR" add "$CASK_PATH"
if git -C "$TAP_DIR" diff --cached --quiet; then
  info "Cask already at $VERSION"
elif [[ "$DRY_RUN" == true ]]; then
  skip "commit and push the cask bump:"
  git -C "$TAP_DIR" --no-pager diff --cached
else
  git -C "$TAP_DIR" commit --quiet -m "monkey-claude-usage $VERSION"
  git -C "$TAP_DIR" push --quiet
  info "Cask bumped to $VERSION"
fi

info "Done — brew install --cask my-monkeys/tap/monkey-claude-usage"
