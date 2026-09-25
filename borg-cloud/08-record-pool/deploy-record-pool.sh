#!/bin/bash
# =============================================================================
# 08-record-pool/deploy-record-pool.sh
# Builds the record-pool web image from this checkout, pushes it to the
# BorgCloud registry and deploys it with the Helm chart (record-pool/build.sh
# does the build, push and helm upgrade). TAG=<tag> SKIP_BUILD=1 redeploys an
# existing image.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh
source 04-registry/registry-lib.sh
source 07-edge/edge-lib.sh
REPO=$(cd .. && pwd)

preflight
for tool in docker curl ss; do
    command -v "$tool" >/dev/null || die "$tool not found on PATH"
done
registry_ready || die "the registry is not installed or not Available (run: make provision-registry)"
kubectl get ingressclass haproxy >/dev/null 2>&1 || die "the haproxy IngressClass is missing (run: make provision-edge)"

trap stop_registry_forward EXIT
start_registry_forward

IMAGE="localhost:$REGISTRY_LOCAL_PORT/record-pool" \
NAMESPACE="$RECORD_POOL_NAMESPACE" \
RELEASE="$RECORD_POOL_RELEASE" \
VALUES="$REPO/charts/record-pool/values-borg.yaml" \
    bash "$REPO/record-pool/build.sh"

stop_registry_forward
image=$(kubectl -n "$RECORD_POOL_NAMESPACE" get deployment -l app.kubernetes.io/instance="$RECORD_POOL_RELEASE" \
    -o jsonpath='{.items[0].spec.template.spec.containers[0].image}')
echo ">>> Deployed $image"
echo "    http://$VIP_ADDRESS/   (check: make record-pool-test)"
