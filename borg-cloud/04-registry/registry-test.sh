#!/bin/bash
# =============================================================================
# 04-registry/registry-test.sh
# Pushes a one-layer test image through the port-forward, then pulls it by its
# localhost:<port>/... name on each node (a pod pinned to the node), proving the
# push path and every node's mirror config.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh
source 04-registry/registry-lib.sh

fail=0
ok()  { echo "  PASS  $*"; }
bad() { echo "  FAIL  $*"; fail=1; }

registry_ready || die "registry is not installed or not Available (run: make provision-registry)"

tag=$(date +%s)
image="localhost:$REGISTRY_LOCAL_PORT/borg-registry-test:$tag"
ctx=$(mktemp -d)
trap 'stop_registry_forward; rm -rf "$ctx"' EXIT

printf 'FROM busybox:1.36\nRUN echo "%s" > /borg-registry-test\n' "$tag" > "$ctx/Dockerfile"
docker build -q -t "$image" "$ctx" >/dev/null

start_registry_forward
if docker push -q "$image" >/dev/null; then ok "push $image"; else bad "push $image"; fi
stop_registry_forward
docker rmi "$image" >/dev/null

pod_succeeded() { [ "$(kr get pod "$1" -o jsonpath='{.status.phase}' 2>/dev/null)" = Succeeded ]; }

for i in 1 2 3; do
    name_var="NODE${i}_NAME"
    node=${!name_var}
    pod="registry-test-$node"
    kr delete pod "$pod" --ignore-not-found >/dev/null
    kr run "$pod" --image="$image" --image-pull-policy=Always --restart=Never \
        --overrides="{\"spec\":{\"nodeName\":\"$node\"}}" -- cat /borg-registry-test >/dev/null
    if retry 30 pod_succeeded "$pod" && [ "$(kr logs "$pod")" = "$tag" ]; then
        ok "pull on $node"
    else
        bad "pull on $node: $(kr get pod "$pod" -o jsonpath='{.status.containerStatuses[0].state}' 2>/dev/null)"
    fi
    kr delete pod "$pod" --ignore-not-found --wait=false >/dev/null
done

if [ "$fail" -eq 0 ]; then
    echo ">>> registry-test: all checks passed"
else
    echo ">>> registry-test: FAILED" >&2
    exit 1
fi
