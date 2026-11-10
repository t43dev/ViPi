#!/bin/bash
# Từ máy dev: chép mã hiện tại (kể cả thay đổi chưa commit, trừ file bị gitignore) sang Mac rồi build iOS ở đó.
#   scripts/ios-dev.sh [--core]
# Cấu hình trong .env: MAC=user@host, SSH_KEY. Thư mục trên Mac: ~/vipi-ios (giữ lại ios/Core và core/target giữa các lần).
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
: "${MAC:?MAC=user@host missing in .env}" "${SSH_KEY:?SSH_KEY missing in .env}"
SSH="ssh -i $SSH_KEY -o BatchMode=yes $MAC"
git ls-files -co --exclude-standard -z | grep -zv '^android/\|^harmony/\|^site/\|^assets/' \
  | tar --null -T - -czf - | $SSH 'mkdir -p ~/vipi-ios && tar -xzf - -C ~/vipi-ios'
$SSH "cd ~/vipi-ios && scripts/ios-build.sh ${1:-}"
