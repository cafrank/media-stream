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
