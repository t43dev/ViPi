#!/bin/bash
# Phát hành ViPi cho người dùng ngoài App Store: build universal trên Mac Studio, ký Developer ID,
# đóng DMG, notarize (App Store Connect API key) + staple, kéo DMG về build/ và đính vào GitHub release.
# Chạy từ máy dev: scripts/mac-release.sh 0.2.0      (tag v0.2.0 phải trỏ đúng commit HEAD)
# Apple notarize lâu (lần đầu của team: hàng giờ) → script chỉ chờ 15 phút; chưa xong thì in mã lần gửi,
# sau đó chạy: scripts/mac-release.sh 0.2.0 --finish   (staple + kiểm Gatekeeper + đưa lên GitHub, không cần secret)
# Cần trong $APPLE_DEV_DIR: developer-id.p12 + DEVID_CERT_P12_PASSWORD trong apple.env, ASC key.
# Chứng chỉ chỉ chép tạm vào một keychain riêng trên Mac rồi xoá ngay khi xong.
set -euo pipefail
VERSION=${1:?usage: scripts/mac-release.sh <version> [--finish]}
MAC=${MAC:-user@mac-host}
SSH="ssh -i $SSH_KEY -o BatchMode=yes $MAC"
SCP="scp -q -i $SSH_KEY"
AD=$APPLE_DEV_DIR
DIR=vipi-release-$VERSION      # thư mục làm việc trên Mac, riêng từng phiên bản
cd "$(dirname "$0")/.."
set -a; . $AD/apple.env; set +a

# DMG đã notarize trên Mac → staple, kiểm Gatekeeper, kéo về, đính vào GitHub release (bản chính thức, latest)
finish() {
  $SSH "cd ~/$DIR && xcrun stapler staple build/ViPi-$VERSION.dmg && spctl --assess --type open --context context:primary-signature --verbose build/ViPi-$VERSION.dmg"
  mkdir -p build
  $SCP $MAC:$DIR/build/ViPi-$VERSION.dmg build/
  ls -la build/ViPi-$VERSION.dmg
  gh release view v$VERSION -R kulinh/ViPi >/dev/null 2>&1 \
    || gh release create v$VERSION -R kulinh/ViPi --verify-tag --latest --generate-notes --title "ViPi $VERSION"
  gh release upload v$VERSION build/ViPi-$VERSION.dmg -R kulinh/ViPi --clobber
  echo "uploaded to release v$VERSION"
}
if [ "${2:-}" = "--finish" ]; then finish; exit; fi

[ -f $AD/developer-id.p12 ] || { echo "missing $AD/developer-id.p12"; exit 1; }

$SSH "rm -rf ~/$DIR && mkdir -p ~/$DIR/sign && chmod 700 ~/$DIR/sign"
git archive --format=tar HEAD | $SSH "tar -x -C ~/$DIR"
$SCP $AD/developer-id.p12 $MAC:$DIR/sign/devid.p12
$SCP "$ASC_KEY_FILE" $MAC:$DIR/sign/notary.p8
printf 'P12_PW=%q\nNOTARY_KEY_ID=%q\nNOTARY_ISSUER=%q\nVERSION=%q\nBUILD=%q\n' \
  "$DEVID_CERT_P12_PASSWORD" "$ASC_KEY_ID" "$ASC_ISSUER_ID" "$VERSION" "$(git rev-list --count HEAD)" \
  | $SSH "umask 077; cat > ~/$DIR/sign/env"

if ! $SSH "DIR=$DIR bash -s" <<'REMOTE'
set -euo pipefail
W=~/$DIR; S=$W/sign; KC=$S/vipi.keychain-db; KC_PW=$(uuidgen)
. $S/env
OLD_KCS=$(security list-keychains -d user | tr -d '"' | xargs)
cleanup() {
  security list-keychains -d user -s $OLD_KCS
  security delete-keychain "$KC" 2>/dev/null || true
  rm -rf "$S"
}
trap cleanup EXIT
security create-keychain -p "$KC_PW" "$KC"
security set-keychain-settings -lut 3600 "$KC"
security unlock-keychain -p "$KC_PW" "$KC"
security import "$S/devid.p12" -P "$P12_PW" -k "$KC" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PW" "$KC" >/dev/null
security list-keychains -d user -s "$KC" $OLD_KCS
IDENTITY=$(security find-identity -v -p codesigning "$KC" | awk -F'"' '/Developer ID Application/{print $2; exit}')
[ -n "$IDENTITY" ] || { echo "no Developer ID Application identity in p12"; exit 1; }
cd $W
# mạng nhà: IPv6 tới timestamp.apple.com treo với request POST → gọi thẳng địa chỉ IPv4
TS_IP=$(dig +short A timestamp.apple.com | grep -E '^[0-9.]+$' | head -1)
export TIMESTAMP_URL=${TS_IP:+http://$TS_IP/ts01}
VERSION=$VERSION BUILD=$BUILD SIGN_IDENTITY="$IDENTITY" \
  NOTARY_KEY=$S/notary.p8 NOTARY_KEY_ID=$NOTARY_KEY_ID NOTARY_ISSUER=$NOTARY_ISSUER NOTARY_TIMEOUT=15m \
  scripts/build-app.sh 2>&1 | grep -vE "^\[[0-9]+ ?/ ?[0-9]+\]|Current status: In Progress"
REMOTE
then
  # thường là hết 15 phút chờ notarize: lần gửi vẫn chạy tiếp bên Apple, secret đã được xoá khỏi Mac
  echo "Notarization not finished yet. When Apple accepts it, run: scripts/mac-release.sh $VERSION --finish"
  exit 1
fi
finish
