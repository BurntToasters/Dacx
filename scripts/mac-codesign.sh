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
APP_INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
ZIP_NAME="${APP_NAME}-macOS.zip"
ZIP_PATH="$ROOT/release/$ZIP_NAME"
ENTITLEMENTS_FILE="$ROOT/macos/Runner/Release.entitlements"
MUSIC_ICON_SOURCE="$ROOT/assets/dacx_music_icon.png"
MUSIC_ICON_NAME="dacx_music_icon.icns"
MUSIC_ICON_DEST="$APP_BUNDLE/Contents/Resources/$MUSIC_ICON_NAME"
KEYCHAIN_PATH="${KEYCHAIN_PATH:-}"

find_codesigning_identities() {
  if [[ -n "$KEYCHAIN_PATH" ]]; then
    security find-identity -v -p codesigning "$KEYCHAIN_PATH"
  else
    security find-identity -v -p codesigning
  fi
}

run_codesign() {
  if [[ -n "$KEYCHAIN_PATH" ]]; then
    codesign --keychain "$KEYCHAIN_PATH" "$@"
  else
    codesign "$@"
  fi
}

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

find_codesigning_identities | grep -F "$APPLE_SIGNING_IDENTITY" >/dev/null || {
  echo "ERROR: APPLE_SIGNING_IDENTITY was not found in the codesigning identities."
  echo "       Identity: $APPLE_SIGNING_IDENTITY"
  echo "       Run: security find-identity -v -p codesigning${KEYCHAIN_PATH:+ \"$KEYCHAIN_PATH\"}"
  exit 1
}

if [[ -f "$MUSIC_ICON_SOURCE" ]]; then
  bash "$ROOT/scripts/embed-mac-document-icon.sh" "$APP_BUNDLE"
else
  echo "WARN: Missing $MUSIC_ICON_SOURCE; audio files will use the default document icon."
fi

# Build self-update helper directly into the bundle (signed below).
HELPER_OUT="$APP_BUNDLE/Contents/MacOS/dacx-update-helper"
echo "Building update helper → $HELPER_OUT"
bash "$ROOT/macos/Helper/build-helper.sh" --output "$HELPER_OUT"

# Preserve the raw release SemVer in the signed bundle.
/usr/libexec/PlistBuddy -c "Set :DacxReleaseVersion $PKG_VERSION" "$APP_INFO_PLIST" 2>/dev/null ||
  /usr/libexec/PlistBuddy -c "Add :DacxReleaseVersion string $PKG_VERSION" "$APP_INFO_PLIST"

# Signing
echo "Codesigning ${APP_BUNDLE}..."

# Sign all embedded dylibs first (files)
find "$APP_BUNDLE" -type f -name "*.dylib" -print0 | while IFS= read -r -d '' lib; do
  run_codesign --force --options runtime --timestamp \
    --sign "$APPLE_SIGNING_IDENTITY" "$lib"
done

# Sign all embedded frameworks (directories)
find "$APP_BUNDLE" -type d -name "*.framework" -print0 | while IFS= read -r -d '' fw; do
  run_codesign --force --options runtime --timestamp \
    --sign "$APPLE_SIGNING_IDENTITY" "$fw"
done

# Sign the update helper before the parent bundle (codesign rules require
# nested executables to be signed inside-out).
if [[ -f "$HELPER_OUT" ]]; then
  run_codesign --force --options runtime --timestamp \
    --sign "$APPLE_SIGNING_IDENTITY" "$HELPER_OUT"
fi

run_codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS_FILE" \
  --sign "$APPLE_SIGNING_IDENTITY" \
  "$APP_BUNDLE"

echo "Verifying codesign..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "Verifying entitlements..."
if codesign -d --entitlements :- "$APP_BUNDLE" 2>/dev/null | grep -q 'com.apple.security.app-sandbox'; then
  echo "ERROR: Release app is sandboxed, but the self-updater needs to spawn validation and helper tools."
  exit 1
fi

# Pkg
echo "Creating zip for notarization..."
mkdir -p "$ROOT/release"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

# Notarize
echo "Submitting for notarization..."
xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait

# Staple notarization ticket to the app bundle
echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_BUNDLE"

# Re-zip with stapled ticket
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "Verifying final zip payload..."
ZIP_VERIFY_DIR="$(mktemp -d)"
cleanup_zip_verify() {
  rm -rf "$ZIP_VERIFY_DIR"
}
trap cleanup_zip_verify EXIT

ditto -x -k --sequesterRsrc "$ZIP_PATH" "$ZIP_VERIFY_DIR"
ZIP_VERIFY_APP="$ZIP_VERIFY_DIR/${APP_NAME}.app"
ZIP_VERIFY_INFO="$ZIP_VERIFY_APP/Contents/Info.plist"

if [[ ! -d "$ZIP_VERIFY_APP" ]]; then
  echo "ERROR: Final zip did not extract ${APP_NAME}.app"
  exit 1
fi

ZIP_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ZIP_VERIFY_INFO")"
if [[ "$ZIP_BUNDLE_ID" != "run.rosie.dacx" ]]; then
  echo "ERROR: Final zip app bundle id is $ZIP_BUNDLE_ID, expected run.rosie.dacx"
  exit 1
fi

ZIP_RELEASE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :DacxReleaseVersion' "$ZIP_VERIFY_INFO")"
if [[ "$ZIP_RELEASE_VERSION" != "$PKG_VERSION" ]]; then
  echo "ERROR: Final zip app release version is $ZIP_RELEASE_VERSION, expected $PKG_VERSION"
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$ZIP_VERIFY_APP"
if ! spctl --assess --type execute --verbose=4 "$ZIP_VERIFY_APP"; then
  echo "ERROR: spctl assessment failed for app extracted from final zip"
  exit 1
fi

cleanup_zip_verify
trap - EXIT

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
run_codesign --force --sign "$APPLE_SIGNING_IDENTITY" "$DMG_PATH"

# Notarize DMG so Gatekeeper can verify it offline (the inner .app is already
# stapled, but stapling the DMG too lets users mount it without a network
# round-trip and avoids the "Apple could not verify" warning when the .dmg
# itself is downloaded directly).
echo "Submitting DMG for notarization..."
xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait

echo "Stapling DMG..."
xcrun stapler staple "$DMG_PATH"

echo "Verifying Gatekeeper acceptance of stapled .app..."
if ! spctl --assess --type execute --verbose=4 "$APP_BUNDLE"; then
  echo "ERROR: spctl assessment failed for $APP_BUNDLE"
  echo "       The signed/stapled .app would be rejected by Gatekeeper."
  exit 1
fi
echo "Verifying Gatekeeper acceptance of DMG..."
if ! spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"; then
  echo "ERROR: spctl assessment failed for $DMG_PATH"
  echo "       The notarized DMG would be rejected by Gatekeeper."
  exit 1
fi

echo ""
echo "Done:"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
echo "  Signed with: $APPLE_SIGNING_IDENTITY"
echo "  Notarized and stapled."
