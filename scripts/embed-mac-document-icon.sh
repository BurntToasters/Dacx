#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: must run on macOS." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
APP_BUNDLE="${1:-$ROOT/build/macos/Build/Products/Release/Dacx.app}"
SOURCE_PNG="$ROOT/assets/dacx_music_icon.png"
DEST_ICNS="$APP_BUNDLE/Contents/Resources/dacx_music_icon.icns"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "WARN: app bundle not found at $APP_BUNDLE; skipping icon embed." >&2
  exit 0
fi
if [[ ! -f "$SOURCE_PNG" ]]; then
  echo "WARN: $SOURCE_PNG missing; document icon will be default." >&2
  exit 0
fi

ICONSET_DIR="$ROOT/build/mac-audio-icon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
trap 'rm -rf "$ICONSET_DIR"' EXIT
while IFS=: read -r icon_name size; do
  sips -z "$size" "$size" "$SOURCE_PNG" --out "$ICONSET_DIR/$icon_name" >/dev/null
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
iconutil -c icns "$ICONSET_DIR" -o "$DEST_ICNS"
echo "Embedded audio document icon at $DEST_ICNS"
