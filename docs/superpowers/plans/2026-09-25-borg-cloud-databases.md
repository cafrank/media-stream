# BorgCloud Data Tier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `make provision-databases` (and `make up`) installs PostgreSQL, MongoDB and Redis into the BorgCloud k3s cluster, with 3 members each, one per node, and automatic failover.

**Architecture:** A new host-side step, `borg-cloud/03-databases/`, in the same style as steps 01 and 02: bash scripts that source `vars.sh`, plus manifests rendered with `envsubst`. Postgres runs under the CloudNativePG operator, MongoDB under the MongoDB operator (`MongoDBCommunity` resource), and Redis as a plain StatefulSet with a Sentinel sidecar. Checks (`db-test`, `db-failover-test`) run against the live cluster through `kubectl exec`.

**Tech Stack:** bash, GNU make, kubectl 1.36, helm 4, envsubst, k3s `local-path` storage, CloudNativePG, the MongoDB Controllers for Kubernetes (`mongodb/mongodb-kubernetes`), and Redis 8 + Sentinel.

**Spec:** `docs/superpowers/specs/2026-09-25-borg-cloud-databases-design.md`

## Global Constraints

- Everything lives under `borg-cloud/`. File paths in **Files:** blocks are relative to it; `Run:` commands `cd borg-cloud` first; `git add`/`git commit` steps run from the repository root.
- Namespace: `databases` (`DB_NAMESPACE`). The CNPG operator runs in `cnpg-system` (`CNPG_NAMESPACE`).
- 3 members per database, with **required** pod anti-affinity on `kubernetes.io/hostname`, so there is exactly one member per node.
- Storage: the `local-path` StorageClass, `2Gi` per member (`DB_STORAGE_SIZE`).
- Memory defaults: Postgres `512Mi`, MongoDB `512Mi`, Redis `256Mi`, Sentinel `64Mi`. All are set in `vars.sh`.
- Pinned versions (in `vars.sh`): CNPG chart `0.29.1`, MongoDB operator chart `1.12.0`, `ghcr.io/cloudnative-pg/postgresql:17.11`, MongoDB `7.0.43`, and `redis:8.10.2-alpine`.
- Names: Postgres `Cluster` `pg` (Services `pg-rw`/`pg-ro`/`pg-r`, Secret `pg-app`); `MongoDBCommunity` `mongo` (user `app` on the database `media`, password Secret `mongo-app-password`, connection Secret `mongo-media-app`); StatefulSet `redis` (Services `redis-headless` and `redis-sentinel`, Secret `redis-auth`, master name `mymaster`, quorum 2).
- Credentials are generated in the cluster (`openssl rand -hex 24`, so they are URI-safe) and only if the Secret is absent. They are never written to disk.
- Scripts use `set -euo pipefail`, run from the host, `cd` to `borg-cloud/` and `source ./vars.sh`, as `01-base` and `02-k3s` do.
- Readiness waits time out after `DB_WAIT_TIMEOUT=300` seconds. On timeout they print pods and recent events, then exit non-zero.
- `make up` = `vagrant-up cluster provision-databases`. `make cluster` is unchanged.
- Out of scope: backups, TLS, access from outside the cluster, monitoring, and changes to media-service.
- The work happens on branch `borg-cloud-databases`, against the live cluster (`~/.kube/config-borg`). **Never run `make vagrant-destroy`** without the user's explicit go-ahead.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Review Focus

1. **Re-running `make provision-databases` on a healthy tier.** It should change nothing: the same Secrets and the same pods (no restarts). Pinned in Task 6, Step 3.
2. **The whole Redis set restarting at once** (rollout, or VMs halted and started). There must be exactly one primary afterwards and Sentinel must track it. Pinned in Task 3, Step 6.
3. **An app connecting through the Services with the generated credentials,** not only `kubectl exec` over local sockets. `db-test` must use the `pg-rw` URI, the MongoDB connection-string Secret and the `redis-sentinel` Service. Pinned in Tasks 1, 2 and 3 (`db-test` steps).
4. **Running `make db-uninstall` when nothing, or only part, is installed.** It should finish cleanly, not fail on a missing resource type. Pinned in Task 6, Step 5.
5. **Host missing `kubectl` or `helm`.** Provisioning should stop at the start with a message naming the missing tool, not partway through. Pinned in Task 1, Step 7.

---

## File Structure

| File | Responsibility |
|---|---|
| `vars.sh` (modify) | New `# --- Databases ---` block: namespace, pinned versions, sizes, timeout |
| `03-databases/lib.sh` (create) | Shared helpers: kubectl wrapper, preflight, Secrets, rendering, waits, and per-database primary/readiness probes |
| `03-databases/operators.sh` (create) | `install_cnpg` and `install_mongodb_operator` (pinned `helm upgrade --install`) |
| `03-databases/postgres.yaml` (create) | CNPG `Cluster` `pg` |
| `03-databases/mongodb.yaml` (create) | `MongoDBCommunity` `mongo` |
| `03-databases/redis.yaml` (create) | Redis ConfigMap (init script), two Services, StatefulSet |
| `03-databases/install-databases.sh` (create) | Entry point `[all\|postgres\|mongo\|redis]` |
| `03-databases/db-test.sh` (create) | Non-destructive replication and connectivity check |
| `03-databases/db-status.sh` (create) | Members, primary and role per database |
| `03-databases/db-info.sh` (create) | Connection strings and credentials read from Secrets |
| `03-databases/db-failover-test.sh` (create) | Disruptive failover check |
| `03-databases/uninstall-databases.sh` (create) | Removes the databases, data and operators |
| `Makefile` (modify) | New targets, `up` includes databases, `help` |

---

### Task 1: Scaffolding + PostgreSQL

**Files:**
- Modify: `vars.sh` (insert before `# --- Derived lists`)
- Create: `03-databases/lib.sh`, `03-databases/operators.sh`, `03-databases/postgres.yaml`, `03-databases/install-databases.sh`, `03-databases/db-test.sh`
- Modify: `Makefile` (variables, new targets)

**Interfaces:**
- Produces (lib.sh, used by every later task): `k <kubectl args>`, `die <msg>`, `preflight`, `ensure_namespace`, `ensure_secret <name> <key>`, `secret_value <secret> <key>`, `render <file>`, `apply_manifest <file>`, `wait_for <desc> <cmd...>`, `retry <tries> <cmd...>`, `pg_primary`, `pg_ready`, `pg_pods`, `pg_sql <pod> <sql>`.
- Produces (operators.sh): `install_cnpg`.
- Produces: `install-databases.sh [all|postgres]` and `db-test.sh [all|postgres]`. Tasks 2 and 3 add `mongo` and `redis` arms to both `case` statements.

