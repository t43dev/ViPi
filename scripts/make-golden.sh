#!/usr/bin/env bash
# Xuất đáp án mẫu từ bộ gõ Swift (Tests/ViPiCoreTests/GoldenTests.swift) cho lõi Rust so khớp (core/tests/golden.rs).
# Chạy lại khi sửa hành vi bộ gõ, ở cả hai bản: scripts/make-golden.sh && (cd core && cargo test)
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
VIPI_GOLDEN="$tmp" swift test --filter GoldenTests 2>&1 | grep -E "^golden |error|failed" || true
mkdir -p core/tests/golden
for f in "$tmp"/*.txt; do gzip -9 -n -c "$f" > "core/tests/golden/$(basename "$f").gz"; done
ls -la core/tests/golden
