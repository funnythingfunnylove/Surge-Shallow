#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Surge Shallow.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

cd "$ROOT"
"$ROOT/scripts/build_app_icon.sh"
swift build -c release

mkdir -p "$MACOS" "$RESOURCES"
install -m 755 "$ROOT/.build/release/SurgeShallow" "$MACOS/SurgeShallow"
install -m 644 "$ROOT/Packaging/Info.plist" "$CONTENTS/Info.plist"
install -m 644 "$ROOT/Packaging/AppIcon.icns" "$RESOURCES/AppIcon.icns"

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "$APP"