- [ ] **Step 1: Add the database settings to `vars.sh`**

Insert this block directly above the line `# --- Derived lists (space-separated for loops) ---`:

```bash
# --- Databases (03-databases) ---
DB_NAMESPACE="databases"
CNPG_NAMESPACE="cnpg-system"
CNPG_CHART_VERSION="0.29.1"                # cnpg/cloudnative-pg -> operator 1.30.1
MONGODB_OPERATOR_CHART_VERSION="1.12.0"    # mongodb/mongodb-kubernetes
PG_IMAGE="ghcr.io/cloudnative-pg/postgresql:17.11"
MONGODB_VERSION="7.0.43"                   # quay.io/mongodb/mongodb-community-server:<v>-ubi8
REDIS_IMAGE="redis:8.10.2-alpine"
DB_STORAGE_SIZE="2Gi"                      # per member, local-path
PG_MEMORY="512Mi"
MONGO_MEMORY="512Mi"
REDIS_MEMORY="256Mi"
SENTINEL_MEMORY="64Mi"
DB_WAIT_TIMEOUT="300"                      # seconds, per readiness wait

```

(The Vagrantfile parses `KEY="value"` lines without `$`. These values contain no `$`, so the Vagrantfile is unaffected.)

- [ ] **Step 2: Create `03-databases/lib.sh`**

```bash
#!/bin/bash
# =============================================================================
# 03-databases/lib.sh
# Shared helpers for the 03-databases scripts. Source after vars.sh:
#   source ./vars.sh; source 03-databases/lib.sh
# =============================================================================

export KUBECONFIG="$KUBECONFIG_OUT"
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
            k get pods -o wide >&2 || true
            k get events --sort-by=.lastTimestamp 2>/dev/null | tail -20 >&2 || true
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
```

- [ ] **Step 3: Write the failing test: create `03-databases/db-test.sh`**

```bash
#!/bin/bash
# =============================================================================
# 03-databases/db-test.sh [all|postgres]
# Non-destructive check: write through the primary (using the same Services and
# credentials an app would), then read the value back on every replica.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh

target=${1:-all}
token="borg-$(date +%s)-$RANDOM"
fail=0
ok()  { echo "  PASS  $*"; }
bad() { echo "  FAIL  $*"; fail=1; }

pg_has_token() { [ "$(pg_sql "$1" "SELECT v FROM borg_db_test WHERE id = 1" 2>/dev/null)" = "$token" ]; }

test_postgres() {
    echo ">>> PostgreSQL"
    local primary uri p
    primary=$(pg_primary 2>/dev/null) && [ -n "$primary" ] || { bad "no primary reported"; return; }
    uri=$(secret_value pg-app uri 2>/dev/null) && [ -n "$uri" ] || { bad "secret pg-app missing"; return; }
    # App path: the pg-rw Service with the generated app credentials
    if k exec "$primary" -c postgres -- psql "$uri" -v ON_ERROR_STOP=1 -tAc \
        "CREATE TABLE IF NOT EXISTS borg_db_test (id int PRIMARY KEY, v text);
         INSERT INTO borg_db_test VALUES (1, '$token') ON CONFLICT (id) DO UPDATE SET v = EXCLUDED.v;" >/dev/null; then
        ok "write via pg-rw as app (primary $primary)"
    else
        bad "write via pg-rw as app"; return
    fi
    for p in $(pg_pods); do
        [ "$p" = "$primary" ] && continue
        if retry 15 pg_has_token "$p"; then ok "read on replica $p"; else bad "read on replica $p"; fi
    done
}

case "$target" in
    all)      test_postgres ;;
    postgres) test_postgres ;;
    *) die "usage: $0 [all|postgres]" ;;
esac

if [ "$fail" -eq 0 ]; then
    echo ">>> db-test: all checks passed"
else
    echo ">>> db-test: FAILED" >&2
    exit 1
fi
```

- [ ] **Step 4: Run the test to confirm it fails**

Run: `cd borg-cloud && bash 03-databases/db-test.sh postgres; echo "exit=$?"`
Expected: `FAIL  no primary reported`, `>>> db-test: FAILED`, `exit=1`

- [ ] **Step 5: Create `03-databases/operators.sh`, `03-databases/postgres.yaml`, `03-databases/install-databases.sh`**

`03-databases/operators.sh`:

```bash
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
```

`03-databases/postgres.yaml`:

```yaml
# PostgreSQL: 3-instance CloudNativePG cluster (1 primary + 2 streaming replicas).
# CNPG creates the Services pg-rw / pg-ro / pg-r and the Secret pg-app.
# Rendered by install-databases.sh: ${...} values come from vars.sh.
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg
  namespace: ${DB_NAMESPACE}
spec:
  instances: 3
  imageName: ${PG_IMAGE}
  primaryUpdateStrategy: unsupervised
  bootstrap:
    initdb:
      database: app
      owner: app
  storage:
    storageClass: local-path
    size: ${DB_STORAGE_SIZE}
  resources:
    requests:
      cpu: 100m
      memory: ${PG_MEMORY}
    limits:
      memory: ${PG_MEMORY}
  postgresql:
    parameters:
      shared_buffers: "128MB"
  affinity:
    enablePodAntiAffinity: true
    podAntiAffinityType: required
    topologyKey: kubernetes.io/hostname
```

`03-databases/install-databases.sh`:

```bash
#!/bin/bash
# =============================================================================
# 03-databases/install-databases.sh [all|postgres]
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

target=${1:-all}
case "$target" in
    all|postgres) ;;
    *) die "usage: $0 [all|postgres]" ;;
esac

preflight
ensure_namespace

case "$target" in
    all)      install_postgres ;;
    postgres) install_postgres ;;
esac
echo ">>> Databases ready. Connection info: make db-info"
```

- [ ] **Step 6: Add Makefile variables and targets**

In the variables block, after `KUBECONFIG_OUT := $(call var,KUBECONFIG_OUT)`, add:

```make
DB_NAMESPACE   := $(call var,DB_NAMESPACE)
```

After the `provision-k3s` target, add:

```make
.PHONY: provision-databases
provision-databases:
	@echo ">>> [03/03] Databases (namespace $(DB_NAMESPACE))..."
	bash 03-databases/install-databases.sh all
	@echo ">>> [03/03] Done."

.PHONY: provision-postgres
provision-postgres:
	bash 03-databases/install-databases.sh postgres
```

Change the existing step labels `[01/02]` → `[01/03]` and `[02/02]` → `[02/03]` in `provision-base` and `provision-k3s`.

In the `Convenience` section, after `cluster-status`, add:

```make
.PHONY: db-test
db-test:
	bash 03-databases/db-test.sh
```

