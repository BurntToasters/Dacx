#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Skipping macOS XPC helper build check on non-macOS host."
  exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

HELPER_OUT="$TMPDIR/run.rosie.dacx.UpdateHelper.xpc"
EXEC_PATH="$HELPER_OUT/Contents/MacOS/run.rosie.dacx.UpdateHelper"
INFO_PLIST="$HELPER_OUT/Contents/Info.plist"

bash "$ROOT/macos/Helper/build-helper.sh" \
  --output "$HELPER_OUT" \
  --short-version "0.0.0-ci" \
  --build-version "1"

if [[ ! -x "$EXEC_PATH" ]]; then
  echo "ERROR: helper executable missing or not executable: $EXEC_PATH"
  exit 1
fi

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "ERROR: helper Info.plist missing: $INFO_PLIST"
  exit 1
fi

ARCHS="$(lipo -archs "$EXEC_PATH")"
if [[ "$ARCHS" != *"arm64"* || "$ARCHS" != *"x86_64"* ]]; then
  echo "ERROR: helper must be universal arm64/x86_64, got: $ARCHS"
  exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
if [[ "$BUNDLE_ID" != "run.rosie.dacx.UpdateHelper" ]]; then
  echo "ERROR: helper bundle id is $BUNDLE_ID"
  exit 1
fi

echo "macOS XPC helper build check OK ($ARCHS)."
