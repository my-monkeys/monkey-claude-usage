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

DIST="$REPO_ROOT/dist"
APP="$DIST/$APP_NAME.app"

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

info "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_PATH/$EXECUTABLE_NAME" "$APP/Contents/MacOS/$EXECUTABLE_NAME"

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
	<string>$VERSION</string>
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
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
  warn "no Developer ID Application certificate found — signing ad-hoc"
  warn "the app will run on this Mac only; it cannot be notarized or distributed"
  codesign --force --sign - "$APP"
fi

codesign --verify --strict --verbose=2 "$APP"

info "Built $APP"
lipo -info "$APP/Contents/MacOS/$EXECUTABLE_NAME"
