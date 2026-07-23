#!/bin/bash
# ShotClip one-click installer.
# Double-click this file. It copies ShotClip into /Applications, clears the
# quarantine flag (so macOS won't block a self-signed app), and launches it.

set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/ShotClip.app"
DEST="/Applications/ShotClip.app"

echo "ShotClip installer"
echo "=================="

if [ ! -d "$APP" ]; then
    echo "Error: ShotClip.app not found next to this script."
    echo "Keep install.command and ShotClip.app in the same folder, then run again."
    read -r -p "Press Return to close."
    exit 1
fi

# If an older copy exists with a DIFFERENT code signature, its TCC grants
# (Screen Recording / Accessibility) are stale: System Settings shows them
# as ON, but they belong to the old signature and the new app stays blocked.
# Reset them so the new app prompts cleanly. Same-signature updates skip this.
if [ -d "$DEST" ]; then
    OLD_REQ=$(codesign -d -r- "$DEST" 2>&1 | grep "^designated" || true)
    NEW_REQ=$(codesign -d -r- "$APP" 2>&1 | grep "^designated" || true)
    if [ "$OLD_REQ" != "$NEW_REQ" ]; then
        echo "Old install has a different signature — clearing stale permission grants..."
        BUNDLE_ID=$(defaults read "$DEST/Contents/Info" CFBundleIdentifier 2>/dev/null || echo "com.local.shotclip")
        tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true
        tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
        echo "You'll be asked to grant Screen Recording / Accessibility again once."
    fi
fi

echo "Quitting any running ShotClip..."
osascript -e 'quit app "ShotClip"' >/dev/null 2>&1 || true
pkill -x ShotClip >/dev/null 2>&1 || true
sleep 1

echo "Copying to /Applications ..."
rm -rf "$DEST"
ditto "$APP" "$DEST"

echo "Clearing quarantine flag ..."
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "Launching ShotClip ..."
open "$DEST"

echo ""
echo "Done. ShotClip is now in your Applications folder and running."
echo "Look for its icon in the menu bar."
read -r -p "Press Return to close."
