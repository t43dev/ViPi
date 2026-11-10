#!/bin/bash
# Lõi Rust cho iOS (chạy trên Mac có Xcode): thư viện tĩnh cho iPhone/iPad thật và simulator (Apple Silicon),
# đóng thành ios/Core/ViPiCore.xcframework, kèm binding Swift sinh bằng uniffi (ios/Core/ViPiCoreFFI.swift).
# Cả hai không lưu trong git; chạy lại mỗi khi core/ thay đổi.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
OUT=$ROOT/ios/Core
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"
export IPHONEOS_DEPLOYMENT_TARGET=26.0
TARGETS=(aarch64-apple-ios aarch64-apple-ios-sim)
rustup target add "${TARGETS[@]}" >/dev/null 2>&1 || true

cd core
# thư viện được phát hành công khai: không để lộ đường dẫn của máy build
export RUSTFLAGS="--remap-path-prefix=$HOME=/home --remap-path-prefix=$ROOT=/vipi"
for t in "${TARGETS[@]}"; do
  cargo build --release --features uniffi --target "$t"
done
# uniffi đọc mô tả giao diện từ thư viện chưa strip của máy build
cargo build --features uniffi
LIB=target/debug/libvipi_core.dylib
GEN=$(mktemp -d)
trap 'rm -rf "$GEN"' EXIT
cargo run -q --features bindgen --bin uniffi-bindgen -- generate --library "$LIB" --language swift --out-dir "$GEN"

mkdir -p "$GEN/headers" "$OUT"
cp "$GEN/ViPiCoreFFIFFI.h" "$GEN/headers/"
cp "$GEN/ViPiCoreFFIFFI.modulemap" "$GEN/headers/module.modulemap"
rm -rf "$OUT/ViPiCore.xcframework"
xcodebuild -create-xcframework \
  -library target/aarch64-apple-ios/release/libvipi_core.a -headers "$GEN/headers" \
  -library target/aarch64-apple-ios-sim/release/libvipi_core.a -headers "$GEN/headers" \
  -output "$OUT/ViPiCore.xcframework" >/dev/null
cp "$GEN/ViPiCoreFFI.swift" "$OUT/"
echo "ios/Core: ViPiCore.xcframework, ViPiCoreFFI.swift"
