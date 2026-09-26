#!/bin/bash
# =============================================================================
# test/run-tests.sh: signed_urls.lua in the server's httpd build (CentOS 7,
# httpd-2.4.6-97.el7, prefork, mod_lua, Lua 5.1), end to end over HTTP.
#   - Lua known-answer self-test
#   - log-only mode: invalid URLs served, "would deny" logged
#   - enforce mode: valid/range 200/206; unsigned, tampered, expired, flag
#     added/removed, unknown key 403; other paths unaffected; no listing
#   - key rotation (two keys, then one)
#   - a URL signed by the live media-service (Java GcsSignUrl) is accepted
#   - latency with the hook, cached and uncached, against a path without it
# Usage: test/run-tests.sh   (needs docker, python3, curl; MEDIA_API optional)
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."
IMAGE=signed-urls-lua-test
NAME=signed-urls-lua-test
PORT=${PORT:-18080}
MEDIA_API=${MEDIA_API:-http://192.168.56.120/api/media}
KEY_B64=$(head -c 16 /dev/urandom | base64 | tr '+/' '-_')
KEY2_B64=$(head -c 16 /dev/urandom | base64 | tr '+/' '-_')
# The key media-service signs with, from its Secret (never printed); empty if the cluster isn't reachable
PROD_KEY_NAME=$(kubectl --kubeconfig "${KUBECONFIG:-$HOME/.kube/config-borg}" -n media get secret media-service-signing -o jsonpath='{.data.SIGNING_KEY_NAME}' 2>/dev/null | base64 -d)
PROD_KEY_B64=$(kubectl --kubeconfig "${KUBECONFIG:-$HOME/.kube/config-borg}" -n media get secret media-service-signing -o jsonpath='{.data.SIGNING_KEY}' 2>/dev/null | base64 -d)
PROD_KEY_NAME=${PROD_KEY_NAME:-none}; PROD_KEY_B64=${PROD_KEY_B64:-AAAA}
FILE=/prev/gen3/402391.mp4

fail=0
ok()  { echo "  PASS  $*"; }
bad() { echo "  FAIL  $*"; fail=1; }
dx()  { docker exec "$NAME" "$@"; }

# sign <path> <key_b64> <key_name> <expires> [prefix]: query string signed like GcsSignUrl.signUrl
sign() {
    python3 - "$@" <<'EOF'
import base64, hashlib, hmac, sys
path, key_b64, key_name, expires = sys.argv[1:5]
prefix = sys.argv[5] if len(sys.argv) > 5 else ""
q = (prefix + "&" if prefix else "") + f"Expires={expires}&KeyName={key_name}"
key = base64.urlsafe_b64decode(key_b64)
sig = base64.urlsafe_b64encode(hmac.new(key, f"https://www.my12inch.com{path}?{q}".encode(), hashlib.sha1).digest()).decode()
print(f"{q}&Signature={sig}")
EOF
}
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
expect() {   # expect <want> <name> <curl args...>
    local want=$1 name=$2; shift 2
    local got; got=$(code "$@")
    if [ "$got" = "$want" ]; then ok "$name -> $got"; else bad "$name -> $got (want $want)"; fi
}
set_keys()  { dx sh -c "printf '%s\n' $* > /etc/httpd/signed-urls/keys && chown root:apache /etc/httpd/signed-urls/keys && chmod 0640 /etc/httpd/signed-urls/keys"; }
set_mode()  {   # log | enforce
    if [ "$1" = enforce ]; then
        dx sed -i -e 's|^    LuaHookAccessChecker \(.*\) check_signed_url_log$|    #LuaHookAccessChecker \1 check_signed_url_log|' \
                  -e 's|^    #LuaHookAccessChecker \(.*\) check_signed_url$|    LuaHookAccessChecker \1 check_signed_url|' /etc/httpd/conf.d/signed-urls.conf
    fi
    dx httpd -t >/dev/null 2>&1 || { bad "httpd -t after switching to $1"; dx httpd -t; }
    dx httpd -k graceful; sleep 2
}

echo ">>> build and start ($IMAGE)"
docker build -q -t "$IMAGE" -f test/Dockerfile . >/dev/null || { echo "docker build failed"; exit 1; }
docker rm -f "$NAME" >/dev/null 2>&1
docker run -d --name "$NAME" -p "127.0.0.1:$PORT:8080" "$IMAGE" >/dev/null
trap 'docker rm -f "$NAME" >/dev/null 2>&1' EXIT
set_keys "'k1 $KEY_B64'" "'$PROD_KEY_NAME $PROD_KEY_B64'"
sleep 2
echo "  INFO  $(dx rpm -q httpd) / $(dx lua -v 2>&1) / MPM $(dx httpd -V 2>/dev/null | awk '/MPM:/ {print $3}')"
base="http://127.0.0.1:$PORT"
now=$(date +%s)

echo ">>> Lua self-test"
docker exec -i "$NAME" lua /dev/stdin /etc/httpd/signed-urls/signed_urls.lua < selftest.lua > /tmp/signed-urls-selftest.$$ 2>&1
if tail -1 /tmp/signed-urls-selftest.$$ | grep -q "all passed"; then ok "Lua self-test ($(grep -c PASS /tmp/signed-urls-selftest.$$) checks; $(grep -o '[0-9.]* ms per sign+verify pair' /tmp/signed-urls-selftest.$$))"; else bad "Lua self-test"; cat /tmp/signed-urls-selftest.$$; fi
rm -f /tmp/signed-urls-selftest.$$

echo ">>> log-only mode (as shipped)"
expect 200 "unsigned request is served" "$base$FILE"
sleep 1
if dx grep -q "signed_urls: would deny $FILE: unsigned" /var/log/httpd/error_log; then ok "error_log: would deny ... unsigned"; else bad "no 'would deny' line in error_log"; fi

echo ">>> enforce mode"
set_mode enforce
valid=$(sign $FILE "$KEY_B64" k1 $((now + 300)))
dl=$(sign $FILE "$KEY_B64" k1 $((now + 300)) download=1)
expect 200 "valid stream URL" "$base$FILE?$valid"
expect 206 "valid stream URL, Range 0-99" -H 'Range: bytes=0-99' "$base$FILE?$valid"
expect 206 "valid stream URL, Range at 4 MB" -H 'Range: bytes=4000000-4000099' "$base$FILE?$valid"
expect 200 "valid download URL" "$base$FILE?$dl"
cd_hdr=$(curl -s -o /dev/null -D - "$base$FILE?$dl" | tr -d '\r' | awk -F': ' 'tolower($1)=="content-disposition" {print $2}')
if [ "$cd_hdr" = attachment ]; then ok "download URL has Content-Disposition: attachment"; else bad "download URL Content-Disposition '$cd_hdr'"; fi
expect 403 "unsigned" "$base$FILE"
expect 403 "wrong signature" "$base$FILE?${valid%Signature=*}Signature=AAAAAAAAAAAAAAAAAAAAAAAAAAA="
expect 403 "expired" "$base$FILE?$(sign $FILE "$KEY_B64" k1 $((now - 1)))"
expect 403 "Expires changed" "$base$FILE?${valid/Expires=/Expires=9}"
expect 403 "download=1 removed" "$base$FILE?${dl#download=1&}"
expect 403 "download=1 added" "$base$FILE?download=1&$valid"
expect 403 "parameter after Signature" "$base$FILE?$valid&x=1"
expect 403 "unknown KeyName" "$base$FILE?$(sign $FILE "$KEY_B64" nokey $((now + 300)))"
expect 403 "valid query on another file (cache must not match)" "$base/prev/gen3/402392.mp4?$valid"
expect 403 "no directory listing of /prev/gen3/" "$base/prev/gen3/"
expect 200 "paths outside /prev/gen3/ unaffected" "$base/plain/402391.mp4"
expect 200 "/index.html unaffected" "$base/index.html"

echo ">>> key rotation"
set_keys "'k1 $KEY_B64'" "'k2 $KEY2_B64'" "'$PROD_KEY_NAME $PROD_KEY_B64'"
dx httpd -k graceful; sleep 2
expect 200 "old key k1 still valid" "$base$FILE?$(sign $FILE "$KEY_B64" k1 $((now + 301)))"
expect 200 "new key k2 valid" "$base$FILE?$(sign $FILE "$KEY2_B64" k2 $((now + 301)))"
set_keys "'k2 $KEY2_B64'" "'$PROD_KEY_NAME $PROD_KEY_B64'"
dx httpd -k graceful; sleep 2
expect 403 "k1 removed: rejected" "$base$FILE?$(sign $FILE "$KEY_B64" k1 $((now + 302)))"
expect 200 "k2 still valid" "$base$FILE?$(sign $FILE "$KEY2_B64" k2 $((now + 302)))"

echo ">>> signed by the live media-service (Java CdnSigner, key $PROD_KEY_NAME from Secret media-service-signing)"
id=$(curl -s -m 30 "$MEDIA_API/search?q=HIGHLIFE&size=50" 2>/dev/null | python3 -c 'import json,sys; print(next(m["id"] for m in json.load(sys.stdin)["items"] if m.get("song_id")==402391))' 2>/dev/null)
java_url=$( [ -n "$id" ] && curl -s -m 10 "$MEDIA_API/$id/stream" )
if [[ "$java_url" == https://www.my12inch.com/prev/gen3/402391.mp4\?* ]]; then
    expect 206 "media-service /stream URL (Java-signed), Range 0-99" -H 'Range: bytes=0-99' "$base${java_url#https://www.my12inch.com}"
    java_dl=$(curl -s -m 10 -X POST "$MEDIA_API/$id/download" | python3 -c 'import json,sys; print(json.load(sys.stdin)["url"])' 2>/dev/null)
    expect 200 "media-service /download URL (Java-signed)" "$base${java_dl#https://www.my12inch.com}"
else
    echo "  SKIP  media-service not reachable at $MEDIA_API ($java_url)"
fi

echo ">>> latency (ab, 2000 requests, concurrency 8, Range 0-0)"
cached=$(sign $FILE "$KEY2_B64" k2 $((now + 600)))
for t in "no hook|$base/plain/402391.mp4" "hook, cached URL|$base$FILE?$cached"; do
    name=${t%%|*}; url=${t#*|}
    ms=$(dx ab -q -n 2000 -c 8 -H 'Range: bytes=0-0' "http://127.0.0.1:8080${url#$base}" 2>/dev/null | awk '/Time per request.*\(mean\)$/ {print $4}')
    echo "  INFO  $name: $ms ms mean per request"
done
# Uncached: every request a different URL (distinct Expires)
urls=$(for i in $(seq 1 300); do echo "http://127.0.0.1:8080$FILE?$(sign $FILE "$KEY2_B64" k2 $((now + 1000 + i)))"; done)
start=$(date +%s%N)
docker exec -i "$NAME" sh -c "xargs -P 8 -n 1 curl -s -o /dev/null -r 0-0" <<<"$urls"
elapsed=$(( ($(date +%s%N) - start) / 1000000 ))
echo "  INFO  hook, 300 distinct URLs (uncached), concurrency 8: $elapsed ms total, $((elapsed * 8 / 300)) ms per request"
denied=$(dx grep -c "signed_urls: denied" /var/log/httpd/error_log)
echo "  INFO  error_log has $denied 'signed_urls: denied' lines (from the 403 cases above)"

if [ "$fail" -eq 0 ]; then echo ">>> signed-urls-lua: all checks passed"; else echo ">>> signed-urls-lua: FAILED" >&2; exit 1; fi
