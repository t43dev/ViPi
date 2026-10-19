#!/bin/bash
# Ảnh hero cho README (sáng + tối) từ hero.html, chạy trên máy Mac có Google Chrome:
#   cd assets/readme && ./render.sh
# cand-*.png là khung chọn chữ Hán thật, lấy từ: ViPi --snapshot-settings <prefix> -appearance light|dark
cd "$(dirname "$0")"
C="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for t in light dark; do
  "$C" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 --window-size=1280,520 \
    --default-background-color=00000000 --screenshot="$PWD/hero-$t.png" "file://$PWD/hero.html#$t" >/dev/null 2>&1
done
