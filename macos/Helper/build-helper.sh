#!/usr/bin/env bash
set -euo pipefail

# Builds run.rosie.dacx.UpdateHelper.xpc; a bundled XPC service that performs
# the self-update swap on behalf of the sandboxed main app.
#
# Usage:
#   build-helper.sh --output /path/to/Dacx.app/Contents/XPCServices/run.rosie.dacx.UpdateHelper.xpc [--version 1.2.3]

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: build-helper.sh must be run on macOS"
  exit 1
fi

OUTPUT=""
SHORT_VERSION=""
BUILD_VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT="$2"; shift 2 ;;
    --short-version) SHORT_VERSION="$2"; shift 2 ;;
    --build-version) BUILD_VERSION="$2"; shift 2 ;;
    *) echo "unknown arg $1"; exit 2 ;;
  esac
done

# CFBundleVersion must be one to three period-separated integers per Apple's
# bundle conventions; notarytool rejects anything else. If a caller forgot to
# pass --build-version (e.g. running this script directly), derive it from the
# SHORT_VERSION's leading integer/dot prefix as a best-effort fallback.
if [[ -z "$BUILD_VERSION" && -n "$SHORT_VERSION" ]]; then
  BUILD_VERSION="$(echo "$SHORT_VERSION" | grep -oE '^[0-9]+(\.[0-9]+){0,2}' || true)"
fi
if [[ -n "$BUILD_VERSION" && ! "$BUILD_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "ERROR: --build-version '$BUILD_VERSION' is not a valid CFBundleVersion (one to three period-separated integers)"
  exit 5
fi

if [[ -z "$OUTPUT" ]]; then
  echo "ERROR: --output is required"
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INFO_PLIST_SRC="$SCRIPT_DIR/Info.plist"
PROTOCOL_SRC="$SCRIPT_DIR/UpdateHelperProtocol.swift"
IMPL_SRC="$SCRIPT_DIR/UpdateHelperImpl.swift"
SERVICE_SRC="$SCRIPT_DIR/UpdateHelperService.swift"
RUNNER_PROTOCOL="$ROOT/macos/Runner/UpdateHelperProtocol.swift"

for f in "$INFO_PLIST_SRC" "$PROTOCOL_SRC" "$IMPL_SRC" "$SERVICE_SRC" "$RUNNER_PROTOCOL"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: required source $f not found"
    exit 3
  fi
done

# The Runner copy of UpdateHelperProtocol.swift must match the canonical Helper
# copy byte-for-byte; the @objc selectors are part of the wire protocol.
if ! diff -q "$PROTOCOL_SRC" "$RUNNER_PROTOCOL" >/dev/null; then
  echo "ERROR: macos/Helper/UpdateHelperProtocol.swift and macos/Runner/UpdateHelperProtocol.swift have drifted."
  echo "       The @objc protocol must be identical in both copies."
  diff -u "$PROTOCOL_SRC" "$RUNNER_PROTOCOL" || true
  exit 4
fi

EXEC_NAME="run.rosie.dacx.UpdateHelper"
CONTENTS_DIR="$OUTPUT/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
EXEC_PATH="$MACOS_DIR/$EXEC_NAME"

rm -rf "$OUTPUT"
mkdir -p "$MACOS_DIR"

cp "$INFO_PLIST_SRC" "$CONTENTS_DIR/Info.plist"

if [[ -n "$SHORT_VERSION" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT_VERSION" "$CONTENTS_DIR/Info.plist"
fi
if [[ -n "$BUILD_VERSION" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_VERSION" "$CONTENTS_DIR/Info.plist"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SOURCES=("$PROTOCOL_SRC" "$IMPL_SRC" "$SERVICE_SRC")

xcrun swiftc -O -target arm64-apple-macos15 \
  -framework Foundation \
  -framework CryptoKit \
  -o "$TMP/${EXEC_NAME}-arm64" "${SOURCES[@]}"

xcrun swiftc -O -target x86_64-apple-macos15 \
  -framework Foundation \
  -framework CryptoKit \
  -o "$TMP/${EXEC_NAME}-x86_64" "${SOURCES[@]}"

lipo -create -output "$EXEC_PATH" \
  "$TMP/${EXEC_NAME}-arm64" \
  "$TMP/${EXEC_NAME}-x86_64"

chmod +x "$EXEC_PATH"

echo "Built $EXEC_NAME → $OUTPUT"
