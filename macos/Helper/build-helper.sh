#!/usr/bin/env bash
set -euo pipefail

# Builds dacx-update-helper as a universal (arm64 + x86_64) Mach-O binary.
# Usage: build-helper.sh --output /path/to/Dacx.app/Contents/MacOS/dacx-update-helper

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: build-helper.sh must be run on macOS"
  exit 1
fi

OUTPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT="$2"; shift 2 ;;
    *) echo "unknown arg $1"; exit 2 ;;
  esac
done

if [[ -z "$OUTPUT" ]]; then
  echo "ERROR: --output is required"
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SCRIPT_DIR/DacxUpdateHelper.swift"

if [[ ! -f "$SOURCE" ]]; then
  echo "ERROR: source $SOURCE not found"
  exit 3
fi

mkdir -p "$(dirname "$OUTPUT")"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

xcrun swiftc -O -target arm64-apple-macos11 \
  -o "$TMP/dacx-update-helper-arm64" "$SOURCE"

xcrun swiftc -O -target x86_64-apple-macos11 \
  -o "$TMP/dacx-update-helper-x86_64" "$SOURCE"

lipo -create -output "$OUTPUT" \
  "$TMP/dacx-update-helper-arm64" \
  "$TMP/dacx-update-helper-x86_64"

chmod +x "$OUTPUT"
echo "Built dacx-update-helper → $OUTPUT"
