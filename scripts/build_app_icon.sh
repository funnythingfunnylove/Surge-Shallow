#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MASTER="$ROOT/Assets/AppIcon/AppIcon-1024.png"
ICONSET="$ROOT/Packaging/AppIcon.iconset"
ICNS="$ROOT/Packaging/AppIcon.icns"

mkdir -p "$ROOT/Assets/AppIcon" "$ICONSET"

if [[ ! -f "$MASTER" ]]; then
    echo "Missing App Icon master: $MASTER" >&2
    exit 1
fi

WIDTH="$(sips -g pixelWidth "$MASTER" 2>/dev/null | awk '/pixelWidth/ { print $2 }')"
HEIGHT="$(sips -g pixelHeight "$MASTER" 2>/dev/null | awk '/pixelHeight/ { print $2 }')"
if [[ "$WIDTH" != "1024" || "$HEIGHT" != "1024" ]]; then
    echo "App Icon master must be 1024x1024; found ${WIDTH:-unknown}x${HEIGHT:-unknown}" >&2
    exit 1
fi

sips -z 16 16 "$MASTER" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$MASTER" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$MASTER" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$MASTER" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$MASTER" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$MASTER" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$MASTER" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$MASTER" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$MASTER" --out "$ICONSET/icon_512x512.png" >/dev/null
install -m 644 "$MASTER" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$ICNS"
echo "$ICNS"
