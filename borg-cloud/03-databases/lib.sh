#!/bin/bash
# =============================================================================
# 03-databases/lib.sh
# Shared helpers for the 03-databases scripts. Source after vars.sh:
#   source ./vars.sh; source 03-databases/lib.sh
# =============================================================================

# BORG_KUBECONFIG overrides the cluster kubeconfig (edge-failover-test points it at a
# node that stays up). A plain KUBECONFIG from the caller's shell is deliberately
# ignored: it may belong to another cluster.
export KUBECONFIG="${BORG_KUBECONFIG:-$KUBECONFIG_OUT}"
export DB_NAMESPACE DB_STORAGE_SIZE PG_IMAGE PG_MEMORY MONGODB_VERSION MONGO_MEMORY \
       REDIS_IMAGE REDIS_MEMORY SENTINEL_MEMORY

# Only these variables are substituted into manifests, so shell code inside
# ConfigMaps (e.g. $REDIS_PASSWORD) is left untouched.
# shellcheck disable=SC2016
MANIFEST_VARS='${DB_NAMESPACE} ${DB_STORAGE_SIZE} ${PG_IMAGE} ${PG_MEMORY} ${MONGODB_VERSION} ${MONGO_MEMORY} ${REDIS_IMAGE} ${REDIS_MEMORY} ${SENTINEL_MEMORY}'

k() { kubectl -n "$DB_NAMESPACE" "$@"; }

die() { echo "ERROR: $*" >&2; exit 1; }

preflight() {
    local tool ready
    for tool in kubectl helm envsubst openssl; do
        command -v "$tool" >/dev/null || die "$tool not found on PATH"
    done
    [ -f "$KUBECONFIG_OUT" ] || die "$KUBECONFIG_OUT not found. Run: make kubeconfig"
    ready=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 == "Ready"' | wc -l)
    [ "$ready" -eq 3 ] || die "expected 3 Ready nodes, found $ready (see: make cluster-status)"
}

ensure_namespace() {
    kubectl create namespace "$DB_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
}

# ensure_secret <name> <key>: create with a random value only if the Secret is absent
ensure_secret() {
    local name=$1 key=$2
    if k get secret "$name" >/dev/null 2>&1; then
        echo "    secret/$name exists (kept)"
    else
        k create secret generic "$name" --from-literal="$key=$(openssl rand -hex 24)" >/dev/null
        echo "    secret/$name created"
    fi
}

# secret_value <secret> <key>: decoded value (dots in the key are escaped for jsonpath)
secret_value() {
    k get secret "$1" -o jsonpath="{.data.${2//./\\.}}" | base64 -d
}

render() { envsubst "$MANIFEST_VARS" < "$1"; }
apply_manifest() { render "$1" | kubectl apply -f -; }

# wait_for <description> <command...>: retry every 5s until DB_WAIT_TIMEOUT,
# then print pods and recent events and exit non-zero
wait_for() {
    local desc=$1 deadline; shift
    deadline=$(( $(date +%s) + DB_WAIT_TIMEOUT ))
    echo ">>> Waiting for $desc (up to ${DB_WAIT_TIMEOUT}s)..."
    until "$@" >/dev/null 2>&1; do
        if [ "$(date +%s)" -ge "$deadline" ]; then
            echo "ERROR: timed out waiting for $desc" >&2
            kubectl -n "${WAIT_NAMESPACE:-$DB_NAMESPACE}" get pods -o wide >&2 || true
            kubectl -n "${WAIT_NAMESPACE:-$DB_NAMESPACE}" get events --sort-by=.lastTimestamp 2>/dev/null \
                | tail -20 >&2 || true
            exit 1
        fi
        sleep 5
    done
    echo "    $desc: ready"
}

# retry <tries> <command...>: every 2s; returns 0 on the first success
retry() {
    local n=$1 i; shift
    for i in $(seq 1 "$n"); do
        "$@" && return 0
        [ "$i" -lt "$n" ] && sleep 2
    done
    return 1
}

