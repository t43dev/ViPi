#!/bin/bash
# Quay video cho App Review trên iPhone thật cắm vào Mac (xem ios/ViPiUITests/DemoTests.swift). Chạy trên HQ-01.
#   scripts/ios-demo.sh build                 chép mã sang Mac, build bản Release ký development, cài lên máy
#   scripts/ios-demo.sh <Demo|Reset|Dump> [record]   chạy một bài test (record: bật Screen Recording)
#   scripts/ios-demo.sh pull <file.mp4>       lấy video mới nhất trong DCIM về HQ-01
# Cần: .env có MAC, SSH_KEY, APPLE_ENV, DEVICE (UDID máy thật); máy bật Developer Mode, mở khoá.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; . "${APPLE_ENV:?}"; set +a
: "${DEVICE:?DEVICE=<udid> missing in .env}"
SSH="ssh -i $SSH_KEY -o BatchMode=yes $MAC"
case "${1:-}" in
build)
  git ls-files -co --exclude-standard -z | grep -zv '^android/\|^harmony/\|^site/\|^assets/' \
    | tar --null -T - -czf - | $SSH 'mkdir -p ~/vipi-ios && tar -xzf - -C ~/vipi-ios'
  # chứng chỉ Apple Development + 3 profile development (app, bàn phím, runner của UI test) chỉ nằm trên Mac lúc build
  PROF=$(dirname "$APPLE_ENV")/profiles
  $SSH 'mkdir -p ~/vipi-demo-sign && chmod 700 ~/vipi-demo-sign'
  for f in "$DEV_CERT_P12" "$PROF/ViPi_Dev.mobileprovision" "$PROF/ViPi_Keyboard_Dev.mobileprovision" "$PROF/ViPi_UITests_Dev.mobileprovision"; do
    scp -q -i "$SSH_KEY" "$f" "$MAC:vipi-demo-sign/"
  done
  printf '%s' "$DEV_CERT_P12_PASSWORD" | $SSH 'cat > ~/vipi-demo-sign/p12pw'
  $SSH "DEV=$DEVICE bash -s" <<'MAC'
set -euo pipefail
export PATH=$HOME/.cargo/bin:/opt/homebrew/bin:$PATH
S=~/vipi-demo-sign; KC=$S/demo.keychain-db; KC_PW=$(uuidgen)
OLD_KCS=$(security list-keychains -d user | tr -d '"' | xargs)
cleanup() { security list-keychains -d user -s $OLD_KCS; security delete-keychain "$KC" 2>/dev/null || true; rm -rf "$S"; }
trap cleanup EXIT
security create-keychain -p "$KC_PW" "$KC"; security set-keychain-settings -lut 3600 "$KC"; security unlock-keychain -p "$KC_PW" "$KC"
security import "$S/apple-development.p12" -P "$(cat "$S/p12pw")" -k "$KC" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PW" "$KC" >/dev/null
security list-keychains -d user -s "$KC" $OLD_KCS
ID=$(security find-identity -v -p codesigning "$KC" | awk 'NR==1{print $2}')
cd ~/vipi-ios
[ -f ios/Core/ViPiCoreFFI.swift ] || scripts/ios-core.sh >/dev/null
mkdir -p ios/Suggest && cp -n ~/vipi-suggest-cache/*.bin ios/Suggest/ 2>/dev/null || true
scripts/ios-suggest-models.sh
cd ios && xcodegen generate --quiet
LOG=build/demo-build.log; mkdir -p build
# bản Release như TestFlight (build 14), build không ký rồi ký tay bằng chứng chỉ development
xcodebuild build-for-testing -project ViPi.xcodeproj -scheme ViPi -configuration Release -destination "id=$DEV" \
  -derivedDataPath build/dd-device CODE_SIGNING_ALLOWED=NO CURRENT_PROJECT_VERSION=14 >$LOG 2>&1 \
  || { grep -E "error|FAILED" $LOG | sort -u | head -20; exit 1; }
P=build/dd-device/Build/Products/Release-iphoneos
sign() { # <bundle> [profile]: ký các framework / plugin bên trong trước, rồi tới bundle (entitlements lấy từ profile)
  local b=$1 prof=${2:-}
  for f in "$b"/Frameworks/*.framework "$b"/Frameworks/*.dylib; do [ -e "$f" ] && codesign -f -s "$ID" --keychain "$KC" "$f" >/dev/null 2>&1; done
  if [ -n "$prof" ]; then
    cp "$S/$prof" "$b/embedded.mobileprovision"
    security cms -D -i "$S/$prof" | plutil -extract Entitlements xml1 -o "$S/ent.plist" -
    plutil -remove keychain-access-groups "$S/ent.plist" 2>/dev/null || true
    codesign -f -s "$ID" --keychain "$KC" --entitlements "$S/ent.plist" --generate-entitlement-der "$b"
  else
    codesign -f -s "$ID" --keychain "$KC" "$b"
  fi
}
sign $P/ViPi.app/PlugIns/ViPiKeyboard.appex ViPi_Keyboard_Dev.mobileprovision
sign $P/ViPi.app ViPi_Dev.mobileprovision
R=$P/ViPiUITests-Runner.app
sign $R/PlugIns/ViPiUITests.xctest
sign $R ViPi_UITests_Dev.mobileprovision
codesign -v --deep --strict $P/ViPi.app && codesign -v --deep $R
# chỉ chạy bộ test, không cho xcodebuild cài lại app (app cài bằng devicectl)
X=$(ls build/dd-device/Build/Products/*.xctestrun | head -1)
for k in UITargetAppPath DependentProductPaths; do /usr/libexec/PlistBuddy -c "Delete :TestConfigurations:0:TestTargets:0:$k" "$X" 2>/dev/null || true; done
xcrun devicectl device install app --device "$DEV" $P/ViPi.app | tail -2
echo BUILD_OK
MAC
  ;;
Demo|Reset|Dump|Setup|Globe|DndOff)
  $SSH "DEV=$DEVICE T=$1 REC=${2:-} bash -s" <<'MAC'
export PATH=/opt/homebrew/bin:$PATH
cd ~/vipi-ios/ios
R=$(ls build/dd-device/Build/Products/*.xctestrun | head -1)
env ${REC:+TEST_RUNNER_VIPI_RECORD=1} xcodebuild test-without-building -xctestrun "$R" -destination "id=$DEV" \
  -only-testing:ViPiUITests/DemoTests/test$T 2>&1 | tee build/demo-$T.log | grep -E "VIPI_|error:|\*\* TEST|failed" | cut -c 1-300
[ "$T" != Demo ] && sed -n '/VIPI_DUMP/,$p' build/demo-$T.log > build/demo-dump.txt || true
MAC
  ;;
pull)
  $SSH "export PATH=/opt/homebrew/bin:\$PATH; f=\$(afcclient ls /DCIM/100APPLE | grep -i mp4 | sort | tail -1); rm -f /tmp/vipi-demo.mp4; afcclient get /DCIM/100APPLE/\$f /tmp/vipi-demo.mp4 >/dev/null && echo \$f"
  scp -q -i "$SSH_KEY" "$MAC:/tmp/vipi-demo.mp4" "${2:?file}"
  ;;
*) sed -n 2,6p "$0"; exit 1;;
esac
