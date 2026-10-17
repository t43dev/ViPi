#!/bin/bash
# Build ViPi trên Mac Studio, ký bằng chứng chỉ dev tự tạo (chữ ký ổn định → quyền Accessibility
# không mất khi build lại), cài vào /Applications và khởi động lại. Chạy từ máy dev.
# Dùng: scripts/mac-dev.sh [selftest-args...]
set -euo pipefail
MAC=user@mac-host
SSH="ssh -i $SSH_KEY -o BatchMode=yes $MAC"
cd "$(dirname "$0")/.."

git archive --format=tar HEAD | $SSH 'rm -rf ~/vipi-dev && mkdir -p ~/vipi-dev && tar -x -C ~/vipi-dev'
# bản đang sửa dở (chưa commit) cũng được đẩy lên
git diff HEAD --binary | $SSH 'cd ~/vipi-dev && git apply --allow-empty 2>/dev/null || patch -p1 >/dev/null' || true
git ls-files --others --exclude-standard -z | xargs -0r tar -c | $SSH 'tar -x -C ~/vipi-dev'
# bản dev mang số phiên bản của tag gần nhất + "-dev", build = commit (có "+" nếu còn sửa dở)
VER="$(git describe --tags --abbrev=0 | sed 's/^v//')-dev"
REV="$(git rev-parse --short HEAD)$(git diff --quiet HEAD || echo +)"
$SSH "VER=$VER REV=$REV bash -s" <<'REMOTE'
set -euo pipefail
cd ~/vipi-dev
swift build -c release 2>&1 | grep -E "error|warning: |Compiling|Build complete" | grep -v "^\[" | tail -20
BIN=$(swift build -c release --show-bin-path)
APP=build/ViPi.app
rm -rf build && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp $BIN/ViPi $APP/Contents/MacOS/
sed -e "s/__VERSION__/$VER/" -e "s/__BUILD__/$REV/" Resources/Info.plist > $APP/Contents/Info.plist
cp Resources/pinyin.tsv Resources/vietnamese-syllables.txt $APP/Contents/Resources/
iconutil -c icns Resources/AppIcon.iconset -o $APP/Contents/Resources/AppIcon.icns
KC=$HOME/Library/Keychains/vipi-dev.keychain-db
security unlock-keychain -p "$KC_PW" $KC
codesign --force --options runtime --keychain $KC --sign "ViPi Dev Signing" $APP
codesign -dr - $APP 2>&1 | tail -1
pkill -x ViPi || true
sleep 0.5
rm -rf /Applications/ViPi.app && cp -R $APP /Applications/ViPi.app
open /Applications/ViPi.app
sleep 2
pgrep -x ViPi >/dev/null && echo "ViPi running (pid $(pgrep -x ViPi))"
REMOTE
