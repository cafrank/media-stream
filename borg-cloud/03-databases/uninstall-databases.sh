#!/bin/bash
# =============================================================================
# 03-databases/uninstall-databases.sh
# Removes the databases, their data (PVCs) and Secrets, then the operators.
# Safe on a partial install or when nothing is installed.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh

has_crd() { kubectl get crd "$1" >/dev/null 2>&1; }

echo ">>> Deleting database resources..."
if has_crd clusters.postgresql.cnpg.io; then
    k delete cluster pg --ignore-not-found --wait=true
fi
if has_crd mongodbcommunity.mongodbcommunity.mongodb.com; then
    k delete mongodbcommunity mongo --ignore-not-found --wait=true
fi
render 03-databases/redis.yaml | kubectl delete --ignore-not-found -f - 2>/dev/null || true

echo ">>> Removing MongoDB operator..."
helm uninstall mongodb-kubernetes -n "$DB_NAMESPACE" --wait 2>/dev/null || echo "    (not installed)"

echo ">>> Deleting namespace $DB_NAMESPACE (PVCs, Secrets)..."
kubectl delete namespace "$DB_NAMESPACE" --ignore-not-found --wait=true

echo ">>> Removing CloudNativePG operator..."
helm uninstall cnpg -n "$CNPG_NAMESPACE" --wait 2>/dev/null || echo "    (not installed)"
kubectl delete namespace "$CNPG_NAMESPACE" --ignore-not-found --wait=true

echo ">>> Done. Operator CRDs may remain (their charts keep them); a reinstall reuses them."
