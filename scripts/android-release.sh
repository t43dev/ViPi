#!/usr/bin/env bash
# Phát hành bàn phím Android: build APK bản release ký bằng khoá trong .env (ANDROID_KEYSTORE…), kiểm chữ ký,
# rồi đưa lên GitHub release android-v<version> dạng pre-release (bản Mac vẫn là "Latest", trình cập nhật Mac
# chỉ nhận release có DMG nên không bị ảnh hưởng).
# Dùng: scripts/android-release.sh 0.1.1      (versionName trong android/app/build.gradle.kts phải khớp,
#        tag android-v0.1.1 phải trỏ đúng commit HEAD)
set -euo pipefail
VERSION=${1:?usage: scripts/android-release.sh <version>}
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
: "${ANDROID_KEYSTORE:?missing in .env}" "${ANDROID_KEYSTORE_PASSWORD:?missing in .env}"
TAG=android-v$VERSION
[ "$(git rev-parse "$TAG^{commit}")" = "$(git rev-parse HEAD)" ] || { echo "tag $TAG must point at HEAD"; exit 1; }

# -DsocksProxy…: bỏ qua proxy SOCKS nếu gradle.properties của máy có đặt mà tunnel không mở
(cd android && ./gradlew -q -DsocksProxyHost= -DsocksProxyPort= clean assembleRelease)
APK=android/app/build/outputs/apk/release/app-release.apk
SDK=$(sed -n 's/^sdk.dir=//p' android/local.properties)
BT=$(ls -d "$SDK"/build-tools/* | sort -V | tail -1)
"$BT/aapt2" dump badging "$APK" | grep -q "versionName='$VERSION'" || { echo "versionName is not $VERSION"; exit 1; }
"$BT/apksigner" verify --print-certs "$APK" | grep -E "Signer #1 certificate (DN|SHA-256)"
mkdir -p build
cp "$APK" "build/ViPi-android-$VERSION.apk"
ls -la "build/ViPi-android-$VERSION.apk"

gh release view "$TAG" -R t43dev/ViPi >/dev/null 2>&1 || gh release create "$TAG" -R t43dev/ViPi --verify-tag --prerelease \
  --title "ViPi for Android $VERSION (beta)" --notes-file "${NOTES:-/dev/null}"
gh release upload "$TAG" "build/ViPi-android-$VERSION.apk" -R t43dev/ViPi --clobber
echo "uploaded to release $TAG"
