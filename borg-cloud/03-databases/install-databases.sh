#!/bin/bash
# =============================================================================
# 03-databases/install-databases.sh [all|postgres|mongo]
# Runs from HOST. Installs the data tier into k3s (namespace $DB_NAMESPACE).
# Safe to re-run: operators are helm upgrades, resources are kubectl apply,
# and existing Secrets are never regenerated.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh
source 03-databases/operators.sh

install_postgres() {
    echo ">>> PostgreSQL: CloudNativePG operator"
    install_cnpg
    echo ">>> PostgreSQL: Cluster pg (3 instances)"
    apply_manifest 03-databases/postgres.yaml
    wait_for "PostgreSQL (3 ready instances)" pg_ready
}

install_mongo() {
    echo ">>> MongoDB: operator"
    install_mongodb_operator
    echo ">>> MongoDB: replica set mongo (3 members)"
    ensure_secret mongo-app-password password
    apply_manifest 03-databases/mongodb.yaml
    wait_for "MongoDB (replica set Running)" mongo_ready
}

target=${1:-all}
case "$target" in
    all|postgres|mongo) ;;
    *) die "usage: $0 [all|postgres|mongo]" ;;
esac

preflight
ensure_namespace

case "$target" in
    all)      install_postgres; install_mongo ;;
    postgres) install_postgres ;;
    mongo)    install_mongo ;;
esac
echo ">>> Databases ready. Connection info: make db-info"
