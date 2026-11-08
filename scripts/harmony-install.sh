#!/usr/bin/env bash
# Sign the HarmonyOS keyboard and install it on a phone over USB, without DevEco Studio.
#   scripts/harmony-install.sh udid      print the connected phone's UDID (to register it in AppGallery Connect)
#   scripts/harmony-install.sh [hap]     sign (default: the HAP from harmony-build.sh) and install, then switch to ViPi
# Signing material lives outside the repo; .env holds the paths and password:
#   HARMONY_KEYSTORE, HARMONY_KEYSTORE_PASSWORD, HARMONY_KEY_ALIAS   key pair (its CSR goes to AppGallery Connect)
#   HARMONY_CERT      debug certificate (.cer) issued by AppGallery Connect for that CSR
#   HARMONY_PROFILE   debug profile (.p7b) for bundle dev.t43.vipi with the phone's UDID
# Tools come from the OpenHarmony SDK: OHOS_SDK=<sdk>/linux/<api>.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
: "${OHOS_SDK:?set OHOS_SDK to the SDK API folder that contains toolchains/}"
hdc="$OHOS_SDK/toolchains/hdc"
if [ "${1:-}" = udid ]; then
  "$hdc" list targets
  "$hdc" shell bm get --udid
  exit 0
fi
set -a; . "$here/.env"; set +a
: "${HARMONY_CERT:?set HARMONY_CERT in .env (debug certificate from AppGallery Connect)}"
: "${HARMONY_PROFILE:?set HARMONY_PROFILE in .env (debug profile from AppGallery Connect)}"
in="${1:-${HARMONY_BUILD_DIR:-${TMPDIR:-/tmp}/vipi-harmony}/entry/build/default/outputs/default/entry-default-unsigned.hap}"
out="$(dirname "$in")/entry-default-signed.hap"
java -jar "$OHOS_SDK/toolchains/lib/hap-sign-tool.jar" sign-app -mode localSign -signAlg SHA256withECDSA \
  -keyAlias "$HARMONY_KEY_ALIAS" -keyPwd "$HARMONY_KEYSTORE_PASSWORD" \
  -keystoreFile "$HARMONY_KEYSTORE" -keystorePwd "$HARMONY_KEYSTORE_PASSWORD" \
  -appCertFile "$HARMONY_CERT" -profileFile "$HARMONY_PROFILE" -inFile "$in" -outFile "$out" -signCode 1
"$hdc" install -r "$out"
"$hdc" shell ime -e dev.t43.vipi || true
"$hdc" shell ime -s dev.t43.vipi || true
"$hdc" shell ime -g || true
