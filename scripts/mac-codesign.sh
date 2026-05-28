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

verify_macos_codesign() {
  local path="$1"
  codesign --verify --deep --strict --verbose=2 "$path"
  if command -v xcrun >/dev/null 2>&1; then
    xcrun stapler validate "$path"
  fi
}

verify_macos_app_distribution() {
  local path="$1"
  verify_macos_codesign "$path"
  if command -v syspolicy_check >/dev/null 2>&1; then
    syspolicy_check distribution "$path" --verbose
  else
    spctl --assess --type execute --verbose=2 "$path"
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

IDENTITY_MATCHES="$(find_codesigning_identities | grep -F "$APPLE_SIGNING_IDENTITY" || true)"
IDENTITY_MATCH_COUNT="$(printf '%s\n' "$IDENTITY_MATCHES" | grep -c '[A-F0-9]\{40\}' || true)"
if [[ "$IDENTITY_MATCH_COUNT" -eq 0 ]]; then
  echo "ERROR: APPLE_SIGNING_IDENTITY was not found in the codesigning identities."
  echo "       Identity: $APPLE_SIGNING_IDENTITY"
  echo "       Run: security find-identity -v -p codesigning${KEYCHAIN_PATH:+ \"$KEYCHAIN_PATH\"}"
  exit 1
fi
if [[ "$IDENTITY_MATCH_COUNT" -gt 1 ]]; then
  echo "ERROR: APPLE_SIGNING_IDENTITY matched $IDENTITY_MATCH_COUNT identities; refusing to guess which one to use."
  printf '%s\n' "$IDENTITY_MATCHES"
  echo "       Set APPLE_SIGNING_IDENTITY to the 40-char SHA-1 hash of the desired identity."
  exit 1
fi
APPLE_SIGNING_IDENTITY_HASH="$(printf '%s\n' "$IDENTITY_MATCHES" | grep -oE '[A-F0-9]{40}' | head -n1)"
if [[ -z "$APPLE_SIGNING_IDENTITY_HASH" ]]; then
  echo "ERROR: could not resolve a SHA-1 hash for APPLE_SIGNING_IDENTITY."
  exit 1
fi
echo "Using codesign identity hash: $APPLE_SIGNING_IDENTITY_HASH ($APPLE_SIGNING_IDENTITY)"
APPLE_SIGNING_IDENTITY="$APPLE_SIGNING_IDENTITY_HASH"

if [[ -f "$MUSIC_ICON_SOURCE" ]]; then
  bash "$ROOT/scripts/embed-mac-document-icon.sh" "$APP_BUNDLE"
else
  echo "WARN: Missing $MUSIC_ICON_SOURCE; audio files will use the default document icon."
fi

# Build the bundled XPC update helper service directly into the app bundle
# (signed below as a nested bundle with its own — un-sandboxed — entitlements).
HELPER_OUT="$APP_BUNDLE/Contents/XPCServices/run.rosie.dacx.UpdateHelper.xpc"
HELPER_ENTITLEMENTS="$ROOT/macos/Helper/UpdateHelper.entitlements"
# Remove any stale pre-migration `dacx-update-helper` binary that would
# otherwise trip codesign --deep --strict.
rm -f "$APP_BUNDLE/Contents/MacOS/dacx-update-helper"
# Inherit the parent app's CFBundleVersion (Flutter-validated build number)
# for the XPC bundle; notarytool requires it to be one to three integers, so
# the SemVer-style PKG_VERSION (e.g. "0.8.0-beta.5") can't go there directly.
PARENT_BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_INFO_PLIST")"
echo "Building update helper → $HELPER_OUT"
mkdir -p "$(dirname "$HELPER_OUT")"
bash "$ROOT/macos/Helper/build-helper.sh" \
  --output "$HELPER_OUT" \
  --short-version "$PKG_VERSION" \
  --build-version "$PARENT_BUILD_VERSION"

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

# Sign the XPC update helper bundle before the parent app (codesign rules
# require nested bundles to be signed inside-out). The helper's entitlements
# deliberately omit `com.apple.security.app-sandbox` so launchd hosts the XPC
# service outside the main app's container.
if [[ -d "$HELPER_OUT" ]]; then
  run_codesign --force --options runtime --timestamp \
    --entitlements "$HELPER_ENTITLEMENTS" \
    --sign "$APPLE_SIGNING_IDENTITY" "$HELPER_OUT"
fi

NOTICES_SRC="${ROOT}/build/THIRD_PARTY_NOTICES.txt"
if [[ ! -f "$NOTICES_SRC" ]]; then
  echo "Generating third-party notices..."
  node "${ROOT}/scripts/generate-licenses.js"
fi
if [[ -f "$NOTICES_SRC" ]]; then
  cp "$NOTICES_SRC" "${APP_BUNDLE}/Contents/Resources/THIRD_PARTY_NOTICES.txt"
  cp "${ROOT}/LICENSE" "${APP_BUNDLE}/Contents/Resources/LICENSE"
fi

run_codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS_FILE" \
  --sign "$APPLE_SIGNING_IDENTITY" \
  "$APP_BUNDLE"

echo "Verifying codesign..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "Verifying entitlements..."
if ! codesign -d --entitlements :- "$APP_BUNDLE" 2>/dev/null | grep -q 'com.apple.security.app-sandbox'; then
  echo "ERROR: Release app is missing com.apple.security.app-sandbox; the XPC update helper expects the main app to be sandboxed."
  exit 1
fi
if codesign -d --entitlements :- "$HELPER_OUT" 2>/dev/null | grep -q 'com.apple.security.app-sandbox'; then
  echo "ERROR: XPC update helper must NOT be sandboxed."
  exit 1
fi

PARENT_TEAM_ID="$(codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1 | awk -F'=' '/^TeamIdentifier=/ {print $2}')"
HELPER_TEAM_ID="$(codesign -dv --verbose=4 "$HELPER_OUT" 2>&1 | awk -F'=' '/^TeamIdentifier=/ {print $2}')"
if [[ -z "$PARENT_TEAM_ID" || "$PARENT_TEAM_ID" == "not set" ]]; then
  echo "ERROR: could not read TeamIdentifier from parent app signature."
  exit 1
fi
if [[ "$PARENT_TEAM_ID" != "$HELPER_TEAM_ID" ]]; then
  echo "ERROR: helper TeamIdentifier ($HELPER_TEAM_ID) does not match parent ($PARENT_TEAM_ID)."
  exit 1
fi
if [[ "$PARENT_TEAM_ID" != "$APPLE_TEAM_ID" ]]; then
  echo "ERROR: signed TeamIdentifier ($PARENT_TEAM_ID) does not match APPLE_TEAM_ID ($APPLE_TEAM_ID)."
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

echo "Verifying codesign on zip payload..."
if ! verify_macos_app_distribution "$ZIP_VERIFY_APP"; then
  echo "ERROR: codesign/stapler/distribution validation failed for app extracted from final zip"
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
run_codesign --force --options runtime --timestamp \
  --sign "$APPLE_SIGNING_IDENTITY" "$DMG_PATH"

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

echo "Verifying codesign on stapled .app..."
if ! verify_macos_app_distribution "$APP_BUNDLE"; then
  echo "ERROR: codesign/stapler/distribution validation failed for $APP_BUNDLE"
  exit 1
fi
echo "Verifying codesign on stapled DMG..."
if ! verify_macos_codesign "$DMG_PATH"; then
  echo "ERROR: codesign/stapler validation failed for $DMG_PATH"
  exit 1
fi

echo ""
echo "Done:"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
echo "  Signed with: $APPLE_SIGNING_IDENTITY"
echo "  Notarized and stapled."
