#!/bin/zsh
# Builds TikKare.app into ./build and signs it. Pass --install to copy into ~/Applications.
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/build/TikKare.app"
IDENTITY="${KESIT_SIGN_IDENTITY:-Apple Development}"

# Fall back to ad-hoc signing when no matching certificate is installed (e.g. building from a fresh clone).
# Note: with ad-hoc signing macOS asks for Screen Recording permission again after every rebuild.
if [[ "$IDENTITY" != "-" ]] && ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "No '$IDENTITY' certificate found, signing ad-hoc."
    IDENTITY="-"
fi

cd "$ROOT"
swift build -c release --arch arm64

BIN="$(swift build -c release --arch arm64 --show-bin-path)/TikKare"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TikKare"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT"/Resources/*.lproj "$APP/Contents/Resources/"

codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --verbose=1 "$APP"
echo "Built: $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p ~/Applications
    pkill -x TikKare 2>/dev/null || true
    rm -rf ~/Applications/TikKare.app
    cp -R "$APP" ~/Applications/TikKare.app
    echo "Installed: ~/Applications/TikKare.app"
    open ~/Applications/TikKare.app
fi
