#!/bin/bash
# =============================================================================
# 05-media/media-test.sh
# HTTP checks against media-service through Traefik on every node. Never calls
# DELETE /api/media (it deletes every record): the test record is removed
# directly in MongoDB afterwards.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh

fail=0
ok()  { echo "  PASS  $*"; }
bad() { echo "  FAIL  $*"; fail=1; }

token="borg-media-test-$(date +%s)-$RANDOM"
body=$(mktemp)
cleanup() {
    local p
    rm -f "$body"
    p=$(mongo_primary 2>/dev/null) || return 0
    mongo_eval "$p" "$(mongo_app_uri)" "db.media.deleteMany({title: '$token'})" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for ip in $ALL_IPS; do
    code=$(curl -s -m 10 -o "$body" -w '%{http_code}' "http://$ip/api/media" || true)
    if [ "$code" = 200 ] && head -c1 "$body" | grep -q '\['; then
        ok "GET http://$ip/api/media -> 200 (JSON array)"
    else
        bad "GET http://$ip/api/media -> $code"
    fi
done

code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
    -d "{\"title\":\"$token\",\"artist\":\"borg-media-test\"}" "http://$NODE1_IP/api/media" || true)
if [ "$code" = 201 ]; then ok "POST via $NODE1_IP -> 201"; else bad "POST via $NODE1_IP -> $code"; fi

if curl -s -m 10 "http://$NODE2_IP/api/media/$token" | grep -q "\"title\":\"$token\""; then
    ok "GET via $NODE2_IP returns the record (stored in MongoDB)"
else
    bad "GET via $NODE2_IP did not return the record"
fi

if [ "$fail" -eq 0 ]; then
    echo ">>> media-test: all checks passed"
else
    echo ">>> media-test: FAILED" >&2
    exit 1
fi
