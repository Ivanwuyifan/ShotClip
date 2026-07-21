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
[ -f MenuBarIcon.png ] && cp MenuBarIcon.png "$APP/Contents/Resources/MenuBarIcon.png"

CERT="ShotClip Self-Signed"

# Create the stable self-signed codesigning cert on first build, so TCC
# permissions (Screen Recording / Accessibility) survive rebuilds instead of
# silently falling back to ad-hoc signing (which changes every build).
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT"; then
    echo "Creating stable self-signed cert '$CERT' (one-time)..."
    TMPCERT=$(mktemp -d)
    openssl req -x509 -newkey rsa:2048 -keyout "$TMPCERT/key.pem" -out "$TMPCERT/cert.pem" \
        -days 3650 -nodes -subj "/CN=$CERT" \
        -addext "extendedKeyUsage=codeSigning" -addext "keyUsage=digitalSignature" \
        -addext "basicConstraints=critical,CA:false" 2>/dev/null
    openssl pkcs12 -export -legacy -out "$TMPCERT/cert.p12" \
        -inkey "$TMPCERT/key.pem" -in "$TMPCERT/cert.pem" -passout pass:shotclip 2>/dev/null \
        || openssl pkcs12 -export -out "$TMPCERT/cert.p12" \
        -inkey "$TMPCERT/key.pem" -in "$TMPCERT/cert.pem" -passout pass:shotclip
    security import "$TMPCERT/cert.p12" -k ~/Library/Keychains/login.keychain-db \
        -P shotclip -T /usr/bin/codesign
    security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db \
        "$TMPCERT/cert.pem" 2>/dev/null || true
    rm -rf "$TMPCERT"
fi

if codesign --force --deep --sign "$CERT" "$APP" 2>/dev/null; then
    echo "Signed with stable self-signed cert ($CERT) — screen-recording permission persists across rebuilds."
else
    echo "Ad-hoc signing (stable cert '$CERT' not available — screen-recording permission won't persist across rebuilds)..."
    codesign --force --deep --sign - "$APP"
fi

# Package a release zip containing the app + one-click installer.
if [ -f install.command ]; then
    DIST="dist/ShotClip"
    rm -rf dist
    mkdir -p "$DIST"
    ditto "$APP" "$DIST/ShotClip.app"
    cp install.command "$DIST/install.command"
    chmod +x "$DIST/install.command"
    rm -f ShotClip.app.zip
    (cd dist && ditto -c -k --keepParent ShotClip ../ShotClip.app.zip)
    echo "Packaged ShotClip.app.zip (app + install.command)"
fi

echo ""
echo "Built $APP"
echo "Run it with:  open $APP"
echo ""
echo "First launch will prompt for Screen Recording permission (for screenshots)."
echo "Grant it in System Settings > Privacy & Security > Screen Recording, then relaunch."
