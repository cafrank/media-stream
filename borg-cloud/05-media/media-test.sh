#!/bin/bash
# =============================================================================
# 05-media/media-test.sh
# HTTP checks against media-service through HAProxy on the VIP: the full
# list, paged search and facets (with parity against the old client-side
# filtering), the search indexes and latency. Never calls DELETE /api/media
# (it deletes every record): the test record is removed directly in MongoDB
# afterwards.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh
source 07-edge/edge-lib.sh

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

code=$(curl -s -m 10 -o "$body" -w '%{http_code}' "http://$VIP_ADDRESS/api/media" || true)
if [ "$code" = 200 ] && head -c1 "$body" | grep -q '\['; then
    ok "GET http://$VIP_ADDRESS/api/media -> 200 (JSON array)"
else
    bad "GET http://$VIP_ADDRESS/api/media -> $code"
fi

# ---- GET /api/media/search and /facets (#16) ----
# The full list in $body is the reference: the old client-side rules, applied with jq
api="http://$VIP_ADDRESS/api/media"
all_total=$(jq length "$body" 2>/dev/null || echo -1)
search() { curl -s -m 10 -G "$api/search" "$@"; }
# expected <q> <genre> <version>: matches under the old client-side rules (substring of title+artist, lower-cased)
expected() {
    jq --arg q "$1" --arg g "$2" --arg v "$3" '[.[] | select(
        (((.title // "") + "\n" + (.artist // "")) | ascii_downcase | contains($q | ascii_downcase))
        and ($g == "" or .genre == $g) and ($v == "" or .remix == $v))] | length' "$body"
}

page=$(search --data-urlencode size=5)
if [ "$(jq '.items | length' <<<"$page")" = 5 ] && [ "$(jq .total <<<"$page")" = "$all_total" ] && [ "$(jq .page <<<"$page")" = 0 ]; then
    ok "GET /api/media/search?size=5 -> 5 items, total $all_total (= full list)"
else
    bad "GET /api/media/search?size=5 -> $(head -c 200 <<<"$page")"
fi

newest=$(jq -r '.items[0].id' <<<"$page" 2>/dev/null || true)   # || true: set -e, and page may not be JSON
if [ "$newest" = "$(jq -r 'max_by(.id) | .id' "$body")" ]; then ok "search is newest first (_id descending)"; else bad "search's first item $newest is not the newest _id"; fi

for bad_params in "size=0" "size=201" "page=-1" "size=abc"; do
    code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' "$api/search?$bad_params" || true)
    if [ "$code" = 400 ]; then ok "GET /api/media/search?$bad_params -> 400"; else bad "GET /api/media/search?$bad_params -> $code (expected 400)"; fi
done

facets=$(curl -s -m 10 "$api/facets" || true)
genre=$(jq -r '.genres[0] // empty' <<<"$facets" 2>/dev/null || true)
version=$(jq -r '.versions[0] // empty' <<<"$facets" 2>/dev/null || true)
if [ -n "$genre" ] && [ -n "$version" ] && [ "$(jq '.genres | . == (sort | unique)' <<<"$facets")" = true ]; then
    ok "GET /api/media/facets -> $(jq '.genres | length' <<<"$facets") genres, $(jq '.versions | length' <<<"$facets") versions (sorted, distinct)"
else
    bad "GET /api/media/facets -> $(head -c 200 <<<"$facets")"
fi

# Parity with the old client-side filtering: q, regex metacharacters taken literally, genre, version, combined
top_genre=$(jq -r '[.[].genre | select(. != null and . != "")] | group_by(.) | max_by(length) | .[0]' "$body")
while IFS='|' read -r q g v; do
    want=$(expected "$q" "$g" "$v")
    got=$(search --data-urlencode "q=$q" --data-urlencode "genre=$g" --data-urlencode "version=$v" --data-urlencode size=1 | jq .total 2>/dev/null || echo error)
    if [ "$got" = "$want" ]; then ok "search q='$q' genre='$g' version='$v' -> total $got (= client-side rules)"; else bad "search q='$q' genre='$g' version='$v' -> $got, client-side rules give $want"; fi
done <<EOF
nirvana||
LOVE||
a.b||
(||
zzzzqqq||
|$top_genre|
||$version
love|$top_genre|
EOF

p=$(mongo_primary 2>/dev/null || true)
indexes=$( [ -n "$p" ] && mongo_eval "$p" "$(mongo_app_uri)" 'db.media.getIndexes().map(i => i.name).join(",")' 2>/dev/null || true)
if grep -q 'genre_1__id_-1' <<<"$indexes" && grep -q 'remix_1__id_-1' <<<"$indexes"; then
    ok "indexes genre_1__id_-1 and remix_1__id_-1 exist"
else
    bad "search indexes missing (have: $indexes)"
fi

# Latency: best of 3, first page, no filter
ms=$(for i in 1 2 3; do curl -s -m 10 -o /dev/null -w '%{time_total}\n' "$api/search?page=0&size=50"; done | sort -n | head -1 | awk '{printf "%d", $1 * 1000}')
if [ "$ms" -lt 100 ]; then ok "GET /api/media/search?page=0&size=50 in ${ms} ms (< 100)"; else bad "GET /api/media/search?page=0&size=50 took ${ms} ms (>= 100)"; fi

code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
    -d "{\"title\":\"$token\",\"artist\":\"borg-media-test\"}" "http://$VIP_ADDRESS/api/media" || true)
if [ "$code" = 201 ]; then ok "POST via $VIP_ADDRESS -> 201"; else bad "POST via $VIP_ADDRESS -> $code"; fi

out=$(curl -s -m 10 "http://$VIP_ADDRESS/api/media/$token" || true)
if grep -q "\"title\":\"$token\"" <<<"$out"; then
    ok "GET by title via $VIP_ADDRESS returns the record (stored in MongoDB)"
else
    bad "GET by title via $VIP_ADDRESS did not return the record"
fi

if [ "$fail" -eq 0 ]; then
    echo ">>> media-test: all checks passed"
else
    echo ">>> media-test: FAILED" >&2
    exit 1
fi
