#!/usr/bin/env bash
# Build libvipi.so (Rust core + NAPI bridge) for the HarmonyOS keyboard and copy it into harmony/entry/libs/.
# Needs the OpenHarmony SDK (API 20+) and the Rust ohos targets:
#   rustup target add aarch64-unknown-linux-ohos x86_64-unknown-linux-ohos
#   OHOS_SDK=<sdk>/linux/20 scripts/harmony-native.sh      (<sdk>/linux/20 holds native/, ets/, toolchains/)
set -euo pipefail
cd "$(dirname "$0")/../harmony/native"
: "${OHOS_SDK:?set OHOS_SDK to the SDK API folder that contains native/}"
export OHOS_NDK_HOME="$OHOS_SDK"
LLVM="$OHOS_SDK/native/llvm/bin"
# the prebuilt library is committed: keep local paths out of it
export RUSTFLAGS="--remap-path-prefix=$HOME=/home --remap-path-prefix=$(cd ../.. && pwd)=/vipi"
for pair in aarch64-unknown-linux-ohos:arm64-v8a x86_64-unknown-linux-ohos:x86_64; do
  target=${pair%%:*}; abi=${pair##*:}
  env_target=$(echo "$target" | tr 'a-z-' 'A-Z_')
  export "CARGO_TARGET_${env_target}_LINKER=$LLVM/$target-clang"
  export "CC_${target//-/_}=$LLVM/$target-clang"
  export "AR_${target//-/_}=$LLVM/llvm-ar"
  cargo build --release --target "$target"
  mkdir -p "../entry/libs/$abi"
  cp "target/$target/release/libvipi.so" "../entry/libs/$abi/libvipi.so"
  "$LLVM/llvm-strip" "../entry/libs/$abi/libvipi.so"
  echo "libs/$abi/libvipi.so $(stat -c %s "../entry/libs/$abi/libvipi.so") bytes"
done
