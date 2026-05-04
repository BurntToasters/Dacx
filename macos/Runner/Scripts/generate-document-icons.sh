#!/bin/sh
# Regenerate macos/Runner/dacx_music_icon.icns from assets/dacx_music_icon.png

set -euo pipefail

# When run from Xcode, $SRCROOT points at macos/.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

SOURCE_PNG="$REPO_ROOT/assets/dacx_music_icon.png"
OUT_ICNS="$REPO_ROOT/macos/Runner/dacx_music_icon.icns"

if [ ! -f "$SOURCE_PNG" ]; then
  echo "warning: $SOURCE_PNG not found; skipping document icon generation"
  exit 0
fi

if [ -f "$OUT_ICNS" ] && [ "$OUT_ICNS" -nt "$SOURCE_PNG" ]; then
  # Up to date.
  exit 0
fi

echo "Generating $(basename "$OUT_ICNS") from $(basename "$SOURCE_PNG")…"

TMP_ICONSET="$(mktemp -d)/dacx_music_icon.iconset"
mkdir -p "$TMP_ICONSET"

gen() {
  size="$1"
  name="$2"
  sips -z "$size" "$size" "$SOURCE_PNG" --out "$TMP_ICONSET/$name" >/dev/null
}

gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
gen 1024 icon_512x512@2x.png

iconutil -c icns "$TMP_ICONSET" -o "$OUT_ICNS"
rm -rf "$TMP_ICONSET"

echo "✓ wrote $OUT_ICNS"
