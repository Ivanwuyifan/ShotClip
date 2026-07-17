#!/bin/bash
# ShotClip uninstaller — quits the app, removes the login item, deletes the app and its data.
set -e

BUNDLE_ID="com.local.shotclip"
APP_PATHS=(
    "/Applications/ShotClip.app"
    "$HOME/Applications/ShotClip.app"
)

echo "Uninstalling ShotClip…"

echo "• Quitting ShotClip"
pkill -f "ShotClip.app" 2>/dev/null || true
sleep 1

echo "• Removing login item"
osascript -e 'tell application "System Events" to delete every login item whose name is "ShotClip"' 2>/dev/null || true
# SMAppService-registered items live in BTM; unregister by removing the app then letting macOS clean up,
# but also try to disable via the app if still present.

echo "• Removing the app"
for p in "${APP_PATHS[@]}"; do
    if [ -e "$p" ]; then
        rm -rf "$p"
        echo "    removed $p"
    fi
done

echo "• Clearing preferences"
defaults delete "$BUNDLE_ID" 2>/dev/null || true

echo "• Clearing temporary data"
rm -rf "$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null)ShotClip" 2>/dev/null || true
rm -rf /var/folders/*/*/T/ShotClip 2>/dev/null || true

echo "• Resetting granted permissions"
tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true

echo ""
echo "Done. If a leftover 'ShotClip' entry remains in"
echo "System Settings → General → Login Items, remove it there."
