#!/bin/bash
# =============================================================================
# 05-media/deploy-media.sh
# Builds media-service from this checkout, pushes it to the BorgCloud registry
# and deploys it with the Helm chart (media-service/build.sh does the build,
# push and helm upgrade). TAG=<tag> SKIP_BUILD=1 redeploys an existing image.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh
source 04-registry/registry-lib.sh
REPO=$(cd .. && pwd)

preflight
for tool in docker mvn curl ss; do
    command -v "$tool" >/dev/null || die "$tool not found on PATH"
done
k get secret mongo-media-app >/dev/null 2>&1 || die "MongoDB is not installed (run: make provision-databases)"
registry_ready || die "the registry is not installed or not Available (run: make provision-registry)"

echo ">>> Secret media-service-mongodb in namespace $MEDIA_NAMESPACE"
kubectl create namespace "$MEDIA_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
uri=$(mongo_app_uri)
printf '%s' "$uri" | kubectl -n "$MEDIA_NAMESPACE" create secret generic media-service-mongodb \
    --from-file=SPRING_DATA_MONGODB_URI=/dev/stdin --dry-run=client -o yaml | kubectl apply -f - >/dev/null
# A changed URI (e.g. a reinstalled database) changes the pod template, so pods restart
uri_sha=$(printf '%s' "$uri" | sha256sum | cut -c1-16)

trap stop_registry_forward EXIT
start_registry_forward

IMAGE="localhost:$REGISTRY_LOCAL_PORT/media3" \
NAMESPACE="$MEDIA_NAMESPACE" \
RELEASE="$MEDIA_RELEASE" \
VALUES="$REPO/charts/media-service/values-borg.yaml" \
HELM_EXTRA_ARGS="--set-string podAnnotations.borg/mongo-uri-sha=$uri_sha" \
    bash "$REPO/media-service/build.sh"

stop_registry_forward
image=$(kubectl -n "$MEDIA_NAMESPACE" get deployment -l app.kubernetes.io/instance="$MEDIA_RELEASE" \
    -o jsonpath='{.items[0].spec.template.spec.containers[0].image}')
echo ">>> Deployed $image"
echo "    http://$NODE1_IP/api/media   (any node IP works; check: make media-test)"
