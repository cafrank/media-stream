#!/bin/bash
# =============================================================================
# 03-databases/db-test.sh [all|postgres|mongo|redis]
# Non-destructive check: write through the primary (using the same Services and
# credentials an app would), then read the value back on every replica.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh

target=${1:-all}
token="borg-$(date +%s)-$RANDOM"
fail=0
ok()  { echo "  PASS  $*"; }
bad() { echo "  FAIL  $*"; fail=1; }

pg_has_token() { [ "$(pg_sql "$1" "SELECT v FROM borg_db_test WHERE id = 1" 2>/dev/null)" = "$token" ]; }

test_postgres() {
    echo ">>> PostgreSQL"
    local primary uri p
    primary=$(pg_primary 2>/dev/null) && [ -n "$primary" ] || { bad "no primary reported"; return; }
    uri=$(secret_value pg-app uri 2>/dev/null) && [ -n "$uri" ] || { bad "secret pg-app missing"; return; }
    # App path: the pg-rw Service with the generated app credentials
    if k exec "$primary" -c postgres -- psql "$uri" -v ON_ERROR_STOP=1 -tAc \
        "SET client_min_messages = warning;
         CREATE TABLE IF NOT EXISTS borg_db_test (id int PRIMARY KEY, v text);
         INSERT INTO borg_db_test VALUES (1, '$token') ON CONFLICT (id) DO UPDATE SET v = EXCLUDED.v;" >/dev/null; then
        ok "write via pg-rw as app (primary $primary)"
    else
        bad "write via pg-rw as app"; return
    fi
    for p in $(pg_pods); do
        [ "$p" = "$primary" ] && continue
        if retry 15 pg_has_token "$p"; then ok "read on replica $p"; else bad "read on replica $p"; fi
    done
}

mongo_has_token() {
    [ "$(mongo_eval "$1" "$(mongo_uri_for "$1")" \
        'const d = db.getSiblingDB("media").borg_db_test.findOne({_id: 1}); print(d ? d.v : "")' \
        2>/dev/null)" = "$token" ]
}

test_mongo() {
    echo ">>> MongoDB"
    local primary uri p
    primary=$(mongo_primary 2>/dev/null) || { bad "no primary found"; return; }
    uri=$(mongo_app_uri 2>/dev/null) && [ -n "$uri" ] \
        || { bad "secret mongo-media-app missing"; return; }
    # App path: the URI's own default database (what a driver like Spring uses), majority write
    if mongo_eval "$primary" "$uri" \
        "db.borg_db_test.replaceOne({_id: 1}, {_id: 1, v: '$token'}, {upsert: true, writeConcern: {w: 'majority', wtimeout: 10000}})" >/dev/null; then
        ok "majority write via connection string (primary $primary)"
    else
        bad "majority write via connection string"; return
    fi
    for p in $(mongo_pods); do
        [ "$p" = "$primary" ] && continue
        if retry 15 mongo_has_token "$p"; then ok "read on secondary $p"; else bad "read on secondary $p"; fi
    done
}

redis_has_token() { [ "$(redis_cli "$1" GET borg_db_test 2>/dev/null)" = "$token" ]; }

test_redis() {
    echo ">>> Redis"
    local via_service primary p
    # App path: ask the redis-sentinel Service (not a specific pod) for the primary
    via_service=$(redis_cli redis-0 -h redis-sentinel -p 26379 SENTINEL get-master-addr-by-name mymaster 2>/dev/null | head -1) || true
    [ -n "$via_service" ] && ok "redis-sentinel Service reports primary ${via_service%%.*}" \
        || { bad "redis-sentinel Service did not answer"; return; }
    primary=${via_service%%.*}
    if [ "$(redis_cli "$primary" SET borg_db_test "$token" 2>/dev/null)" = OK ]; then
        ok "write on primary $primary"
    else
        bad "write on primary $primary"; return
    fi
    for p in $(redis_pods); do
        [ "$p" = "$primary" ] && continue
        if retry 15 redis_has_token "$p"; then ok "read on replica $p"; else bad "read on replica $p"; fi
    done
}

case "$target" in
    all)      test_postgres; test_mongo; test_redis ;;
    postgres) test_postgres ;;
    mongo)    test_mongo ;;
    redis)    test_redis ;;
    *) die "usage: $0 [all|postgres|mongo|redis]" ;;
esac

if [ "$fail" -eq 0 ]; then
    echo ">>> db-test: all checks passed"
else
    echo ">>> db-test: FAILED" >&2
    exit 1
fi
