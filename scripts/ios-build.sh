#!/bin/bash
# Build ViPi iOS trên Mac (Xcode, XcodeGen): lõi Rust nếu chưa có hoặc core/ mới hơn, tạo dự án, build cho simulator.
#   scripts/ios-build.sh            build simulator (ký ad-hoc để có App Group)
#   scripts/ios-build.sh --core     build lại lõi trước
# Từ máy dev dùng scripts/ios-dev.sh để chép mã sang Mac rồi chạy script này.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"
command -v xcodegen >/dev/null || brew install xcodegen >/dev/null

stamp=ios/Core/ViPiCoreFFI.swift
if [ "${1:-}" = "--core" ] || [ ! -f "$stamp" ] || [ -n "$(find core/src core/Cargo.toml -type f -newer "$stamp" -print -quit)" ]; then
  scripts/ios-core.sh
fi

cd ios
xcodegen generate --quiet
LOG=build/xcodebuild.log
mkdir -p build
if xcodebuild -project ViPi.xcodeproj -target ViPi -configuration Debug -sdk iphonesimulator -arch arm64 \
    SYMROOT="$PWD/build/products" OBJROOT="$PWD/build/obj" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build >"$LOG" 2>&1; then
  grep -E "warning: " "$LOG" | grep -v -e "^ld: warning" -e appintents | sort -u | head -40 || true
  echo "BUILD OK: $(ls -d build/products/Debug-iphonesimulator/ViPi.app)"
else
  grep -E "error|BUILD FAILED" "$LOG" | sort -u | head -60
  exit 1
fi
