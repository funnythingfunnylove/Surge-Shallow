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
xcrun actool "$ROOT/Packaging/Assets.xcassets" \
    --compile "$RESOURCES" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --target-device mac \
    --output-format human-readable-text \
    --notices \
    --warnings
test -f "$RESOURCES/Assets.car"

MODULE_RESOURCE_BUNDLE="$ROOT/.build/release/SurgeShallow_SurgeModuleManagement.bundle"
if [[ -d "$MODULE_RESOURCE_BUNDLE" ]]; then
    INSTALLED_RESOURCE_BUNDLE="$RESOURCES/$(basename "$MODULE_RESOURCE_BUNDLE")"
    rm -rf "$INSTALLED_RESOURCE_BUNDLE"
    ditto "$MODULE_RESOURCE_BUNDLE" "$INSTALLED_RESOURCE_BUNDLE"

    # SwiftPM's command-line resource bundle Info.plist only contains the
    # development region. macOS 26 rejects that incomplete nested bundle at
    # process launch, so make it a fully described BNDL before signing the app.
    RESOURCE_PLIST="$INSTALLED_RESOURCE_BUNDLE/Info.plist"
    set_resource_plist_value() {
        local key="$1"
        local value="$2"
        if ! /usr/libexec/PlistBuddy -c "Set :$key $value" "$RESOURCE_PLIST" 2>/dev/null; then
            /usr/libexec/PlistBuddy -c "Add :$key string $value" "$RESOURCE_PLIST"
        fi
    }
    set_resource_plist_value CFBundleIdentifier com.surgeprofilerelay.module-resources
    set_resource_plist_value CFBundleName SurgeModuleManagementResources
    set_resource_plist_value CFBundlePackageType BNDL
    set_resource_plist_value CFBundleInfoDictionaryVersion 6.0
    set_resource_plist_value CFBundleVersion 1
fi

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "$APP"