- [ ] **Step 7: Check preflight and argument handling (Review Focus 5)**

Run: `cd borg-cloud && PATH=/usr/bin:/bin bash 03-databases/install-databases.sh; echo "exit=$?"`
Expected: `ERROR: kubectl not found on PATH`, `exit=1` (`kubectl` and `helm` live in `/snap/bin`, which is off this PATH). No `databases` namespace is created:
Run: `KUBECONFIG=~/.kube/config-borg kubectl get ns databases 2>&1 | tail -1`
Expected: `Error from server (NotFound): namespaces "databases" not found`

Run: `cd borg-cloud && bash 03-databases/install-databases.sh bogus; echo "exit=$?"`
Expected: `ERROR: usage: .../install-databases.sh [all|postgres]`, `exit=1`

- [ ] **Step 8: Lint**

Run: `cd borg-cloud && shellcheck -S warning -e SC1091 03-databases/*.sh`
Expected: no output, exit 0.

- [ ] **Step 9: Install PostgreSQL**

Run: `cd borg-cloud && make provision-postgres`
Expected: ends with `PostgreSQL (3 ready instances): ready` and `>>> Databases ready.` Takes about 2–4 minutes on the first image pull.

Check the spread across nodes:
Run: `KUBECONFIG=~/.kube/config-borg kubectl -n databases get pods -l cnpg.io/cluster=pg -o wide`
Expected: `pg-1`, `pg-2`, `pg-3` are all `Running 1/1`, each on a different `NODE` (k3s-node1/2/3).

- [ ] **Step 10: Run the test to confirm it passes**

Run: `cd borg-cloud && make db-test`
Expected:
```
>>> PostgreSQL
  PASS  write via pg-rw as app (primary pg-1)
  PASS  read on replica pg-2
  PASS  read on replica pg-3
>>> db-test: all checks passed
```

- [ ] **Step 11: Commit**

```bash
git add borg-cloud/vars.sh borg-cloud/Makefile borg-cloud/03-databases/
git commit -m "borg-cloud: add 03-databases step with PostgreSQL (CNPG, 3 instances)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: MongoDB

**Files:**
- Modify: `03-databases/lib.sh` (append the MongoDB helpers)
- Modify: `03-databases/operators.sh` (append `install_mongodb_operator`)
- Create: `03-databases/mongodb.yaml`
- Modify: `03-databases/install-databases.sh`, `03-databases/db-test.sh` (add `mongo`)
- Modify: `Makefile` (`provision-mongo`)

**Interfaces:**
- Consumes: everything lib.sh produced in Task 1.
- Produces (lib.sh): `mongo_pods`, `mongo_ready`, `mongo_hello <pod>` (prints `<primary-host> <true|false>`), `mongo_primary` (pod name, e.g. `mongo-1`), `mongo_eval <pod> <uri> <js>`, `mongo_uri_for <pod>` (direct connection, app user).
- Produces (operators.sh): `install_mongodb_operator`.
- Facts about the operator (MongoDB Controllers for Kubernetes 1.12.0, `MongoDBCommunity` reconciler): pods are named `mongo-0..2`; the headless Service is `mongo-svc`; the pod label is `app: mongo-svc`; the containers are `mongod` and `mongodb-agent`; the chart creates the ServiceAccount `mongodb-kubernetes-appdb` (get secrets; get/patch/delete pods), which we set explicitly as the pod's ServiceAccount.

- [ ] **Step 1: Append the MongoDB helpers to `03-databases/lib.sh`**

```bash

# ---- MongoDB (MongoDBCommunity "mongo") ----
mongo_pods()  { echo mongo-0 mongo-1 mongo-2; }
mongo_ready() { [ "$(k get mongodbcommunity mongo -o jsonpath='{.status.phase}')" = Running ]; }
# mongo_hello <pod>: prints "<primary host> <isWritablePrimary>" (hello needs no auth)
mongo_hello() {
    k exec "$1" -c mongod -- mongosh --quiet --eval \
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
mongo_eval() { k exec "$1" -c mongod -- mongosh "$2" --quiet --eval "$3"; }
# mongo_uri_for <pod>: direct connection to one member as the app user
mongo_uri_for() {
    echo "mongodb://app:$(secret_value mongo-app-password password)@$1.mongo-svc.$DB_NAMESPACE.svc.cluster.local:27017/media?authSource=admin&directConnection=true&readPreference=secondaryPreferred"
}
```

- [ ] **Step 2: Write the failing test: add MongoDB to `03-databases/db-test.sh`**

Change the header comment's `[all|postgres]` to `[all|postgres|mongo]`. Add after `test_postgres() { ... }`:

```bash
mongo_has_token() {
    [ "$(mongo_eval "$1" "$(mongo_uri_for "$1")" \
        'const d = db.getSiblingDB("media").borg_db_test.findOne({_id: 1}); print(d ? d.v : "")' \
        2>/dev/null)" = "$token" ]
}

test_mongo() {
    echo ">>> MongoDB"
    local primary uri p
    primary=$(mongo_primary 2>/dev/null) || { bad "no primary found"; return; }
    uri=$(secret_value mongo-media-app connectionString.standard 2>/dev/null) && [ -n "$uri" ] \
        || { bad "secret mongo-media-app missing"; return; }
    # App path: the operator's replica-set connection string, majority write concern
    if mongo_eval "$primary" "$uri" \
        "db.getSiblingDB('media').borg_db_test.replaceOne({_id: 1}, {_id: 1, v: '$token'}, {upsert: true, writeConcern: {w: 'majority', wtimeout: 10000}})" >/dev/null; then
        ok "majority write via connection string (primary $primary)"
    else
        bad "majority write via connection string"; return
    fi
    for p in $(mongo_pods); do
        [ "$p" = "$primary" ] && continue
        if retry 15 mongo_has_token "$p"; then ok "read on secondary $p"; else bad "read on secondary $p"; fi
    done
}
```

Replace the `case` block with:

```bash
case "$target" in
    all)      test_postgres; test_mongo ;;
    postgres) test_postgres ;;
    mongo)    test_mongo ;;
    *) die "usage: $0 [all|postgres|mongo]" ;;
esac
```

- [ ] **Step 3: Run the test to confirm it fails**

Run: `cd borg-cloud && bash 03-databases/db-test.sh mongo; echo "exit=$?"`
Expected: `FAIL  no primary found`, `>>> db-test: FAILED`, `exit=1`

- [ ] **Step 4: Append `install_mongodb_operator` to `03-databases/operators.sh`**

```bash

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
```

- [ ] **Step 5: Create `03-databases/mongodb.yaml`**

```yaml
# MongoDB: 3-member replica set (all data-bearing), managed by the MongoDB operator.
# The operator writes the connection-string Secret mongo-media-app.
# Rendered by install-databases.sh: ${...} values come from vars.sh.
apiVersion: mongodbcommunity.mongodb.com/v1
kind: MongoDBCommunity
metadata:
  name: mongo
  namespace: ${DB_NAMESPACE}
