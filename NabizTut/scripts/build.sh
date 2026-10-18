#!/bin/zsh
# Builds NabizTut.app into ./build and signs it. Pass --install to copy into ~/Applications.
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/build/NabizTut.app"
IDENTITY="${NABIZTUT_SIGN_IDENTITY:-Apple Development}"

# Fall back to ad-hoc signing when no matching certificate is installed (e.g. building from a fresh clone).
# Note: with ad-hoc signing macOS may ask for permissions again after every rebuild.
if [[ "$IDENTITY" != "-" ]] && ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "No '$IDENTITY' certificate found, signing ad-hoc."
    IDENTITY="-"
fi

cd "$ROOT"
swift build -c release --arch arm64

BIN="$(swift build -c release --arch arm64 --show-bin-path)/NabizTut"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NabizTut"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT"/Resources/*.lproj "$APP/Contents/Resources/"

codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --verbose=1 "$APP"
echo "Built: $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p ~/Applications
    pkill -x NabizTut 2>/dev/null || true
    rm -rf ~/Applications/NabizTut.app
    cp -R "$APP" ~/Applications/NabizTut.app
    echo "Installed: ~/Applications/NabizTut.app"
    open ~/Applications/NabizTut.app
fi
