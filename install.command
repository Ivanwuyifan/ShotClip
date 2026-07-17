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
