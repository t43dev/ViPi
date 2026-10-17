#!/bin/bash
# Build ViPi.app (universal arm64 + x86_64): Developer ID → signed, notarized DMG; otherwise ad-hoc zip, into build/.
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

# Ký: có SIGN_IDENTITY (Developer ID Application) thì ký hardened runtime, đóng DMG, notarize + staple;
# không thì ad-hoc + zip (ad-hoc: macOS gắn quyền Accessibility vào chữ ký nên mỗi bản build mới phải cấp lại).
# Notarize bằng App Store Connect API key (NOTARY_KEY/NOTARY_KEY_ID/NOTARY_ISSUER) hoặc Apple ID (APPLE_ID/...).
# máy chủ timestamp của Apple thỉnh thoảng không trả lời → thử lại; TIMESTAMP_URL để chọn máy chủ khác
sign() {
  for i in 1 2 3; do
    codesign --force --timestamp${TIMESTAMP_URL:+=$TIMESTAMP_URL} --sign "$SIGN_IDENTITY" "$@" && return
    sleep $((i * 3))
  done
  return 1
}
if [ -n "${SIGN_IDENTITY:-}" ]; then
  sign --options runtime "$APP"
  codesign --verify --strict --verbose=2 "$APP"

  DMG="build/ViPi-$VERSION.dmg"
  STAGE=build/dmg
  mkdir -p "$STAGE" && cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
  hdiutil create -quiet -volname "ViPi $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
  rm -rf "$STAGE"
  sign "$DMG"

  if [ -n "${NOTARY_KEY:-}" ]; then
    NOTARY=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
  elif [ -n "${APPLE_ID:-}" ]; then
    NOTARY=(--apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$APPLE_TEAM_ID")
  fi
  if [ -n "${NOTARY+x}" ]; then
    xcrun notarytool submit "$DMG" "${NOTARY[@]}" --wait --timeout 30m | tee build/notary.log
    grep -q "status: Accepted" build/notary.log || {
      ID=$(awk '/^  id:/{print $2; exit}' build/notary.log)
      [ -n "$ID" ] && xcrun notarytool log "$ID" "${NOTARY[@]}"
      exit 1
    }
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
  fi
  echo "built $DMG"
else
  codesign --force --sign - "$APP"
  codesign --verify --verbose "$APP"
  ZIP="build/ViPi-$VERSION.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "built $ZIP"
fi