spec:
  type: ReplicaSet
  members: 3
  version: "${MONGODB_VERSION}"
  security:
    authentication:
      modes: ["SCRAM"]
  users:
    - name: app
      db: admin
      passwordSecretRef:
        name: mongo-app-password
      roles:
        - name: readWrite
          db: media
      scramCredentialsSecretName: mongo-app
      connectionStringSecretName: mongo-media-app
  additionalMongodConfig:
    storage.wiredTiger.engineConfig.cacheSizeGB: 0.25
  statefulSet:
    spec:
      template:
        spec:
          serviceAccountName: mongodb-kubernetes-appdb
          affinity:
            podAntiAffinity:
              requiredDuringSchedulingIgnoredDuringExecution:
                - topologyKey: kubernetes.io/hostname
                  labelSelector:
                    matchLabels:
                      app: mongo-svc
          containers:
            - name: mongod
              resources:
                requests:
                  cpu: 100m
                  memory: ${MONGO_MEMORY}
                limits:
                  memory: ${MONGO_MEMORY}
            - name: mongodb-agent
              resources:
                requests:
                  cpu: 50m
                  memory: 96Mi
                limits:
                  memory: 192Mi
      volumeClaimTemplates:
        - metadata:
            name: data-volume
          spec:
            storageClassName: local-path
            resources:
              requests:
                storage: ${DB_STORAGE_SIZE}
        - metadata:
            name: logs-volume
          spec:
            storageClassName: local-path
            resources:
              requests:
                storage: 256Mi
```

- [ ] **Step 6: Wire MongoDB into `03-databases/install-databases.sh`**

Change the header comment's `[all|postgres]` to `[all|postgres|mongo]`. Add after `install_postgres() { ... }`:

```bash
install_mongo() {
    echo ">>> MongoDB: operator"
    install_mongodb_operator
    echo ">>> MongoDB: replica set mongo (3 members)"
    ensure_secret mongo-app-password password
    apply_manifest 03-databases/mongodb.yaml
    wait_for "MongoDB (replica set Running)" mongo_ready
}
```

Replace both `case` blocks with:

```bash
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
```

In the `Makefile`, after `provision-postgres`, add:

```make
.PHONY: provision-mongo
provision-mongo:
	bash 03-databases/install-databases.sh mongo
