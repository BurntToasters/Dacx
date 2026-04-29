#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: This script must be run on macOS."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
PKG_VERSION="$(node -p "require('$ROOT/package.json').version")"

APP_NAME="Dacx"
BUILD_DIR="$ROOT/build/macos/Build/Products/Release"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"
ZIP_NAME="${APP_NAME}-${PKG_VERSION}-macos.zip"
ZIP_PATH="$ROOT/release/$ZIP_NAME"
ENTITLEMENTS_FILE="$ROOT/macos/Runner/Release.entitlements"
MUSIC_ICON_SOURCE="$ROOT/assets/dacx_music_icon.png"
MUSIC_ICON_NAME="dacx_music_icon.icns"
MUSIC_ICON_DEST="$APP_BUNDLE/Contents/Resources/$MUSIC_ICON_NAME"

# Validate
: "${APPLE_SIGNING_IDENTITY:?Set APPLE_SIGNING_IDENTITY in .env}"
: "${APPLE_ID:?Set APPLE_ID in .env}"
: "${APPLE_PASSWORD:?Set APPLE_PASSWORD in .env}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID in .env}"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "ERROR: App bundle not found at $APP_BUNDLE"
  echo "Run 'npm run build:mac' first."
  exit 1
fi

if [[ ! -f "$ENTITLEMENTS_FILE" ]]; then
  echo "ERROR: Entitlements file not found at $ENTITLEMENTS_FILE"
  exit 1
fi

if [[ -f "$MUSIC_ICON_SOURCE" ]]; then
  ICONSET_DIR="$ROOT/build/mac-audio-icon.iconset"
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"

  while IFS=: read -r icon_name size; do
    sips -z "$size" "$size" "$MUSIC_ICON_SOURCE" --out "$ICONSET_DIR/$icon_name" >/dev/null
  done <<'EOF'
icon_16x16.png:16
icon_16x16@2x.png:32
icon_32x32.png:32
icon_32x32@2x.png:64
icon_128x128.png:128
icon_128x128@2x.png:256
icon_256x256.png:256
icon_256x256@2x.png:512
icon_512x512.png:512
icon_512x512@2x.png:1024
EOF

  iconutil -c icns "$ICONSET_DIR" -o "$MUSIC_ICON_DEST"
  rm -rf "$ICONSET_DIR"
  echo "Prepared audio document icon at $MUSIC_ICON_DEST"
else
  echo "WARN: Missing $MUSIC_ICON_SOURCE; audio files will use the default document icon."
fi

# Signing
echo "Codesigning ${APP_BUNDLE}..."

# Sign all embedded dylibs first (files)
find "$APP_BUNDLE" -type f -name "*.dylib" -print0 | while IFS= read -r -d '' lib; do
  codesign --force --options runtime --timestamp \
    --sign "$APPLE_SIGNING_IDENTITY" "$lib"
done

# Sign all embedded frameworks (directories)
find "$APP_BUNDLE" -type d -name "*.framework" -print0 | while IFS= read -r -d '' fw; do
  codesign --force --options runtime --timestamp \
    --sign "$APPLE_SIGNING_IDENTITY" "$fw"
done

codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS_FILE" \
  --sign "$APPLE_SIGNING_IDENTITY" \
  "$APP_BUNDLE"

echo "Verifying codesign..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "Verifying entitlements..."
if ! codesign -d --entitlements :- "$APP_BUNDLE" 2>/dev/null | grep -q 'com.apple.security.files.user-selected.read-only'; then
  echo "ERROR: Missing file picker entitlement after signing."
  exit 1
fi

# Pkg
echo "Creating zip for notarization..."
mkdir -p "$ROOT/release"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

# Notarize
echo "Submitting for notarization..."
xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait

# Staple Noatry
echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_BUNDLE"

# Re-zip with stapled ticket
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

# DMG
DMG_NAME="Dacx-macOS.dmg"
DMG_PATH="$ROOT/release/$DMG_NAME"
DMG_STAGE="$ROOT/build/dmg-stage"

echo "Creating DMG..."
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
cp -R "$APP_BUNDLE" "$DMG_STAGE/Dacx.app"
ln -s /Applications "$DMG_STAGE/Applications"

hdiutil create -volname "Dacx" -srcfolder "$DMG_STAGE" \
  -ov -format UDZO "$DMG_PATH"

rm -rf "$DMG_STAGE"

# Sign DMG
codesign --force --sign "$APPLE_SIGNING_IDENTITY" "$DMG_PATH"

echo ""
echo "Done:"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
echo "  Signed with: $APPLE_SIGNING_IDENTITY"
echo "  Notarized and stapled."
