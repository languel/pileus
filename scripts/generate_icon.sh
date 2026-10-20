#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SVG_SRC="Resources/pileus-logo.svg"
PNG_1024="Resources/pileus-1024.png"
ICONSET="build/Pileus.iconset"
OUTPUT_ICNS="Resources/Pileus.icns"

if [ ! -f "$SVG_SRC" ]; then
    echo "Error: $SVG_SRC not found"
    exit 1
fi

echo "Rasterizing $SVG_SRC to $PNG_1024..."
magick -background none -size 1024x1024 "$SVG_SRC" "$PNG_1024"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

echo "Generating icon resolutions..."
sips -z 16 16     "$PNG_1024" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32     "$PNG_1024" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$PNG_1024" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64     "$PNG_1024" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$PNG_1024" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256   "$PNG_1024" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$PNG_1024" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512   "$PNG_1024" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$PNG_1024" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$PNG_1024" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

echo "Packaging $OUTPUT_ICNS..."
iconutil -c icns "$ICONSET" -o "$OUTPUT_ICNS"
cp "$OUTPUT_ICNS" "Pileus.icns"

rm -rf "$ICONSET"
echo "Done! Generated $OUTPUT_ICNS"
