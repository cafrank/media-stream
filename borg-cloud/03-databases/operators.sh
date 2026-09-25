#!/bin/bash
# =============================================================================
# 03-databases/operators.sh
# Pinned operator installs. Sourced by install-databases.sh (after vars.sh, lib.sh).
# =============================================================================

# CloudNativePG: cluster-wide operator in $CNPG_NAMESPACE
install_cnpg() {
    helm repo add cnpg https://cloudnative-pg.github.io/charts --force-update >/dev/null
    helm repo update cnpg >/dev/null
    helm upgrade --install cnpg cnpg/cloudnative-pg \
        --version "$CNPG_CHART_VERSION" \
        --namespace "$CNPG_NAMESPACE" --create-namespace \
        --wait --timeout "${DB_WAIT_TIMEOUT}s"
}

# MongoDB Controllers for Kubernetes (successor to the archived
# mongodb-kubernetes-operator), in $DB_NAMESPACE, reconciling only MongoDBCommunity.
# The chart also creates the mongodb-kubernetes-appdb ServiceAccount used by the pods.
install_mongodb_operator() {
    helm repo add mongodb https://mongodb.github.io/helm-charts --force-update >/dev/null
    helm repo update mongodb >/dev/null
    helm upgrade --install mongodb-kubernetes mongodb/mongodb-kubernetes \
        --version "$MONGODB_OPERATOR_CHART_VERSION" \
        --namespace "$DB_NAMESPACE" \
        --set 'operator.watchedResources={mongodbcommunity}' \
        --set operator.telemetry.enabled=false \
        --set operator.resources.requests.cpu=100m \
        --wait --timeout "${DB_WAIT_TIMEOUT}s"
}
