#!/usr/bin/env bash
# Build gói AAB để đưa lên Google Play, ký bằng khoá trong .env (ANDROID_KEYSTORE…). Không upload gì.
# Dùng: scripts/android-play.sh     → build/ViPi-android-<version>.aab
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
: "${ANDROID_KEYSTORE:?missing in .env}" "${ANDROID_KEYSTORE_PASSWORD:?missing in .env}"
VERSION=$(sed -n 's/^ *versionName = "\(.*\)"/\1/p' android/app/build.gradle.kts)

# -DsocksProxy…: bỏ qua proxy SOCKS nếu gradle.properties của máy có đặt mà tunnel không mở
(cd android && ./gradlew -q -DsocksProxyHost= -DsocksProxyPort= clean bundleRelease)
AAB=android/app/build/outputs/bundle/release/app-release.aab
jarsigner -verify -certs "$AAB" | grep -E "^jar verified|CN=" | sort -u
mkdir -p build
cp "$AAB" "build/ViPi-android-$VERSION.aab"
ls -la "build/ViPi-android-$VERSION.aab"