```

- [ ] **Step 7: Lint, then install MongoDB**

Run: `cd borg-cloud && shellcheck -S warning -e SC1091 03-databases/*.sh`
Expected: no output.

Run: `cd borg-cloud && make provision-mongo`
Expected: `secret/mongo-app-password created`, then `MongoDB (replica set Running): ready`. Takes about 3–5 minutes.

Check the spread across nodes and the ServiceAccount:
Run: `KUBECONFIG=~/.kube/config-borg kubectl -n databases get pods -l app=mongo-svc -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,SA:.spec.serviceAccountName,READY:.status.containerStatuses[*].ready`
Expected: `mongo-0..2`, each on a different node, SA `mongodb-kubernetes-appdb`, both containers ready.

If the pods are not labelled `app=mongo-svc` (the command returns nothing), or `mongosh` is missing from the `mongod` container (`kubectl -n databases exec mongo-0 -c mongod -- mongosh --version` fails), STOP and report. Both are assumptions the anti-affinity and the checks rely on.

- [ ] **Step 8: Run the test to confirm it passes**

Run: `cd borg-cloud && make db-test`
Expected: the PostgreSQL checks as before, plus:
```
>>> MongoDB
  PASS  majority write via connection string (primary mongo-0)
  PASS  read on secondary mongo-1
  PASS  read on secondary mongo-2
>>> db-test: all checks passed
```

- [ ] **Step 9: Commit**

```bash
git add borg-cloud/Makefile borg-cloud/03-databases/
git commit -m "borg-cloud: add MongoDB 3-member replica set (MongoDB operator)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Redis + Sentinel

**Files:**
- Modify: `03-databases/lib.sh` (append the Redis helpers)
- Create: `03-databases/redis.yaml`
- Modify: `03-databases/install-databases.sh`, `03-databases/db-test.sh` (add `redis`)
- Modify: `Makefile` (`provision-redis`)

**Interfaces:**
- Consumes: lib.sh from Tasks 1–2.
- Produces (lib.sh): `redis_pods`, `redis_cli <pod> <args...>` (authenticated, in the `redis` container), `sentinel_cli <args...>` (first Sentinel that answers), `redis_primary` (pod name), `redis_ready`.
- Pod layout: StatefulSet `redis`, pods `redis-0..2`, label `app.kubernetes.io/name: redis`, containers `redis` (6379) and `sentinel` (26379), env `REDIS_PASSWORD` from the Secret `redis-auth` key `password`. Per-pod DNS is `redis-N.redis-headless.<ns>.svc.cluster.local`.

- [ ] **Step 1: Append the Redis helpers to `03-databases/lib.sh`**

```bash

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
```

- [ ] **Step 2: Write the failing test: add Redis to `03-databases/db-test.sh`**

Change the header comment to `[all|postgres|mongo|redis]`. Add after `test_mongo() { ... }`:

```bash
redis_has_token() { [ "$(redis_cli "$1" GET borg_db_test 2>/dev/null)" = "$token" ]; }

test_redis() {
    echo ">>> Redis"
    local via_service primary p
    # App path: ask the redis-sentinel Service (not a specific pod) for the primary
    via_service=$(redis_cli redis-0 -h redis-sentinel -p 26379 SENTINEL get-master-addr-by-name mymaster 2>/dev/null | head -1)
    [ -n "$via_service" ] && ok "redis-sentinel Service reports primary ${via_service%%.*}" \
        || { bad "redis-sentinel Service did not answer"; return; }
    primary=${via_service%%.*}
    if [ "$(redis_cli "$primary" SET borg_db_test "$token" 2>/dev/null)" = OK ]; then
        ok "write on primary $primary"
    else
        bad "write on primary $primary"; return
    fi
    for p in $(redis_pods); do
        [ "$p" = "$primary" ] && continue
        if retry 15 redis_has_token "$p"; then ok "read on replica $p"; else bad "read on replica $p"; fi
    done
}
```

Replace the `case` block with:

```bash
case "$target" in
    all)      test_postgres; test_mongo; test_redis ;;
    postgres) test_postgres ;;
    mongo)    test_mongo ;;
    redis)    test_redis ;;
    *) die "usage: $0 [all|postgres|mongo|redis]" ;;
esac
```

- [ ] **Step 3: Run the test to confirm it fails**

Run: `cd borg-cloud && bash 03-databases/db-test.sh redis; echo "exit=$?"`
Expected: `FAIL  redis-sentinel Service did not answer`, `>>> db-test: FAILED`, `exit=1`

- [ ] **Step 4: Create `03-databases/redis.yaml`**

```yaml
# Redis: 3-pod StatefulSet, each pod = redis + Sentinel sidecar.
# 1 primary + 2 replicas; Sentinel (quorum 2) promotes a replica when the primary fails.
# Clients connect Sentinel-aware: redis-sentinel.<ns>:26379, master name "mymaster".
# There is deliberately no "primary" Service: it would point at the wrong pod after failover.
# Rendered by install-databases.sh: only the ${...} values listed in lib.sh
# MANIFEST_VARS are substituted; the shell variables in init.sh are left alone.
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-scripts
  namespace: ${DB_NAMESPACE}
data:
  init.sh: |
    #!/bin/sh
    # Writes /config/redis.conf and /config/sentinel.conf for this pod.
    # Asks the other pods' Sentinels who the primary is. If none answers
    # (first boot of the whole set), redis-0 is the primary. This stops a
    # restarted former primary from coming back as a second primary.
    set -eu
    NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
    SVC="redis-headless.$NS.svc.cluster.local"
    ME="$(hostname).$SVC"
    MASTER=""
    for i in 0 1 2; do
      PEER="redis-$i.$SVC"
      [ "$PEER" = "$ME" ] && continue
      ANSWER=$(timeout 3 redis-cli -h "$PEER" -p 26379 -a "$REDIS_PASSWORD" --no-auth-warning \
        SENTINEL get-master-addr-by-name mymaster 2>/dev/null | head -1) || true
      if [ -n "$ANSWER" ]; then MASTER="$ANSWER"; break; fi
    done
    [ -n "$MASTER" ] || MASTER="redis-0.$SVC"
    echo "init: this pod is $ME; primary is $MASTER"

    cat > /config/redis.conf <<EOF
    port 6379
    dir /data
    appendonly yes
    requirepass $REDIS_PASSWORD
    masterauth $REDIS_PASSWORD
    replica-announce-ip $ME
    EOF
    if [ "$MASTER" != "$ME" ]; then
      echo "replicaof $MASTER 6379" >> /config/redis.conf
    fi

    cat > /config/sentinel.conf <<EOF
    port 26379
    sentinel resolve-hostnames yes
    sentinel announce-hostnames yes
    sentinel announce-ip $ME
    sentinel monitor mymaster $MASTER 6379 2
    sentinel auth-pass mymaster $REDIS_PASSWORD
    sentinel down-after-milliseconds mymaster 5000
    sentinel failover-timeout mymaster 60000
    sentinel parallel-syncs mymaster 1
    requirepass $REDIS_PASSWORD
    sentinel sentinel-pass $REDIS_PASSWORD
    EOF
---
# Per-pod DNS. publishNotReadyAddresses: a starting pod must resolve its own
# name and its peers' names before it is Ready.
apiVersion: v1
kind: Service
metadata:
  name: redis-headless
  namespace: ${DB_NAMESPACE}
spec:
  clusterIP: None
  publishNotReadyAddresses: true
  selector:
    app.kubernetes.io/name: redis
  ports:
    - name: redis
      port: 6379
    - name: sentinel
      port: 26379
---
apiVersion: v1
kind: Service
metadata:
  name: redis-sentinel
  namespace: ${DB_NAMESPACE}
spec:
  selector:
    app.kubernetes.io/name: redis
  ports:
    - name: sentinel
      port: 26379
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: ${DB_NAMESPACE}
spec:
  serviceName: redis-headless
  replicas: 3
  selector:
    matchLabels:
      app.kubernetes.io/name: redis
  template:
    metadata:
      labels:
        app.kubernetes.io/name: redis
    spec:
      # uid 999 = redis in the official image. Sentinel rewrites its own config,
      # so /config (emptyDir) must be writable by this user.
      securityContext:
        runAsNonRoot: true
        runAsUser: 999
        runAsGroup: 1000
        fsGroup: 1000
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - topologyKey: kubernetes.io/hostname
              labelSelector:
                matchLabels:
                  app.kubernetes.io/name: redis
      initContainers:
        - name: config
          image: ${REDIS_IMAGE}
          command: ["sh", "/scripts/init.sh"]
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: redis-auth
                  key: password
          volumeMounts:
            - name: scripts
              mountPath: /scripts
            - name: config
              mountPath: /config
      containers:
        - name: redis
          image: ${REDIS_IMAGE}
          command: ["redis-server", "/config/redis.conf"]
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: redis-auth
                  key: password
          ports:
            - name: redis
              containerPort: 6379
          readinessProbe:
            exec:
              command: ["sh", "-c", "redis-cli -a \"$REDIS_PASSWORD\" --no-auth-warning ping | grep -q PONG"]
            periodSeconds: 5
          resources:
            requests:
              cpu: 50m
              memory: ${REDIS_MEMORY}
            limits:
              memory: ${REDIS_MEMORY}
          volumeMounts:
            - name: data
              mountPath: /data
            - name: config
              mountPath: /config
        - name: sentinel
          image: ${REDIS_IMAGE}
          command: ["redis-server", "/config/sentinel.conf", "--sentinel"]
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: redis-auth
                  key: password
          ports:
            - name: sentinel
              containerPort: 26379
          readinessProbe:
            exec:
              command: ["sh", "-c", "redis-cli -p 26379 -a \"$REDIS_PASSWORD\" --no-auth-warning ping | grep -q PONG"]
            periodSeconds: 5
          resources:
            requests:
              cpu: 20m
              memory: ${SENTINEL_MEMORY}
            limits:
              memory: ${SENTINEL_MEMORY}
          volumeMounts:
            - name: config
              mountPath: /config
      volumes:
        - name: scripts
          configMap:
            name: redis-scripts
        - name: config
          emptyDir: {}
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: local-path
        resources:
          requests:
            storage: ${DB_STORAGE_SIZE}
```

- [ ] **Step 5: Wire Redis into `03-databases/install-databases.sh`, then install**

Change the header comment to `[all|postgres|mongo|redis]`. Add after `install_mongo() { ... }`:

```bash
install_redis() {
    echo ">>> Redis: StatefulSet redis + Sentinel (3 pods)"
    ensure_secret redis-auth password
    apply_manifest 03-databases/redis.yaml
    wait_for "Redis (3 pods, Sentinel sees 2 replicas)" redis_ready
}
```

Replace both `case` blocks with:

```bash
target=${1:-all}
case "$target" in
    all|postgres|mongo|redis) ;;
    *) die "usage: $0 [all|postgres|mongo|redis]" ;;
esac

preflight
ensure_namespace

case "$target" in
    all)      install_postgres; install_mongo; install_redis ;;
    postgres) install_postgres ;;
    mongo)    install_mongo ;;
    redis)    install_redis ;;
esac
```

In the `Makefile`, after `provision-mongo`, add:

```make
.PHONY: provision-redis
provision-redis:
	bash 03-databases/install-databases.sh redis
```

Run: `cd borg-cloud && shellcheck -S warning -e SC1091 03-databases/*.sh`
Expected: no output.

Run: `cd borg-cloud && make provision-redis`
Expected: `secret/redis-auth created`, then `Redis (3 pods, Sentinel sees 2 replicas): ready`.

Run: `KUBECONFIG=~/.kube/config-borg kubectl -n databases logs redis-1 -c config`
Expected: `init: this pod is redis-1.redis-headless.databases.svc.cluster.local; primary is redis-0.redis-headless.databases.svc.cluster.local`

Run: `cd borg-cloud && make db-test`
Expected: the PostgreSQL and MongoDB checks as before, plus:
```
>>> Redis
  PASS  redis-sentinel Service reports primary redis-0
  PASS  write on primary redis-0
  PASS  read on replica redis-1
  PASS  read on replica redis-2
>>> db-test: all checks passed
```

- [ ] **Step 6: Whole-set restart leaves exactly one primary (Review Focus 2)**

Run:
```bash
cd borg-cloud && export KUBECONFIG=~/.kube/config-borg
kubectl -n databases rollout restart statefulset redis
kubectl -n databases rollout status statefulset redis --timeout=300s
source ./vars.sh && source 03-databases/lib.sh
wait_for "Redis after restart" redis_ready
for p in redis-0 redis-1 redis-2; do echo "$p $(redis_cli $p ROLE | head -1)"; done
echo "sentinel: $(redis_primary)"
bash 03-databases/db-test.sh redis
```
Expected: exactly one line says `master` and two say `slave`; `sentinel:` names the same pod as the `master` line; `db-test: all checks passed`.

- [ ] **Step 7: Commit**

```bash
git add borg-cloud/Makefile borg-cloud/03-databases/
git commit -m "borg-cloud: add Redis 3-pod StatefulSet with Sentinel

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `db-status` and `db-info`

**Files:**
- Create: `03-databases/db-status.sh`, `03-databases/db-info.sh`
- Modify: `Makefile`

**Interfaces:**
- Consumes: lib.sh helpers from Tasks 1–3 (`k`, `secret_value`, `mongo_pods`, `mongo_hello`, `redis_pods`, `redis_cli`, `redis_primary`).

- [ ] **Step 1: Write the failing check**

Run: `cd borg-cloud && make db-info 2>&1 | grep -c 'pg-rw.databases.svc.cluster.local:5432'`
Expected: `make: *** No rule to make target 'db-info'` and a count of `0`.

- [ ] **Step 2: Create `03-databases/db-status.sh`**

```bash
#!/bin/bash
# =============================================================================
# 03-databases/db-status.sh
# Members, current primary and role for each database.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh

echo "=== PostgreSQL (CNPG cluster pg) ==="
if k get cluster pg >/dev/null 2>&1; then
    k get cluster pg
    k get pods -l cnpg.io/cluster=pg -L cnpg.io/instanceRole -o wide
else
    echo "  not installed"
fi

echo ""
echo "=== MongoDB (replica set mongo) ==="
if k get mongodbcommunity mongo >/dev/null 2>&1; then
    k get mongodbcommunity mongo
    k get pods -l app=mongo-svc -o wide
    for p in $(mongo_pods); do
        printf '  %s: ' "$p"
        mongo_hello "$p" 2>/dev/null \
            | awk '{print ($2 == "true" ? "PRIMARY" : "secondary") "  (primary: " $1 ")"}' \
            || echo "unreachable"
    done
else
    echo "  not installed"
fi

echo ""
echo "=== Redis + Sentinel (StatefulSet redis) ==="
if k get statefulset redis >/dev/null 2>&1; then
    k get pods -l app.kubernetes.io/name=redis -o wide
    for p in $(redis_pods); do
        printf '  %s: ' "$p"
        redis_cli "$p" ROLE 2>/dev/null | head -1 || echo "unreachable"
    done
    printf '  Sentinel primary: '
    redis_primary || echo "unknown"
else
    echo "  not installed"
fi
```

- [ ] **Step 3: Create `03-databases/db-info.sh`**

```bash
#!/bin/bash
# =============================================================================
# 03-databases/db-info.sh
# In-cluster connection info. Credentials are read from the Secrets in the cluster.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh

D="$DB_NAMESPACE.svc.cluster.local"
echo "In-cluster connection info (namespace $DB_NAMESPACE)"

echo ""
echo "PostgreSQL"
if k get secret pg-app >/dev/null 2>&1; then
    echo "  primary (rw):  pg-rw.$D:5432"
    echo "  replicas (ro): pg-ro.$D:5432"
    echo "  database: app   user: app   password: $(secret_value pg-app password)"
    echo "  uri:      $(secret_value pg-app uri)"
    echo "  secret:   pg-app (keys: username, password, uri, jdbc-uri)"
else
    echo "  not installed"
fi

echo ""
echo "MongoDB"
if k get secret mongo-media-app >/dev/null 2>&1; then
    echo "  uri:      $(secret_value mongo-media-app connectionString.standard)"
    echo "  secret:   mongo-media-app (key: connectionString.standard)"
else
    echo "  not installed"
fi

echo ""
echo "Redis (Sentinel)"
if k get secret redis-auth >/dev/null 2>&1; then
    echo "  sentinels:   redis-sentinel.$D:26379"
    echo "  master name: mymaster"
    echo "  password:    $(secret_value redis-auth password)   (Redis and Sentinel)"
    echo "  secret:      redis-auth (key: password)"
else
    echo "  not installed"
fi
```

- [ ] **Step 4: Add the Makefile targets**

After `db-test` in the Convenience section, add:

```make
.PHONY: db-status
db-status:
	@bash 03-databases/db-status.sh

.PHONY: db-info
db-info:
	@bash 03-databases/db-info.sh
```

- [ ] **Step 5: Lint and run**

Run: `cd borg-cloud && shellcheck -S warning -e SC1091 03-databases/*.sh`
Expected: no output.

Run: `cd borg-cloud && make db-info`
Expected: three sections. The PostgreSQL section shows `pg-rw.databases.svc.cluster.local:5432` and a `postgresql://app:...@pg-rw.databases...:5432/app` URI. MongoDB shows a `mongodb://app:...@mongo-0.mongo-svc...,mongo-1...,mongo-2.../admin?replicaSet=mongo...` URI. Redis shows `redis-sentinel.databases.svc.cluster.local:26379` and `mymaster`. There are no `not installed` lines.

Run: `cd borg-cloud && make db-status`
Expected: 3 pg pods (one `primary` in the `INSTANCEROLE` column), one MongoDB `PRIMARY` and two `secondary`, one Redis `master` and two `slave`, and `Sentinel primary:` matching the Redis `master`.

- [ ] **Step 6: Commit**

```bash
git add borg-cloud/Makefile borg-cloud/03-databases/
git commit -m "borg-cloud: add db-status and db-info targets

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Failover test

**Files:**
- Create: `03-databases/db-failover-test.sh`
- Modify: `Makefile`

**Interfaces:**
- Consumes: `pg_primary`, `pg_ready`, `mongo_primary`, `mongo_hello`, `mongo_ready`, `redis_primary`, `redis_cli`, `redis_ready`, `wait_for`, and `db-test.sh <db>`.

- [ ] **Step 1: Write the failing check**

Run: `cd borg-cloud && make db-failover-test; echo "exit=$?"`
Expected: `No rule to make target 'db-failover-test'`, `exit=2`

- [ ] **Step 2: Create `03-databases/db-failover-test.sh`**

```bash
#!/bin/bash
# =============================================================================
# 03-databases/db-failover-test.sh [all|postgres|mongo|redis]
# DISRUPTIVE: for each database, deletes the primary pod, then checks that
# another member is promoted, writes work again, and the old pod rejoins as
# a replica. Not part of `make up`.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh

# primary_changed <primary-fn> <old-pod>: the function reports a primary other than old
primary_changed() { local now; now=$("$1" 2>/dev/null) && [ -n "$now" ] && [ "$now" != "$2" ]; }

mongo_is_secondary() {
    mongo_hello "$1" 2>/dev/null | awk '$1 != "undefined" && $2 == "false" {ok = 1} END {exit !ok}'
}
redis_is_replica() { [ "$(redis_cli "$1" ROLE 2>/dev/null | head -1)" = slave ]; }

failover_postgres() {
    local old
    old=$(pg_primary)
    echo ">>> PostgreSQL: deleting primary pod $old"
    k delete pod "$old" --wait=false
    wait_for "PostgreSQL new primary (not $old)" primary_changed pg_primary "$old"
    echo "    new primary: $(pg_primary)"
    wait_for "PostgreSQL 3 ready instances ($old rejoined as replica)" pg_ready
    bash 03-databases/db-test.sh postgres
}

failover_mongo() {
    local old
    old=$(mongo_primary)
    echo ">>> MongoDB: deleting primary pod $old"
    k delete pod "$old" --wait=false
    wait_for "MongoDB new primary (not $old)" primary_changed mongo_primary "$old"
    echo "    new primary: $(mongo_primary)"
    wait_for "MongoDB $old rejoined as secondary" mongo_is_secondary "$old"
    wait_for "MongoDB replica set Running" mongo_ready
    bash 03-databases/db-test.sh mongo
}

failover_redis() {
    local old
    old=$(redis_primary)
    echo ">>> Redis: deleting primary pod $old"
    k delete pod "$old" --wait=false
    wait_for "Redis new primary (not $old)" primary_changed redis_primary "$old"
    echo "    new primary: $(redis_primary)"
    wait_for "Redis $old rejoined as replica" redis_is_replica "$old"
    wait_for "Redis (3 pods, Sentinel sees 2 replicas)" redis_ready
    bash 03-databases/db-test.sh redis
}

target=${1:-all}
case "$target" in
    all)      failover_postgres; failover_mongo; failover_redis ;;
    postgres) failover_postgres ;;
    mongo)    failover_mongo ;;
    redis)    failover_redis ;;
    *) die "usage: $0 [all|postgres|mongo|redis]" ;;
esac
echo ">>> db-failover-test: passed"
```

- [ ] **Step 3: Add the Makefile target**

After `db-info`, add:

```make
.PHONY: db-failover-test
db-failover-test:
	@echo "WARNING: This deletes each database's primary pod. Ctrl-C to abort."
	@sleep 3
	bash 03-databases/db-failover-test.sh
```

- [ ] **Step 4: Lint and run**

Run: `cd borg-cloud && shellcheck -S warning -e SC1091 03-databases/*.sh`
Expected: no output.

Run: `cd borg-cloud && make db-failover-test`
Expected, for each database: `deleting primary pod X`, then `new primary: Y` (Y ≠ X), then `rejoined ... ready`, then the database's `db-test` all `PASS`. It ends with `>>> db-failover-test: passed`. Takes about 3–6 minutes.

If Redis reports no new primary because the pod came back before Sentinel's 5-second down-after window, rerun `bash 03-databases/db-failover-test.sh redis` once. If it fails a second time, STOP and report the output and `kubectl -n databases logs <pod> -c sentinel --tail=50`.

- [ ] **Step 5: Commit**

```bash
git add borg-cloud/Makefile borg-cloud/03-databases/db-failover-test.sh
git commit -m "borg-cloud: add db-failover-test target

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Uninstall, idempotency, `make up`, help

**Files:**
- Create: `03-databases/uninstall-databases.sh`
- Modify: `Makefile` (`db-uninstall`, `up`, `help`, header comment)

**Interfaces:**
- Consumes: `k`, `render`, the Secret and resource names from Tasks 1–3, and the helm release names `cnpg` (in `cnpg-system`) and `mongodb-kubernetes` (in `databases`).

- [ ] **Step 1: Write the failing check**

Run: `cd borg-cloud && make -n up | grep -c install-databases.sh`
Expected: `0` (`up` does not yet include the databases).

- [ ] **Step 2: Wire `make up` and help**

Change `up: vagrant-up cluster` to:

```make
up: vagrant-up cluster provision-databases
```

Change the header comment's first line to `# Makefile — BorgCloud 3-node k3s cluster + data tier lifecycle (VirtualBox + Vagrant)`.

In `help`, replace these two lines:

```make
	@echo "  make up                  Everything: vagrant-up + cluster"
```
```make
	@echo "  make cluster             2. Base OS prep + k3s HA install + kubeconfig"
```

with:

```make
	@echo "  make up                  Everything: vagrant-up + cluster + databases"
```
```make
	@echo "  make cluster             2. Base OS prep + k3s HA install + kubeconfig"
	@echo "  make provision-databases 3. Postgres + MongoDB + Redis (3 members each)"
```

And, before the `@echo "  Convenience:"` line, insert:

```make
	@echo "  Databases (namespace $(DB_NAMESPACE), one member per node):"
	@echo "  make provision-databases 03: operators + Postgres, MongoDB, Redis"
	@echo "  make provision-postgres  One database (also: provision-mongo, provision-redis)"
	@echo "  make db-status           Members, primaries and roles"
	@echo "  make db-info             In-cluster connection strings + credentials"
	@echo "  make db-test             Write on primary, read on every replica"
	@echo "  make db-failover-test    Delete each primary, verify promotion (disruptive)"
	@echo "  make db-uninstall        Delete databases, their data and operators"
	@echo ""
```

Run: `cd borg-cloud && make -n up | grep -c install-databases.sh && make help | grep -c 'db-'`
Expected: `1`, then `6` or more.

- [ ] **Step 3: Re-running provisioning changes nothing (Review Focus 1)**

Run:
```bash
cd borg-cloud && export KUBECONFIG=~/.kube/config-borg
# Secret contents as short hashes (never the values), and pod UIDs
snap() {
    kubectl -n databases get secrets -o json \
        | jq -r '.items[] | [.metadata.name, (.data | tostring)] | @tsv' \
        | while IFS=$'\t' read -r name data; do
              echo "secret/$name=$(printf '%s' "$data" | sha256sum | cut -c1-12)"
          done
    kubectl -n databases get pods -o jsonpath='{range .items[*]}pod/{.metadata.name}={.metadata.uid}{"\n"}{end}'
}
tmp=$(mktemp -d)
snap | sort > "$tmp/before"
make provision-databases
snap | sort > "$tmp/after"
diff "$tmp/before" "$tmp/after" && echo "IDEMPOTENT"
rm -rf "$tmp"
```
Expected: `secret/... exists (kept)` for `mongo-app-password` and `redis-auth`, all three waits `ready`, and `IDEMPOTENT`: no Secret's contents changed and no pod was recreated. Any difference is a failure. Report it rather than weakening the check.

- [ ] **Step 4: Create `03-databases/uninstall-databases.sh` and the target**

```bash
#!/bin/bash
# =============================================================================
# 03-databases/uninstall-databases.sh
# Removes the databases, their data (PVCs) and Secrets, then the operators.
# Safe on a partial install or when nothing is installed.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh

has_crd() { kubectl get crd "$1" >/dev/null 2>&1; }

echo ">>> Deleting database resources..."
if has_crd clusters.postgresql.cnpg.io; then
    k delete cluster pg --ignore-not-found --wait=true
fi
if has_crd mongodbcommunity.mongodbcommunity.mongodb.com; then
    k delete mongodbcommunity mongo --ignore-not-found --wait=true
fi
render 03-databases/redis.yaml | kubectl delete --ignore-not-found -f - 2>/dev/null || true

echo ">>> Removing MongoDB operator..."
helm uninstall mongodb-kubernetes -n "$DB_NAMESPACE" --wait 2>/dev/null || echo "    (not installed)"

echo ">>> Deleting namespace $DB_NAMESPACE (PVCs, Secrets)..."
kubectl delete namespace "$DB_NAMESPACE" --ignore-not-found --wait=true

echo ">>> Removing CloudNativePG operator..."
helm uninstall cnpg -n "$CNPG_NAMESPACE" --wait 2>/dev/null || echo "    (not installed)"
kubectl delete namespace "$CNPG_NAMESPACE" --ignore-not-found --wait=true

echo ">>> Done. Operator CRDs may remain (their charts keep them); a reinstall reuses them."
```

In the `Makefile`, after `db-failover-test`, add:

```make
.PHONY: db-uninstall
db-uninstall:
	@echo "WARNING: This deletes all databases and their data in namespace $(DB_NAMESPACE). Ctrl-C to abort."
	@sleep 3
	bash 03-databases/uninstall-databases.sh
```

Run: `cd borg-cloud && shellcheck -S warning -e SC1091 03-databases/*.sh`
Expected: no output.

- [ ] **Step 5: Uninstall, uninstall again, reinstall (Review Focus 4)**

Run: `cd borg-cloud && make db-uninstall`
Expected: ends with `>>> Done.`; `kubectl get ns databases cnpg-system` reports NotFound for both; `kubectl get pv | grep -c databases/` prints `0`.

Run: `cd borg-cloud && make db-uninstall; echo "exit=$?"`
Expected: both operators `(not installed)`, `>>> Done.`, `exit=0`.

Run: `cd borg-cloud && make provision-databases && make db-test`
Expected: all three Secrets are `created` (new credentials), every wait is `ready`, and `db-test: all checks passed`.

- [ ] **Step 6: Commit**

```bash
git add borg-cloud/Makefile borg-cloud/03-databases/uninstall-databases.sh
git commit -m "borg-cloud: add db-uninstall, include databases in make up, document targets

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Acceptance run and PR

**Files:** none (verification and PR only).

- [ ] **Step 1: Full check on the live cluster**

Run:
```bash
cd borg-cloud
make db-status
make db-test
make db-failover-test
make db-test
```
Expected: every check `PASS`; `db-failover-test: passed`.

- [ ] **Step 2: Resource check**

Run: `KUBECONFIG=~/.kube/config-borg kubectl top nodes`
Expected: each node's memory stays below about 80%. Record the numbers for the PR.

- [ ] **Step 3: Ask about a full rebuild**

Ask the user whether to run `make vagrant-destroy && make up` (it destroys the current VMs and takes about 20 minutes). Run it only on an explicit yes. If they say yes, then afterwards run `make db-test` and expect all checks to pass.

- [ ] **Step 4: Push and open the PR**

```bash
git push -u origin borg-cloud-databases
gh pr create --base main --head borg-cloud-databases \
  --title "BorgCloud: Redis, MongoDB and PostgreSQL, 3 members each" \
  --body "Closes #6. Part of #1.

Adds step 03-databases to borg-cloud: PostgreSQL (CloudNativePG), MongoDB (MongoDB operator, MongoDBCommunity) and Redis + Sentinel, 3 members each with one per node, in namespace databases. make up now includes it.

Design: docs/superpowers/specs/2026-09-25-borg-cloud-databases-design.md
Plan: docs/superpowers/plans/2026-09-25-borg-cloud-databases.md

## Targets
provision-databases, provision-postgres/mongo/redis, db-status, db-info, db-test, db-failover-test, db-uninstall

## Testing (live BorgCloud cluster)
- <fill in: provision from nothing, re-run idempotency, db-test, db-failover-test, uninstall/reinstall, Redis rollout restart, kubectl top nodes numbers, whether a full rebuild was run>

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

Before running, replace the `<fill in ...>` line with the actual results from Tasks 1–7. Do not merge the PR: the user merges.
