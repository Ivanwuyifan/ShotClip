#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "Building release binary..."
swift build -c release

APP="ShotClip.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp Info.plist "$APP/Contents/Info.plist"
cp ".build/release/ShotClip" "$APP/Contents/MacOS/ShotClip"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
if [ ! -f MenuBarIcon.png ] && [ -f icon_1024.png ]; then
    sips -z 44 44 icon_1024.png --out MenuBarIcon.png >/dev/null 2>&1
fi
[ -f MenuBarIcon.png ] && cp MenuBarIcon.png "$APP/Contents/Resources/MenuBarIcon.png"

CERT="ShotClip Self-Signed"
if codesign --force --deep --sign "$CERT" "$APP" 2>/dev/null; then
    echo "Signed with stable self-signed cert ($CERT) — screen-recording permission persists across rebuilds."
else
    echo "Ad-hoc signing (stable cert '$CERT' not available — screen-recording permission won't persist across rebuilds)..."
    codesign --force --deep --sign - "$APP"
fi

echo ""
echo "Built $APP"
echo "Run it with:  open $APP"
echo ""
echo "First launch will prompt for Screen Recording permission (for screenshots)."
echo "Grant it in System Settings > Privacy & Security > Screen Recording, then relaunch."
