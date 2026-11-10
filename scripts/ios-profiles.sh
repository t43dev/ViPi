#!/bin/bash
# (Tạo lại) 2 profile App Store cho ViPi iOS bằng App Store Connect API, ký bằng chứng chỉ Apple Distribution chung của team.
# Chạy lại mỗi khi đổi capability / App Group trên App ID (profile cũ mất hiệu lực).
# Cần trong .env: APPLE_ENV = file apple.env (ASC_KEY_*, DIST_CERT_P12, DIST_CERT_P12_PASSWORD). Profile ghi vào thư mục profiles/ cạnh file đó.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; . "${APPLE_ENV:?APPLE_ENV missing in .env}"; set +a
ASC="python3 scripts/asc.py"
json() { sed 1d | python3 -c "import sys,json; d=json.load(sys.stdin); $1"; }

# chứng chỉ trên ASC khớp với file p12 (theo số serial); p12 của Apple mã hoá kiểu cũ nên cần -legacy
SERIAL=$(openssl pkcs12 -legacy -in "$DIST_CERT_P12" -nokeys -passin env:DIST_CERT_P12_PASSWORD 2>/dev/null \
  | openssl x509 -noout -serial | cut -d= -f2)
CERT=$($ASC GET "/v1/certificates?filter[serialNumber]=$SERIAL" | json "print(d['data'][0]['id'])")
OUT=$(dirname "$APPLE_ENV")/profiles; mkdir -p "$OUT"

for p in "dev.t43.vipi:ViPi AppStore" "dev.t43.vipi.keyboard:ViPi Keyboard AppStore"; do
  id=${p%%:*}; name=${p#*:}
  bid=$($ASC GET "/v1/bundleIds?filter[identifier]=$id" | json "print([b['id'] for b in d['data'] if b['attributes']['identifier']=='$id'][0])")
  for old in $($ASC GET "/v1/profiles?filter[name]=${name// /%20}" | json "print(' '.join(p['id'] for p in d['data']))"); do
    $ASC DELETE "/v1/profiles/$old" | head -1 >/dev/null
  done
  $ASC POST /v1/profiles "{\"data\":{\"type\":\"profiles\",\"attributes\":{\"name\":\"$name\",\"profileType\":\"IOS_APP_STORE\"},\"relationships\":{\"bundleId\":{\"data\":{\"type\":\"bundleIds\",\"id\":\"$bid\"}},\"certificates\":{\"data\":[{\"type\":\"certificates\",\"id\":\"$CERT\"}]}}}}" \
    | json "import base64; a=d['data']['attributes']; open('$OUT/${name// /_}.mobileprovision','wb').write(base64.b64decode(a['profileContent'])); print('$name', a['profileState'])"
  # App Group phải có trong profile, không thì bàn phím không đọc được cài đặt của app
  security_groups=$(python3 - "$OUT/${name// /_}.mobileprovision" <<'PY'
import plistlib, re, sys
raw = open(sys.argv[1], 'rb').read()
plist = raw[raw.index(b'<?xml'):raw.index(b'</plist>') + 8]
print(' '.join(plistlib.loads(plist)['Entitlements'].get('com.apple.security.application-groups', [])))
PY
)
  [[ " $security_groups " == *" group.dev.t43.vipi "* ]] || { echo "  $id: App Group group.dev.t43.vipi is not on this App ID yet (developer.apple.com → Identifiers)" >&2; exit 1; }
done
