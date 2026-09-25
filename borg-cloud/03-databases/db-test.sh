#!/bin/bash
# =============================================================================
# 03-databases/db-test.sh [all|postgres]
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
        "CREATE TABLE IF NOT EXISTS borg_db_test (id int PRIMARY KEY, v text);
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

case "$target" in
    all)      test_postgres ;;
    postgres) test_postgres ;;
    *) die "usage: $0 [all|postgres]" ;;
esac

if [ "$fail" -eq 0 ]; then
    echo ">>> db-test: all checks passed"
else
    echo ">>> db-test: FAILED" >&2
    exit 1
fi
