#!/bin/bash
# =============================================================================
# 04-registry/registry-lib.sh
# Registry helpers. Source after vars.sh and 03-databases/lib.sh.
# =============================================================================

export REGISTRY_NAMESPACE REGISTRY_IMAGE REGISTRY_NODEPORT REGISTRY_LOCAL_PORT REGISTRY_STORAGE_SIZE

# Only these variables are substituted into 04-registry templates.
# shellcheck disable=SC2016
REGISTRY_VARS='${REGISTRY_NAMESPACE} ${REGISTRY_IMAGE} ${REGISTRY_NODEPORT} ${REGISTRY_LOCAL_PORT} ${REGISTRY_STORAGE_SIZE} ${NODE_IP}'

kr() { kubectl -n "$REGISTRY_NAMESPACE" "$@"; }

render_registry() { envsubst "$REGISTRY_VARS" < "$1"; }

registry_ready() {
    [ "$(kr get deployment registry -o jsonpath='{.status.availableReplicas}' 2>/dev/null)" = 1 ]
}

REGISTRY_FORWARD_PID=""

# start_registry_forward: port-forward localhost:$REGISTRY_LOCAL_PORT to the registry.
# Refuses if the port is already taken, so a push can't reach a different registry.
start_registry_forward() {
    if ss -ltn | awk '{print $4}' | grep -qE "[:.]$REGISTRY_LOCAL_PORT\$"; then
        die "port $REGISTRY_LOCAL_PORT is already in use on this host (REGISTRY_LOCAL_PORT in vars.sh)"
    fi
    # kubectl directly, not the kr function: backgrounding a function forks a
    # subshell, so $! would be the subshell and kill would orphan kubectl.
    kubectl -n "$REGISTRY_NAMESPACE" port-forward svc/registry "$REGISTRY_LOCAL_PORT:5000" >/dev/null 2>&1 &
    REGISTRY_FORWARD_PID=$!
    if ! retry 15 curl -sf -o /dev/null "http://localhost:$REGISTRY_LOCAL_PORT/v2/"; then
        stop_registry_forward
        die "registry port-forward on localhost:$REGISTRY_LOCAL_PORT did not come up"
    fi
}

stop_registry_forward() {
    if [ -n "$REGISTRY_FORWARD_PID" ]; then
        kill "$REGISTRY_FORWARD_PID" 2>/dev/null || true
        wait "$REGISTRY_FORWARD_PID" 2>/dev/null || true
    fi
    REGISTRY_FORWARD_PID=""
    return 0
}
