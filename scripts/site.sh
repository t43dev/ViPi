#!/usr/bin/env bash
# Build the vipi.t43.app website into build/site, optionally deploy it to Cloudflare Pages.
#   scripts/site.sh          build only
#   scripts/site.sh deploy   build, then upload (needs CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID in .env)
set -euo pipefail
cd "$(dirname "$0")/.."
out=build/site
rm -rf "$out"
mkdir -p "$out/img" "$out/data"
cp -R site/. "$out/"
cp assets/logo.svg assets/logo-256.png "$out/img/"
cp assets/readme/cand-light.png assets/readme/cand-dark.png "$out/img/"
cp assets/readme/settings-*-en-*.png "$out/img/"
cp assets/readme/hero-light.png "$out/img/og.png"
cp Resources/vietnamese-syllables.txt "$out/data/syllables.txt"
python3 scripts/site-pinyin.py "$out/data/pinyin.tsv"
echo "built $out ($(du -sh "$out" | cut -f1))"

if [[ "${1:-}" == deploy ]]; then
  set -a; . ./.env; set +a
  npx --yes wrangler@4 pages deploy "$out" --project-name vipi --branch main --commit-dirty=true
fi
