#!/bin/bash
# =============================================================================
# Build, push and deploy media-service with the Helm chart.
#
#   ./build.sh                      # build + push + deploy to namespace djmz
#   NAMESPACE=media VALUES=../charts/media-service/values-borg.yaml ./build.sh
#   SKIP_BUILD=1 TAG=abc1234 ./build.sh   # redeploy an existing tag
#   PRINT_TAG=1 ./build.sh                # print the tag a build would use
#   (BorgCloud: use `make deploy-media` in borg-cloud/, which wraps this script)
#
# Prereq: docker login --username=cafrank   (hub.docker.com)
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

IMAGE=${IMAGE:-docker.io/cafrank/media3}
# A build of uncommitted changes (including new, untracked files) in the build
# inputs gets a unique tag, so every deploy of such a build changes the image
# and rolls the pods.
BUILD_INPUTS=(src pom.xml ../pom.xml Dockerfile)
if [ -n "$(git status --porcelain -- "${BUILD_INPUTS[@]}")" ]; then
    DIRTY="-dirty-$(date +%Y%m%d%H%M%S)"
fi
TAG=${TAG:-$(git rev-parse --short HEAD)${DIRTY:-}}
if [ -n "${PRINT_TAG:-}" ]; then echo "$TAG"; exit 0; fi   # PRINT_TAG=1: show the tag a build would use
NAMESPACE=${NAMESPACE:-djmz}
RELEASE=${RELEASE:-media-service}
CHART=../charts/media-service
VALUES=${VALUES:-$CHART/values-djmz.yaml}
APP_VERSION=$(sed -n 's/^appVersion: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/p' "$CHART/Chart.yaml")

if [ -z "${SKIP_BUILD:-}" ]; then
    mvn clean package -DskipTests=true
    docker build --no-cache -t "$IMAGE:$TAG" -t "$IMAGE:$APP_VERSION" .
    docker push "$IMAGE:$TAG"
    docker push "$IMAGE:$APP_VERSION"
fi

# HELM_EXTRA_ARGS: extra helm words from a wrapper, e.g. deploy-media.sh.
# shellcheck disable=SC2086
helm upgrade --install "$RELEASE" "$CHART" \
    --namespace "$NAMESPACE" --create-namespace \
    -f "$VALUES" \
    --set image.tag="$TAG" \
    ${HELM_EXTRA_ARGS:-} \
    --wait --timeout 5m

kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/instance="$RELEASE"
