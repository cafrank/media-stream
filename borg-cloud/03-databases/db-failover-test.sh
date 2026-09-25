#!/bin/bash
# =============================================================================
# 03-databases/db-failover-test.sh [all|postgres|mongo|redis]
# DISRUPTIVE: for each database, deletes the primary pod, then checks that
# another member is promoted, writes work again, and the old pod rejoins as
# a replica. Not part of `make up`.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh

# primary_changed <primary-fn> <old-pod>: the function reports a primary other than old
primary_changed() { local now; now=$("$1" 2>/dev/null) && [ -n "$now" ] && [ "$now" != "$2" ]; }

mongo_is_secondary() {
    mongo_hello "$1" 2>/dev/null | awk '$1 != "undefined" && $2 == "false" {ok = 1} END {exit !ok}'
}
redis_is_replica() { [ "$(redis_cli "$1" ROLE 2>/dev/null | head -1)" = slave ]; }

failover_postgres() {
    local old
    old=$(pg_primary)
    echo ">>> PostgreSQL: deleting primary pod $old"
    k delete pod "$old" --wait=false
    wait_for "PostgreSQL new primary (not $old)" primary_changed pg_primary "$old"
    echo "    new primary: $(pg_primary)"
    wait_for "PostgreSQL 3 ready instances ($old rejoined as replica)" pg_ready
    bash 03-databases/db-test.sh postgres
}

failover_mongo() {
    local old
    old=$(mongo_primary)
    echo ">>> MongoDB: deleting primary pod $old"
    k delete pod "$old" --wait=false
    wait_for "MongoDB new primary (not $old)" primary_changed mongo_primary "$old"
    echo "    new primary: $(mongo_primary)"
    wait_for "MongoDB $old rejoined as secondary" mongo_is_secondary "$old"
    wait_for "MongoDB replica set Running" mongo_ready
    bash 03-databases/db-test.sh mongo
}

failover_redis() {
    local old
    old=$(redis_primary)
    echo ">>> Redis: deleting primary pod $old"
    k delete pod "$old" --wait=false
    wait_for "Redis new primary (not $old)" primary_changed redis_primary "$old"
    echo "    new primary: $(redis_primary)"
    wait_for "Redis $old rejoined as replica" redis_is_replica "$old"
    wait_for "Redis (3 pods, Sentinel sees 2 replicas)" redis_ready
    bash 03-databases/db-test.sh redis
}

target=${1:-all}
case "$target" in
    all)      failover_postgres; failover_mongo; failover_redis ;;
    postgres) failover_postgres ;;
    mongo)    failover_mongo ;;
    redis)    failover_redis ;;
    *) die "usage: $0 [all|postgres|mongo|redis]" ;;
esac
echo ">>> db-failover-test: passed"