# ---- PostgreSQL (CloudNativePG cluster "pg") ----
pg_primary() { k get cluster pg -o jsonpath='{.status.currentPrimary}'; }
pg_ready()   { [ "$(k get cluster pg -o jsonpath='{.status.readyInstances}')" = 3 ]; }
pg_pods()    { k get pods -l cnpg.io/cluster=pg -o jsonpath='{.items[*].metadata.name}'; }
# pg_sql <pod> <sql>: psql as the postgres superuser over the pod's local socket, database app
pg_sql()     { k exec "$1" -c postgres -- psql -d app -v ON_ERROR_STOP=1 -tAc "$2"; }

# ---- MongoDB (MongoDBCommunity "mongo") ----
mongo_pods()  { echo mongo-0 mongo-1 mongo-2; }
mongo_ready() { [ "$(k get mongodbcommunity mongo -o jsonpath='{.status.phase}')" = Running ]; }
# mongo_hello <pod>: prints "<primary host> <isWritablePrimary>" (hello needs no auth)
mongo_hello() {
    k exec "$1" -c mongod -- env HOME=/tmp mongosh --quiet --eval \
        'const h = db.hello(); print(h.primary + " " + h.isWritablePrimary)'
}
# mongo_primary: pod name of the current primary, as seen by the first member that answers
mongo_primary() {
    local p host
    for p in $(mongo_pods); do
        host=$(mongo_hello "$p" 2>/dev/null | awk '{print $1}') || continue
        if [ -n "$host" ] && [ "$host" != undefined ]; then echo "${host%%.*}"; return 0; fi
    done
    return 1
}
# mongo_eval <pod> <uri> <js>
mongo_eval() { k exec "$1" -c mongod -- env HOME=/tmp mongosh "$2" --quiet --eval "$3"; }
# mongo_app_uri: the operator's replica-set URI, with media as the default database.
# The operator's own URI (secret mongo-media-app) points at /admin, where the app
# user has no rights, so a driver that uses the URI's database would be refused.
mongo_app_uri() {
    secret_value mongo-media-app connectionString.standard | sed 's|/admin?|/media?authSource=admin\&|'
}
# mongo_uri_for <pod>: direct connection to one member as the app user
mongo_uri_for() {
    echo "mongodb://app:$(secret_value mongo-app-password password)@$1.mongo-svc.$DB_NAMESPACE.svc.cluster.local:27017/media?authSource=admin&directConnection=true&readPreference=secondaryPreferred"
}

# ---- Redis + Sentinel (StatefulSet "redis") ----
redis_pods() { echo redis-0 redis-1 redis-2; }
# redis_cli <pod> <args...>: redis-cli in the pod's redis container, authenticated
# shellcheck disable=SC2016
redis_cli() {
    local p=$1; shift
    k exec "$p" -c redis -- sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning "$@"' _ "$@"
}
# sentinel_cli <args...>: ask the first Sentinel that answers
# shellcheck disable=SC2016
sentinel_cli() {
    local p
    for p in $(redis_pods); do
        k exec "$p" -c sentinel -- sh -c \
            'redis-cli -p 26379 -a "$REDIS_PASSWORD" --no-auth-warning "$@"' _ "$@" 2>/dev/null && return 0
    done
    return 1
}
# redis_primary: pod name of the primary according to Sentinel
redis_primary() {
    local h
    h=$(sentinel_cli SENTINEL get-master-addr-by-name mymaster | head -1)
    [ -n "$h" ] && echo "${h%%.*}"
}
# redis_ready: 3 pods Ready, and Sentinel knows 2 replicas and 2 other Sentinels
redis_ready() {
    local info
    [ "$(k get statefulset redis -o jsonpath='{.status.readyReplicas}')" = 3 ] || return 1
    info=$(sentinel_cli SENTINEL master mymaster) || return 1
    [ "$(echo "$info" | awk 'p == "num-slaves" {print; exit} {p = $0}')" = 2 ] &&
    [ "$(echo "$info" | awk 'p == "num-other-sentinels" {print; exit} {p = $0}')" = 2 ]
}
