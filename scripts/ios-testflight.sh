#!/bin/bash
# Build ViPi iOS từ code đã commit (HEAD) trên Mac, ký bằng chứng chỉ Apple Distribution chung của team, upload TestFlight.
#   scripts/ios-testflight.sh
# Cần: .env có MAC, SSH_KEY, APPLE_ENV; App Group và profile đã có (scripts/ios-profiles.sh); app record dev.t43.vipi trên App Store Connect.
# Chứng chỉ, profile và khoá ASC chép tạm lên Mac vào một keychain riêng, xoá khi xong (kể cả khi lỗi giữa chừng).
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; . "${APPLE_ENV:?APPLE_ENV missing in .env}"; set +a
SSH="ssh -i $SSH_KEY -o BatchMode=yes $MAC"
SCP="scp -q -i $SSH_KEY"
ASC="python3 scripts/asc.py"
PROFILES=$(dirname "$APPLE_ENV")/profiles
W=vipi-release

APP_ID=$($ASC GET "/v1/apps?filter[bundleId]=dev.t43.vipi" | sed 1d | python3 -c "import sys,json;d=json.load(sys.stdin)['data'];print(d[0]['id'] if d else '')")
[ -n "$APP_ID" ] || { echo "No App Store Connect app record for dev.t43.vipi: create it on appstoreconnect.apple.com first" >&2; exit 1; }
LAST=$($ASC GET "/v1/apps/$APP_ID/buildUploads?fields[buildUploads]=cfBundleVersion&limit=200" | sed 1d |
  python3 -c "import sys,json;print(max([int(b['attributes']['cfBundleVersion']) for b in json.load(sys.stdin).get('data',[])] or [0]))")
BUILD=$((LAST + 1))
echo "build $BUILD from $(git rev-parse --short HEAD)"

$SSH "rm -rf ~/$W && mkdir -p ~/$W/sign && chmod 700 ~/$W/sign"
git archive HEAD core Resources ios scripts | $SSH "tar xf - -C ~/$W"
$SCP "$DIST_CERT_P12" "$MAC:$W/sign/dist.p12"
$SCP "$PROFILES/ViPi_AppStore.mobileprovision" "$MAC:$W/sign/app.mobileprovision"
$SCP "$PROFILES/ViPi_Keyboard_AppStore.mobileprovision" "$MAC:$W/sign/keyboard.mobileprovision"
$SCP "$ASC_KEY_FILE" "$MAC:$W/sign/AuthKey.p8"
# mật khẩu P12 qua stdin (không nằm trong tham số ssh, ps thấy được)
printf '%s' "$DIST_CERT_P12_PASSWORD" | $SSH "umask 077; cat > ~/$W/sign/p12pw"
trap '$SSH "rm -rf ~/$W/sign" || true' EXIT

TMP=$(mktemp)
cat > "$TMP" <<'MAC'
set -euo pipefail
export PATH=$HOME/.cargo/bin:/opt/homebrew/bin:$PATH
W=~/vipi-release; S=$W/sign; KC=$S/vipi.keychain-db; KC_PW=$(uuidgen)
OLD_KCS=$(security list-keychains -d user | tr -d '"' | xargs)
cleanup() { security list-keychains -d user -s $OLD_KCS; security delete-keychain "$KC" 2>/dev/null || true; rm -rf "$S"; }
trap cleanup EXIT
security create-keychain -p "$KC_PW" "$KC"
security set-keychain-settings -lut 3600 "$KC"
security unlock-keychain -p "$KC_PW" "$KC"
security import "$S/dist.p12" -P "$(cat "$S/p12pw")" -k "$KC" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PW" "$KC" >/dev/null
security list-keychains -d user -s "$KC" $OLD_KCS
for p in app keyboard; do
  UUID=$(security cms -D -i "$S/$p.mobileprovision" | plutil -extract UUID raw -)
  for d in ~/Library/MobileDevice/Provisioning\ Profiles ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles; do
    mkdir -p "$d"; cp "$S/$p.mobileprovision" "$d/$UUID.mobileprovision"
  done
done
cd $W
command -v xcodegen >/dev/null || brew install xcodegen >/dev/null
scripts/ios-core.sh >$W/core.log 2>&1 || { echo CORE_FAIL; tail -20 $W/core.log; exit 1; }
# mô hình gợi ý từ không nằm trong git: dùng lại bản đã tải của lần build trước nếu có (65 MB)
mkdir -p ios/Suggest ~/vipi-suggest-cache && cp -n ~/vipi-suggest-cache/*.bin ios/Suggest/ 2>/dev/null || true
scripts/ios-suggest-models.sh || { echo MODELS_FAIL; exit 1; }
cp -n ios/Suggest/*.bin ~/vipi-suggest-cache/ 2>/dev/null || true
cd ios
xcodegen generate --quiet
cat > $W/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>manual</string>
  <key>provisioningProfiles</key><dict>
    <key>dev.t43.vipi</key><string>ViPi AppStore</string>
    <key>dev.t43.vipi.keyboard</key><string>ViPi Keyboard AppStore</string>
  </dict>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
if ! xcodebuild -project ViPi.xcodeproj -scheme ViPi -configuration Release -destination generic/platform=iOS \
  -archivePath $W/ViPi.xcarchive DEVELOPMENT_TEAM="$TEAM" CURRENT_PROJECT_VERSION="$BUILD" archive > $W/archive.log 2>&1; then
  echo ARCHIVE_FAIL; grep -E 'error:|errSec' $W/archive.log | sort -u | head -20; exit 1
fi
echo ARCHIVE_OK
if ! xcodebuild -exportArchive -archivePath $W/ViPi.xcarchive -exportOptionsPlist $W/ExportOptions.plist \
  -exportPath $W/export -authenticationKeyPath "$S/AuthKey.p8" \
  -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" > $W/export.log 2>&1; then
  echo UPLOAD_FAIL; grep -iE 'error' $W/export.log | sort -u | head -20; exit 1
fi
echo UPLOAD_OK
MAC
$SCP "$TMP" "$MAC:$W/release.sh"; rm -f "$TMP"
$SSH "TEAM=$APPLE_TEAM_ID BUILD=$BUILD ASC_KEY_ID=$ASC_KEY_ID ASC_ISSUER_ID=$ASC_ISSUER_ID bash ~/$W/release.sh"

echo "waiting for App Store Connect to process build $BUILD…"
STATE=""
for _ in $(seq 60); do
  STATE=$($ASC GET "/v1/apps/$APP_ID/buildUploads?fields[buildUploads]=cfBundleVersion,state&limit=200" | sed 1d |
    python3 -c "
import sys,json
for b in json.load(sys.stdin).get('data',[]):
    a=b['attributes']
    if a['cfBundleVersion']=='$BUILD':
        s=a['state']; print(s['state'], *[e['code']+': '+e['description'][:200] for e in s.get('errors',[])])")
  case "$STATE" in COMPLETE*|FAILED*) break ;; esac
  sleep 20
done
echo "build $BUILD: ${STATE:-unknown}"
[[ $STATE == COMPLETE* ]]
