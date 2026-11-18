#!/bin/bash
# Mô hình gợi ý từ (đếm từ và mạng dự đoán từ tiếp theo, tiếng Anh và tiếng Việt), lấy từ Vikey
# (github.com/tonyminibot/Vikey, GPL-3.0) ở đúng một commit, kiểm tra SHA-256. 65 MB nên không lưu trong git.
#   scripts/suggest-models.sh [thư mục]    mặc định build/suggest (lõi Rust: VIPI_SUGGEST_MODELS, cargo test)
# scripts/ios-suggest-models.sh gọi script này với ios/Suggest cho bản iOS.
set -euo pipefail
cd "$(dirname "$0")/.."
DIR=${1:-build/suggest}
COMMIT=5f2bfb0257146eb86301f1b86e5c2fb313b1dcd8
mkdir -p "$DIR"
sum() { { shasum -a 256 "$1" 2>/dev/null || sha256sum "$1" 2>/dev/null; } | cut -d' ' -f1; }
while read -r name want; do
  [ "$(sum "$DIR/$name")" = "$want" ] && continue
  echo "fetching $name"
  curl -fsSL --retry 3 -o "$DIR/$name.part" "https://raw.githubusercontent.com/tonyminibot/Vikey/$COMMIT/iOS/Keyboard/$name"
  [ "$(sum "$DIR/$name.part")" = "$want" ] || { echo "checksum mismatch: $name" >&2; rm -f "$DIR/$name.part"; exit 1; }
  mv "$DIR/$name.part" "$DIR/$name"
done <<'LIST'
SuggestEN.bin 32cc83db7d31d10d6e8e2c4e55996dac8a9de34b9a68680be3d705e3ebedac46
SuggestNN.bin 9f1c7f4b77ccd19d8081397feafdd43c8736eaf625da1bf45bb90453fad6f3a7
SuggestVI.bin 22aeb68ff008d308972add598c5682aeca46289e550eb5f88f8f1b01db665126
SuggestVINN.bin d43b10d9e56bfa8b9c8bf86774062e32568a377f5b9802a5fc65513400e00549
LIST
