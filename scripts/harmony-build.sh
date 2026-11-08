#!/usr/bin/env bash
# Compile check of the HarmonyOS keyboard on Linux, without DevEco Studio.
# The project targets HarmonyOS (DevEco opens harmony/ as is). Here a copy is built against the public
# OpenHarmony SDK of the same API level, so ArkTS type errors show up without a Huawei account.
# Needs: OpenHarmony SDK unpacked as <sdk>/linux/<api>/{ets,js,native,toolchains,previewer},
#        hvigor from the HarmonyOS npm registry: npm i @ohos/hvigor @ohos/hvigor-ohos-plugin
#          (with @ohos:registry=https://repo.harmonyos.com/npm/ in .npmrc), and Java 17+.
# Usage: OHOS_SDK_ROOT=<sdk>/linux HVIGOR_NODE_MODULES=<dir>/node_modules scripts/harmony-build.sh [assembleHap]
set -euo pipefail
: "${OHOS_SDK_ROOT:?set OHOS_SDK_ROOT to the SDK linux/ folder}"
: "${HVIGOR_NODE_MODULES:?set HVIGOR_NODE_MODULES to the node_modules that holds @ohos/hvigor}"
here="$(cd "$(dirname "$0")/.." && pwd)"
out="${HARMONY_BUILD_DIR:-${TMPDIR:-/tmp}/vipi-harmony}"
mkdir -p "$out"
rsync -a --delete --exclude /build --exclude /entry/build --exclude /.hvigor --exclude /native/target \
  --exclude /oh_modules --exclude /entry/oh_modules "$here/harmony/" "$out/"
# OpenHarmony SDK instead of HarmonyOS: numeric API levels and runtimeOS OpenHarmony
api=$(ls "$OHOS_SDK_ROOT" | grep -E '^[0-9]+$' | sort -n | tail -1)
sed -i -E "s/\"targetSdkVersion\": \"[^\"]+\"/\"targetSdkVersion\": $api/; s/\"compatibleSdkVersion\": \"[^\"]+\"/\"compatibleSdkVersion\": $api, \"compileSdkVersion\": $api/; s/\"runtimeOS\": \"HarmonyOS\"/\"runtimeOS\": \"OpenHarmony\"/" "$out/build-profile.json5"
# OpenHarmony names the phone device type "default"
sed -i -E 's/"deviceTypes": \[[^]]*\]/"deviceTypes": ["default", "tablet"]/' "$out/entry/src/main/module.json5"
# what ohpm install would do for the local native types package
mkdir -p "$out/entry/oh_modules"
ln -sfn ../src/main/cpp/types/libvipi "$out/entry/oh_modules/libvipi.so"
cd "$out"
export OHOS_BASE_SDK_HOME="$OHOS_SDK_ROOT" NODE_PATH="$HVIGOR_NODE_MODULES" VIPI_RESOURCES="$here/Resources"
node "$HVIGOR_NODE_MODULES/@ohos/hvigor/bin/hvigor.js" --mode module -p module=entry@default -p product=default \
  -p buildMode="${BUILD_MODE:-debug}" "${1:-assembleHap}" --no-daemon
find "$out/entry/build" -name '*.hap' -newer "$out/build-profile.json5" -exec ls -la {} \;
