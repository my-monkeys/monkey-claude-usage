#!/usr/bin/env bash
#
# Builds dist/MonkeyClaudeUsage-<VERSION>.dmg from a fresh app build.
#
#   VERSION=1.2.3 ./scripts/build-dmg.sh
#
# Plain hdiutil, no create-dmg dependency: the disk image holds the app and a
# symlink to /Applications, which is all Homebrew Cask needs.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

VERSION="${VERSION:-0.1.0}"
APP_NAME="Monkey Claude Usage"
VOLUME_NAME="Monkey Claude Usage"

DIST="$REPO_ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/MonkeyClaudeUsage-$VERSION.dmg"
STAGING="$DIST/dmg-staging"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

developer_id_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    printf '%s' "$CODESIGN_IDENTITY"
    return
  fi
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
    | head -n 1
}

VERSION="$VERSION" "$REPO_ROOT/scripts/build-app.sh"
[[ -d "$APP" ]] || die "$APP was not produced"

# A volume left mounted by an interrupted run makes hdiutil fail with "Resource busy".
if [[ -d "/Volumes/$VOLUME_NAME" ]]; then
  info "Detaching stale /Volumes/$VOLUME_NAME"
  hdiutil detach "/Volumes/$VOLUME_NAME" -quiet || true
fi

info "Staging disk image contents"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

info "Creating $DMG"
rm -f "$DMG"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG" > /dev/null

rm -rf "$STAGING"

IDENTITY="$(developer_id_identity)"
if [[ -n "$IDENTITY" ]]; then
  info "Signing disk image with: $IDENTITY"
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  codesign --verify --verbose=2 "$DMG"
else
  warn "no Developer ID Application certificate found — the disk image stays unsigned"
fi

info "Built $DMG ($(du -h "$DMG" | cut -f1))"
