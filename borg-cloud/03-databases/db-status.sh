#!/bin/bash
# =============================================================================
# 03-databases/db-status.sh
# Members, current primary and role for each database.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh

echo "=== PostgreSQL (CNPG cluster pg) ==="
if k get cluster pg >/dev/null 2>&1; then
    k get cluster pg
    k get pods -l cnpg.io/cluster=pg -L cnpg.io/instanceRole -o wide
else
    echo "  not installed"
fi

echo ""
echo "=== MongoDB (replica set mongo) ==="
if k get mongodbcommunity mongo >/dev/null 2>&1; then
    k get mongodbcommunity mongo
    k get pods -l app=mongo-svc -o wide
    for p in $(mongo_pods); do
        printf '  %s: ' "$p"
        mongo_hello "$p" 2>/dev/null \
            | awk '{print ($2 == "true" ? "PRIMARY" : "secondary") "  (primary: " $1 ")"}' \
            || echo "unreachable"
    done
else
    echo "  not installed"
fi

echo ""
echo "=== Redis + Sentinel (StatefulSet redis) ==="
if k get statefulset redis >/dev/null 2>&1; then
    k get pods -l app.kubernetes.io/name=redis -o wide
    for p in $(redis_pods); do
        printf '  %s: ' "$p"
        redis_cli "$p" ROLE 2>/dev/null | head -1 || echo "unreachable"
    done
    printf '  Sentinel primary: '
    redis_primary || echo "unknown"
else
    echo "  not installed"
fi
