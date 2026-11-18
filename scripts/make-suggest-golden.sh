#!/usr/bin/env bash
# Xuất đáp án mẫu của bộ gợi ý từ Swift (ios/ViPiKeyboard/Suggest/, qua ios/Tools/suggest-golden/main.swift) cho lõi
# Rust so khớp (core/tests/suggest.rs). Chạy trên Mac, khi sửa SuggestLM/SuggestNN/TapModel/Suggester/KeepWords:
#   scripts/make-suggest-golden.sh && (cd core && cargo test --release --test suggest)
# Mô hình lấy ở VIPI_SUGGEST_MODELS, mặc định ios/Suggest (scripts/ios-suggest-models.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
models=${VIPI_SUGGEST_MODELS:-ios/Suggest}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
src=ios/ViPiKeyboard/Suggest
cp "$src/SuggestLM.swift" "$src/SuggestNN.swift" "$src/KeyRect.swift" "$src/KeepWords.swift" ios/Tools/suggest-golden/main.swift "$tmp/"
# TapModel và Suggester chỉ cần CGPoint/CGRect của UIKit: dịch cho macOS với Foundation
for f in TapModel Suggester; do sed 's/^import UIKit$/import Foundation/' "$src/$f.swift" > "$tmp/$f.swift"; done
for f in SuggestEN SuggestNN SuggestVI SuggestVINN; do cp "$models/$f.bin" "$tmp/"; done
cp Resources/keep-words.txt Resources/keep-words-chat.txt ios/Tools/suggest-eval/sentences.txt ios/Tools/suggest-eval/chat.txt "$tmp/"
(cd "$tmp" && swiftc -O main.swift SuggestLM.swift SuggestNN.swift KeyRect.swift KeepWords.swift TapModel.swift Suggester.swift \
  -o suggest-golden && ./suggest-golden . suggest.txt)
mkdir -p core/tests/golden
gzip -9 -n -c "$tmp/suggest.txt" > core/tests/golden/suggest.txt.gz
ls -la core/tests/golden/suggest.txt.gz
