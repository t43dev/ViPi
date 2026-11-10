#!/usr/bin/env python3
"""App Store Connect API: asc.py METHOD PATH [JSON]. In ra mã HTTP ở dòng đầu, rồi JSON trả về.
Khoá đọc từ biến môi trường ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_FILE (file apple.env, không nằm trong repo)."""
import base64, json, os, sys, time, urllib.error, urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils


def b64(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def token():
    key = serialization.load_pem_private_key(open(os.environ["ASC_KEY_FILE"], "rb").read(), None)
    h = b64(json.dumps({"alg": "ES256", "kid": os.environ["ASC_KEY_ID"], "typ": "JWT"}).encode())
    now = int(time.time())
    p = b64(json.dumps({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}).encode())
    r, s = utils.decode_dss_signature(key.sign(f"{h}.{p}".encode(), ec.ECDSA(hashes.SHA256())))
    return f"{h}.{p}.{b64(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))}"


def call(method, path, body=None):
    url = path if path.startswith("http") else "https://api.appstoreconnect.apple.com" + path
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
                return r.status, json.loads(data) if data else None
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read() or b"null")
        except (urllib.error.URLError, ConnectionError, TimeoutError):
            if attempt == 3:
                raise
            time.sleep(2 ** attempt)


if __name__ == "__main__":
    status, data = call(sys.argv[1], sys.argv[2], json.loads(sys.argv[3]) if len(sys.argv) > 3 else None)
    print(status)
    print(json.dumps(data, ensure_ascii=False, indent=1))
