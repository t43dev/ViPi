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

# Ký: có SIGN_IDENTITY (Developer ID) thì ký hardened runtime + notarize; không thì ad-hoc
# (ad-hoc: macOS gắn quyền Accessibility vào chữ ký nên mỗi bản build mới phải cấp lại).
ZIP="build/ViPi-$VERSION.zip"
if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
  if [ -n "${APPLE_ID:-}" ]; then
    ditto -c -k --keepParent "$APP" build/notarize.zip
    xcrun notarytool submit build/notarize.zip --apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" --wait
    xcrun stapler staple "$APP"
    rm build/notarize.zip
    spctl --assess --type execute --verbose "$APP"
  fi
else
  codesign --force --sign - "$APP"
  codesign --verify --verbose "$APP"
fi

ditto -c -k --keepParent "$APP" "$ZIP"
echo "built $ZIP"
