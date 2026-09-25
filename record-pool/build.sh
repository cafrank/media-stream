#!/bin/bash
# =============================================================================
# Build, push and deploy the record-pool web app with the Helm chart.
#
#   IMAGE=localhost:5050/record-pool NAMESPACE=record-pool \
#     VALUES=../charts/record-pool/values-borg.yaml ./build.sh
#   SKIP_BUILD=1 TAG=abc1234 ./build.sh   # redeploy an existing tag
#   PRINT_TAG=1 ./build.sh                # print the tag a build would use
#   (BorgCloud: use `make deploy-record-pool` in borg-cloud/, which wraps this script)
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

IMAGE=${IMAGE:-docker.io/cafrank/record-pool}
# A build of uncommitted changes (including new, untracked files) in the build
# inputs gets a unique tag, so every deploy of such a build changes the image
# and rolls the pods.
BUILD_INPUTS=(app assets components constants hooks app.json package.json package-lock.json
    tsconfig.json Dockerfile nginx.conf .dockerignore)
if [ -n "$(git status --porcelain -- "${BUILD_INPUTS[@]}")" ]; then
    DIRTY="-dirty-$(date +%Y%m%d%H%M%S)"
fi
TAG=${TAG:-$(git rev-parse --short HEAD)${DIRTY:-}}
if [ -n "${PRINT_TAG:-}" ]; then echo "$TAG"; exit 0; fi
NAMESPACE=${NAMESPACE:-record-pool}
RELEASE=${RELEASE:-record-pool}
CHART=../charts/record-pool
VALUES=${VALUES:-$CHART/values.yaml}
APP_VERSION=$(sed -n 's/^appVersion: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/p' "$CHART/Chart.yaml")

if [ -z "${SKIP_BUILD:-}" ]; then
    docker build --build-arg EXPO_PUBLIC_API_URL="${EXPO_PUBLIC_API_URL:-}" \
        -t "$IMAGE:$TAG" -t "$IMAGE:$APP_VERSION" .
    docker push "$IMAGE:$TAG"
    docker push "$IMAGE:$APP_VERSION"
fi

# HELM_EXTRA_ARGS: extra helm words from a wrapper, e.g. deploy-record-pool.sh.
# shellcheck disable=SC2086
helm upgrade --install "$RELEASE" "$CHART" \
    --namespace "$NAMESPACE" --create-namespace \
    -f "$VALUES" \
    --set image.tag="$TAG" \
    ${HELM_EXTRA_ARGS:-} \
    --wait --timeout 5m

kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/instance="$RELEASE"
