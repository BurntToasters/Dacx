#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: This script must be run on macOS."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
PKG_VERSION="$(node -p "require('$ROOT/package.json').version")"

APP_NAME="dacx"
BUILD_DIR="$ROOT/build/macos/Build/Products/Release"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"
ZIP_NAME="${APP_NAME}-${PKG_VERSION}-macos.zip"
ZIP_PATH="$ROOT/release/$ZIP_NAME"

# ── Validate env ──────────────────────────────────────────────
: "${APPLE_SIGNING_IDENTITY:?Set APPLE_SIGNING_IDENTITY in .env}"
: "${APPLE_ID:?Set APPLE_ID in .env}"
: "${APPLE_PASSWORD:?Set APPLE_PASSWORD in .env}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID in .env}"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "ERROR: App bundle not found at $APP_BUNDLE"
  echo "Run 'npm run build:mac' first."
  exit 1
fi

# ── Codesign ──────────────────────────────────────────────────
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
  --sign "$APPLE_SIGNING_IDENTITY" \
  --deep "$APP_BUNDLE"

echo "Verifying codesign..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

# ── Package ───────────────────────────────────────────────────
echo "Creating zip for notarization..."
mkdir -p "$ROOT/release"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

# ── Notarize ──────────────────────────────────────────────────
echo "Submitting for notarization..."
xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait

# ── Staple ────────────────────────────────────────────────────
echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_BUNDLE"

# Re-zip with stapled ticket
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

# ── DMG ───────────────────────────────────────────────────────
DMG_NAME="DACX-macOS.dmg"
DMG_PATH="$ROOT/release/$DMG_NAME"
DMG_STAGE="$ROOT/build/dmg-stage"

echo "Creating DMG..."
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
cp -R "$APP_BUNDLE" "$DMG_STAGE/DACX.app"
ln -s /Applications "$DMG_STAGE/Applications"

hdiutil create -volname "DACX" -srcfolder "$DMG_STAGE" \
  -ov -format UDZO "$DMG_PATH"

rm -rf "$DMG_STAGE"

# Sign the DMG
codesign --force --sign "$APPLE_SIGNING_IDENTITY" "$DMG_PATH"

echo ""
echo "Done:"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
echo "  Signed with: $APPLE_SIGNING_IDENTITY"
echo "  Notarized and stapled."
