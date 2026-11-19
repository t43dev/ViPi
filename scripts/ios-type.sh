#!/bin/bash
# Gõ thử bàn phím ViPi trên simulator (chạy trên Mac, sau scripts/ios-build.sh). Phím ViPi vẽ bằng Core Graphics
# nên test chạm theo toạ độ màn hình (point), xem ios/ViPiUITests/TypingTests.swift.
#   scripts/ios-type.sh "<x,y x,y w ...>" [simulator] [tên-ảnh]
# In ra TEXT: <chữ trong ô thử> và chụp màn hình vào ios/build/shots/<tên-ảnh>.png.
# Lần đầu với mỗi simulator: bật ViPi trong Settings. iPad lần đầu còn hiện màn "Quickly Change Keyboards":
# truyền toạ độ nút Continue trong danh sách chạm của lần chạy đó.
# Biến tuỳ chọn: SYSTEM=1 giữ bàn phím của Apple (không bật ViPi); SET="<nhãn>=0|1" đặt một công tắc trong app trước khi gõ; LAND=1 xoay ngang; GLOBE="x,y" quả địa cầu (iPhone); PICK="x,y" mục ViPi khi giữ quả địa cầu (iPad); INTRO=1 qua màn "Quickly Change Keyboards"; FIELD=search ô thử một dòng có nút Search;
# FIELD=number|decimal|asciiNumber|phone|namePhone|numbersPunct ô thử có bàn phím số; SECOND=1 thêm ô chữ thứ hai (chạm bằng "f:trial2", in TEXT2).
set -uo pipefail
cd "$(dirname "$0")/../ios"
export PATH="/opt/homebrew/bin:$PATH"
TAPS=${1:-}
SIM=${2:-iPhone 18 Pro}
NAME=${3:-shot}
UDID=$(xcrun simctl list devices available | grep -F "    $SIM (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$UDID" ] || { echo "no simulator named $SIM"; exit 1; }
mkdir -p build/shots
xcrun simctl boot "$UDID" 2>/dev/null; xcrun simctl bootstatus "$UDID" -b >/dev/null
../scripts/ios-suggest-models.sh
xcodegen generate --quiet
LOG=build/test.log
ARGS=(-project ViPi.xcodeproj -scheme ViPi -destination "id=$UDID" -derivedDataPath build/dd CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual)
xcodebuild build-for-testing "${ARGS[@]}" >$LOG 2>&1 || { grep -E "error" $LOG | sort -u | head -30; exit 1; }
xcrun simctl install "$UDID" build/dd/Build/Products/Debug-iphonesimulator/ViPi.app
if [ -z "${SYSTEM:-}" ] && [ ! -f "build/.enabled-$UDID" ]; then
  xcodebuild test-without-building "${ARGS[@]}" -only-testing:ViPiUITests/TypingTests/testEnableKeyboard >>$LOG 2>&1 \
    && touch "build/.enabled-$UDID" && echo "ViPi enabled in Settings" \
    || { grep -E "error|failed" $LOG | tail -20; exit 1; }
fi
env ${LAND:+TEST_RUNNER_VIPI_LANDSCAPE=1} ${SYSTEM:+TEST_RUNNER_VIPI_SYSTEM=1} ${GLOBE:+TEST_RUNNER_VIPI_GLOBE=$GLOBE} ${PICK:+TEST_RUNNER_VIPI_PICK=$PICK} ${INTRO:+TEST_RUNNER_VIPI_INTRO=1} ${SET:+"TEST_RUNNER_VIPI_SET=$SET"} ${FIELD:+TEST_RUNNER_VIPI_FIELD=$FIELD} ${SECOND:+TEST_RUNNER_VIPI_SECOND=1} \
    TEST_RUNNER_VIPI_TAPS="$TAPS" TEST_RUNNER_VIPI_HOLD=6 \
    xcodebuild test-without-building "${ARGS[@]}" -only-testing:ViPiUITests/TypingTests/testType 2>&1 | tee -a $LOG |
  while IFS= read -r line; do
    case "$line" in
      *VIPI_TEXT=*) echo "TEXT: ${line#*VIPI_TEXT=}"; sleep 1
        xcrun simctl io "$UDID" screenshot "build/shots/$NAME.png" >/dev/null 2>&1 && echo "screenshot ios/build/shots/$NAME.png";;
      *VIPI_TEXT2=*) echo "TEXT2: ${line#*VIPI_TEXT2=}";;
      *VIPI_SET=*|*VIPI_APPLEKB=*|*"error:"*|*"** TEST"*) echo "$line";;
    esac
  done
