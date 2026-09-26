#!/bin/bash
# =============================================================================
# 08-record-pool/record-pool-test.sh
# HTTP checks against the record-pool web app through HAProxy on the VIP, that
# /api/media still reaches media-service, that a track's signed stream and
# download URLs resolve on the CDN, unknown /api paths 404, and the chart's
# helm test.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh
source 07-edge/edge-lib.sh

fail=0
ok()   { echo "  PASS  $*"; }
bad()  { echo "  FAIL  $*"; fail=1; }
skip() { echo "  SKIP  $*"; }
warn() { echo "  WARN  $*"; }

body=$(mktemp)
trap 'rm -f "$body"' EXIT
base="http://$VIP_ADDRESS"

want=$(kubectl -n "$RECORD_POOL_NAMESPACE" get deployment "$RECORD_POOL_RELEASE" -o jsonpath='{.spec.replicas}' 2>/dev/null) ||
    die "deployment $RECORD_POOL_RELEASE not found in namespace $RECORD_POOL_NAMESPACE (run: make deploy-record-pool)"
have=$(kubectl -n "$RECORD_POOL_NAMESPACE" get deployment "$RECORD_POOL_RELEASE" -o jsonpath='{.status.readyReplicas}')
if [ "${have:-0}" = "$want" ]; then ok "$have/$want replicas Ready"; else bad "${have:-0}/$want replicas Ready"; fi
nodes=$(kubectl -n "$RECORD_POOL_NAMESPACE" get pods -l app.kubernetes.io/instance="$RECORD_POOL_RELEASE" \
    -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | wc -l)
echo "  INFO  pods spread over $nodes node(s)"

code=$(curl -s -m 10 -o "$body" -w '%{http_code}' "$base/" || true)
if [ "$code" = 200 ] && grep -q '<div id="root">' "$body"; then
    ok "GET $base/ -> 200 (app shell)"
else
    bad "GET $base/ -> $code"
fi

js=$(grep -o '/_expo/static/js/web/[^"]*\.js' "$body" | head -1 || true)
if [ -n "$js" ]; then
    cc=$(curl -s -m 10 -o /dev/null -D - "$base$js" | tr -d '\r' | awk -F': ' 'tolower($1) == "cache-control" {print $2}')
    if grep -q immutable <<<"$cc"; then ok "GET $js -> immutable ($cc)"; else bad "GET $js -> Cache-Control '$cc'"; fi
else
    bad "no /_expo/static/js bundle referenced by $base/"
fi

for route in /RecordPoolApp /explore /no/such/route; do
    code=$(curl -s -m 10 -o "$body" -w '%{http_code}' "$base$route" || true)
    if [ "$code" = 200 ] && grep -q '<div id="root">' "$body"; then
        ok "GET $base$route -> 200 (deep link)"
    else
        bad "GET $base$route -> $code"
    fi
done

if kubectl -n "$MEDIA_NAMESPACE" get deployment "$MEDIA_RELEASE" >/dev/null 2>&1; then
    code=$(curl -s -m 10 -o "$body" -w '%{http_code}' "$base/api/media" || true)
    if [ "$code" = 200 ] && head -c1 "$body" | grep -q '\['; then
        ok "GET $base/api/media -> 200 JSON array (still media-service)"
    else
        bad "GET $base/api/media -> $code (expected media-service's JSON array)"
    fi

    # Signed URLs of one published video track: /prev/gen3/<song_id>.mp4 on the CDN
    track=$(jq -r 'first(.[] | select(.song_id != null and .is_video == true)) | "\(.id) \(.song_id)"' "$body" 2>/dev/null || true)
    if [ -z "$track" ]; then
        skip "no published video track in the catalog; stream and download URLs not checked"
    else
        read -r id song_id <<<"$track"
        url=$(curl -s -m 10 "$base/api/media/$id/stream" || true)
        cdn=$(curl -s -m 15 -o /dev/null -w '%{http_code}' -I "$url" || true)
        if [[ "$url" == *"/$song_id.mp4?Expires="* ]] && [ "$cdn" = 200 ]; then
            ok "GET /api/media/$id/stream -> $song_id.mp4, CDN HEAD 200"
        else
            bad "GET /api/media/$id/stream -> '$url', CDN HEAD $cdn"
        fi

        code=$(curl -s -m 10 -o "$body" -w '%{http_code}' -X POST "$base/api/media/$id/download" || true)
        url=$(jq -r '.url // empty' "$body" 2>/dev/null || true)
        headers=$(curl -s -m 15 -o /dev/null -D - -I "$url" | tr -d '\r' || true)
        cdn=$(awk 'NR == 1 {print $2}' <<<"$headers")
        if [ "$code" = 200 ] && [[ "$url" == *"/$song_id.mp4?download=1&Expires="* ]] && [ "$cdn" = 200 ]; then
            ok "POST /api/media/$id/download -> signed $song_id.mp4?download=1, CDN HEAD 200"
        else
            bad "POST /api/media/$id/download -> $code '$url', CDN HEAD $cdn"
        fi
        if grep -qi '^content-disposition: *attachment' <<<"$headers"; then
            ok "CDN answers the download URL with Content-Disposition: attachment"
        else
            bad "CDN sends no Content-Disposition: attachment for download=1 (see cdn/mod-lua-signed-urls/README.md)"
        fi
        # The origin enforces signatures (#17): the same file without a signature, or with a tampered one, is refused
        unsigned="${url%%\?*}"
        code=$(curl -s -m 15 -o /dev/null -w '%{http_code}' -I "$unsigned" || true)
        if [ "$code" = 403 ]; then ok "CDN refuses the unsigned URL (403)"; else bad "CDN answers the unsigned URL $unsigned with $code (expected 403)"; fi
        code=$(curl -s -m 15 -o /dev/null -w '%{http_code}' -I "${url/Expires=/Expires=9}" || true)
        if [ "$code" = 403 ]; then ok "CDN refuses a tampered signed URL (403)"; else bad "CDN answers a tampered signed URL with $code (expected 403)"; fi
    fi
else
    skip "media-service is not deployed; /api/media not checked"
fi

# Unknown API paths fall through to record-pool; nginx must 404 them, not serve the app
code=$(curl -s -m 10 -o "$body" -w '%{http_code}' "$base/api/no-such-endpoint" || true)
if [ "$code" = 404 ] && ! grep -q '<div id="root">' "$body"; then
    ok "GET $base/api/no-such-endpoint -> 404 (not the app shell)"
else
    bad "GET $base/api/no-such-endpoint -> $code (expected 404)"
fi

if helm test "$RECORD_POOL_RELEASE" -n "$RECORD_POOL_NAMESPACE" --timeout 2m >/dev/null 2>&1; then
    ok "helm test $RECORD_POOL_RELEASE"
else
    bad "helm test $RECORD_POOL_RELEASE (see: helm test $RECORD_POOL_RELEASE -n $RECORD_POOL_NAMESPACE --logs)"
fi

if [ "$fail" -eq 0 ]; then
    echo ">>> record-pool-test: all checks passed"
else
    echo ">>> record-pool-test: FAILED" >&2
    exit 1
fi
