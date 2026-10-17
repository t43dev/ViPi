#!/bin/bash
# Build ViPi.app (universal arm64 + x86_64), ad-hoc sign it and zip it into build/.
# Run on macOS with Xcode command line tools: VERSION=0.1.0 BUILD=1 scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-1}"
APP=build/ViPi.app

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ViPi" "$APP/Contents/MacOS/ViPi"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
[ -f Resources/pinyin.tsv ] && cp Resources/pinyin.tsv "$APP/Contents/Resources/"
[ -d Resources/AppIcon.iconset ] && iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: macOS ties the Accessibility grant to it, so every new build must be re-granted.
codesign --force --sign - "$APP"
codesign --verify --verbose "$APP"

ditto -c -k --keepParent "$APP" "build/ViPi-$VERSION.zip"
echo "built build/ViPi-$VERSION.zip"
