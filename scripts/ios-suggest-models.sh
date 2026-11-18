#!/bin/bash
# Mô hình gợi ý từ của bàn phím iOS: như scripts/suggest-models.sh, vào ios/Suggest/ (gitignore).
# scripts/ios-build.sh, ios-type.sh và ios-testflight.sh gọi script này trước khi build.
#   scripts/ios-suggest-models.sh
set -euo pipefail
exec "$(dirname "$0")/suggest-models.sh" ios/Suggest
