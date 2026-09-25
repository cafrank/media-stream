#!/bin/bash
# =============================================================================
# 03-databases/db-info.sh
# In-cluster connection info. Credentials are read from the Secrets in the cluster.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh

D="$DB_NAMESPACE.svc.cluster.local"
echo "In-cluster connection info (namespace $DB_NAMESPACE)"

echo ""
echo "PostgreSQL"
if k get secret pg-app >/dev/null 2>&1; then
    echo "  primary (rw):  pg-rw.$D:5432"
    echo "  replicas (ro): pg-ro.$D:5432"
    echo "  database: app   user: app   password: $(secret_value pg-app password)"
    echo "  uri:      $(secret_value pg-app uri)"
    echo "  secret:   pg-app (keys: username, password, uri, jdbc-uri)"
else
    echo "  not installed"
fi

echo ""
echo "MongoDB"
if k get secret mongo-media-app >/dev/null 2>&1; then
    echo "  uri:      $(mongo_app_uri)"
    echo "  database: media   user: app (auth database: admin)"
    echo "  secret:   mongo-media-app (key: connectionString.standard; its URI"
    echo "            ends in /admin, so set the database to media when using it)"
else
    echo "  not installed"
fi

echo ""
echo "Redis (Sentinel)"
if k get secret redis-auth >/dev/null 2>&1; then
    echo "  sentinels:   redis-sentinel.$D:26379"
    echo "  master name: mymaster"
    echo "  password:    $(secret_value redis-auth password)   (Redis and Sentinel)"
    echo "  secret:      redis-auth (key: password)"
else
    echo "  not installed"
fi
