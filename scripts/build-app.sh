#!/usr/bin/env bash
#
# Builds "Monkey Claude Usage.app" (universal arm64 + x86_64) into dist/.
#
#   VERSION=1.2.3 ./scripts/build-app.sh
#
# Signs with a Developer ID Application certificate when one is available,
# ad-hoc otherwise (fine for local runs, refused by Gatekeeper elsewhere).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

VERSION="${VERSION:-0.1.0}"
APP_NAME="Monkey Claude Usage"
EXECUTABLE_NAME="MonkeyClaudeUsage"
BUNDLE_ID="fr.mymonkey.monkeyclaudeusage"
RESOURCE_BUNDLE="MonkeyClaudeUsage_MonkeyClaudeUsage.bundle"
MINIMUM_SYSTEM_VERSION="14.0"
COPYRIGHT="Copyright © 2026 My-Monkey. Released under the BSD 2-Clause License."

# Sparkle. The private half lives in the login keychain under the account below and is
# never written to this repository — see docs/RELEASING.md.
SPARKLE_PUBLIC_KEY="OCHtXohyD4woD+VjFfZvJRg8RDas5ZAXK4UlGHLRIvQ="
FEED_URL="https://raw.githubusercontent.com/my-monkeys/monkey-claude-usage/main/appcast.xml"

DIST="$REPO_ROOT/dist"
APP="$DIST/$APP_NAME.app"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Sparkle compares CFBundleVersion, and it compares it as a number: "0.10.0" has to sort
# above "0.2.0", which the marketing string does not. Hence one integer per release.
bundle_version() {
  local major minor patch
  IFS=. read -r major minor patch <<< "$1"
  [[ "$minor" -lt 100 && "$patch" -lt 100 ]] \
    || die "minor and patch must stay below 100 to keep the build number increasing: $1"
  echo $(( major * 10000 + minor * 100 + patch ))
}

developer_id_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    printf '%s' "$CODESIGN_IDENTITY"
    return
  fi
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
    | head -n 1
}

# Sparkle nests bundles of its own — two XPC services, the Autoupdate helper and
# Updater.app — that signing the .framework alone does NOT reach. Leaving them with the
# ad-hoc signature SwiftPM gives them is what gets the whole app rejected by the notary
# service with "not signed with a valid Developer ID certificate". Deepest first.
sign_sparkle() {
  local framework="$APP/Contents/Frameworks/Sparkle.framework"
  local versioned="$framework/Versions/B"
  codesign "$@" --preserve-metadata=entitlements "$versioned/XPCServices/Downloader.xpc"
  codesign "$@" --preserve-metadata=entitlements "$versioned/XPCServices/Installer.xpc"
  codesign "$@" "$versioned/Autoupdate"
  codesign "$@" "$versioned/Updater.app"
  codesign "$@" "$framework"
}

locate_app_icon() {
  local candidate
  for candidate in \
    "$REPO_ROOT/Sources/MonkeyClaudeUsage/Resources/AppIcon.icns" \
    "$BIN_PATH/$RESOURCE_BUNDLE/Contents/Resources/AppIcon.icns" \
    "$BIN_PATH/$RESOURCE_BUNDLE/Resources/AppIcon.icns"
  do
    if [[ -f "$candidate" ]]; then
      printf '%s' "$candidate"
      return
    fi
  done
}

info "Building $APP_NAME $VERSION (universal)"
swift build -c release --arch arm64 --arch x86_64

BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
[[ -x "$BIN_PATH/$EXECUTABLE_NAME" ]] || die "executable not found at $BIN_PATH/$EXECUTABLE_NAME"

SPARKLE_FRAMEWORK="$BIN_PATH/Frameworks/Sparkle.framework"
[[ -d "$SPARKLE_FRAMEWORK" ]] || die "Sparkle.framework not found at $SPARKLE_FRAMEWORK"

info "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp "$BIN_PATH/$EXECUTABLE_NAME" "$APP/Contents/MacOS/$EXECUTABLE_NAME"

# ditto rather than cp -R: the framework is a tree of relative symlinks around Versions/B.
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"

# SwiftPM links Sparkle as @rpath/Sparkle.framework/… but only emits its own rpaths
# (/usr/lib/swift and @executable_path/../lib). Without this the app dies at launch on
# "Library not loaded" — and it has to happen before signing, which it invalidates.
if ! otool -l "$APP/Contents/MacOS/$EXECUTABLE_NAME" | grep -q '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/$EXECUTABLE_NAME"
fi

if [[ -d "$BIN_PATH/$RESOURCE_BUNDLE" ]]; then
  cp -R "$BIN_PATH/$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
else
  warn "SPM resource bundle $RESOURCE_BUNDLE not found — Bundle.module would trap at runtime"
fi

APP_ICON="$(locate_app_icon)"
if [[ -n "$APP_ICON" ]]; then
  cp "$APP_ICON" "$APP/Contents/Resources/AppIcon.icns"
else
  warn "AppIcon.icns not found — the app will show the generic macOS icon"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>$APP_NAME</string>
	<key>CFBundleExecutable</key>
	<string>$EXECUTABLE_NAME</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$(bundle_version "$VERSION")</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.developer-tools</string>
	<key>LSMinimumSystemVersion</key>
	<string>$MINIMUM_SYSTEM_VERSION</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>$COPYRIGHT</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>SUEnableAutomaticChecks</key>
	<true/>
	<key>SUFeedURL</key>
	<string>$FEED_URL</string>
	<key>SUPublicEDKey</key>
	<string>$SPARKLE_PUBLIC_KEY</string>
</dict>
</plist>
PLIST

plutil -lint "$APP/Contents/Info.plist" > /dev/null

# Stale extended attributes (quarantine, Finder metadata) make codesign fail with
# "resource fork, Finder information, or similar detritus not allowed".
xattr -cr "$APP"

IDENTITY="$(developer_id_identity)"
if [[ -n "$IDENTITY" ]]; then
  info "Signing with: $IDENTITY"
  # The SPM resource bundle carries its own Info.plist, so codesign treats it as a
  # nested bundle: sign it before sealing the app around it.
  if [[ -d "$APP/Contents/Resources/$RESOURCE_BUNDLE" ]]; then
    codesign --force --timestamp --sign "$IDENTITY" "$APP/Contents/Resources/$RESOURCE_BUNDLE"
  fi
  sign_sparkle --force --options runtime --timestamp --sign "$IDENTITY"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
  warn "no Developer ID Application certificate found — signing ad-hoc"
  warn "the app will run on this Mac only; it cannot be notarized or distributed"
  sign_sparkle --force --sign -
  codesign --force --sign - "$APP"
fi

# --deep so the verification walks into Sparkle's nested bundles too: sealing the app is
# what a plain --verify checks, and it succeeds over an unsigned helper.
codesign --verify --deep --strict --verbose=2 "$APP"

info "Built $APP"
lipo -info "$APP/Contents/MacOS/$EXECUTABLE_NAME"
