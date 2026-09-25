# Deploy media-service to BorgCloud Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `make deploy-media` builds media-service from the checkout, pushes it to a registry inside BorgCloud and deploys it with Helm, reachable at `http://<node IP>/api/media` and backed by the cluster's MongoDB.

**Architecture:** A new step `borg-cloud/04-registry` runs `registry:3.1.2` in k3s. The host pushes through a temporary `kubectl port-forward` to `localhost:5050`, and each node's k3s `registries.yaml` mirrors `localhost:5050` to the registry's NodePort. A new step `borg-cloud/05-media` writes the MongoDB Secret, opens the port-forward and runs the existing `media-service/build.sh` with BorgCloud values. Checks run from the host against the live cluster.

**Tech Stack:** bash, GNU make, kubectl 1.36, helm 4, Docker 29, Maven 3.8 + JDK 17, k3s (containerd, Traefik, local-path), Distribution `registry:3.1.2`, Spring Boot 2.7.

**Spec:** `docs/superpowers/specs/2026-09-25-deploy-media-borg-design.md`

## Global Constraints

- Branch `deploy-media-borg`. Paths in **Files:** blocks are relative to the repository root. `Run:` commands say where they run. `git` commands run from the repository root.
- Live cluster: `~/.kube/config-borg`. **Never run `make vagrant-destroy`.** Never call `DELETE /api/media` (it deletes every record).
- Namespaces: `registry` (`REGISTRY_NAMESPACE`) and `media` (`MEDIA_NAMESPACE`). Helm release `media-service` (`MEDIA_RELEASE`).
- Registry: image `registry:3.1.2`, 1 replica, strategy `Recreate`, a `10Gi` `local-path` PVC at `/var/lib/registry`, ClusterIP Service `registry:5000`, NodePort Service `registry-nodeport` 5000 → `30500`.
- Host push port: `REGISTRY_LOCAL_PORT="5050"`; image names are `localhost:5050/<name>`. Port 5000 on this host is raq-base's `raq-registry`; never push to it.
- Node mirror file `/etc/rancher/k3s/registries.yaml`: `"localhost:5050"` → `http://<that node's IP>:30500`. k3s is restarted only on nodes whose file changed, one node at a time.
- The media-service image is `localhost:5050/media3:<tag>`. Chart values file: `charts/media-service/values-borg.yaml`.
- The MongoDB Secret `media-service-mongodb` in `media`, key `SPRING_DATA_MONGODB_URI`, holds the `mongo_app_uri` value (database `media`). It is passed through stdin only.
- Ingress: className `traefik`, no host, path `/api/media` Prefix. URL `http://192.168.56.121/api/media` (any node IP).
- Dockerfile base image: `eclipse-temurin:17-jre`.
- Do not stage or modify the user's uncommitted files: `.gitignore`, `.idea/workspace.xml`, `README`, `media-service/src/main/java/com/sparkle/mediaservice/service/GcsSignUrl.java`, `media-service/src/main/resources/application.properties`. Stage by explicit path only.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Review Focus

1. **Redeploying from a working tree with uncommitted changes.** Each `make deploy-media` must run the image it just built. Today `build.sh` tags every such build `<sha>-dirty`, so a second deploy reuses the same tag, Helm sees no change and the old image keeps running. Pinned in Task 2 (unique dirty tag) and Task 3, Step 8.
2. **Host port 5050 already taken** (another port-forward, another registry). The push must refuse with a clear message rather than push to whatever answers on that port, and no stray port-forward may be left running after a deploy. Pinned in Task 1, Step 8 and Task 3, Step 9.
3. **Registry missing or not Available when deploying.** `deploy-media` must stop before building, and name `make provision-registry`. Pinned in Task 3, Step 9.
4. **MongoDB credentials change** (e.g. `make db-uninstall` + `provision-databases`). The next `make deploy-media`, even with `SKIP_BUILD=1` and the same tag, must restart the pods with the new URI. A Secret change alone does not restart pods, so the pod template carries the URI's hash. Pinned in Task 3, Step 8.
5. **Re-running `make provision-registry` on a configured cluster.** It must not restart k3s anywhere. Pinned in Task 1, Step 7.

---

## File Structure

| File | Responsibility |
|---|---|
| `borg-cloud/vars.sh` (modify) | Registry and media settings |
| `borg-cloud/03-databases/lib.sh` (modify) | `wait_for` diagnostics use `WAIT_NAMESPACE` (default `DB_NAMESPACE`) |
| `borg-cloud/04-registry/registry-lib.sh` (create) | `kr`, `render_registry`, `registry_ready`, `start_registry_forward`, `stop_registry_forward` |
| `borg-cloud/04-registry/registry.yaml` (create) | Namespace, PVC, Deployment, two Services |
| `borg-cloud/04-registry/registries.yaml` (create) | Per-node k3s mirror template |
| `borg-cloud/04-registry/install-registry.sh` (create) | Apply the registry; roll out the node config |
| `borg-cloud/04-registry/registry-test.sh` (create) | Push a test image, then pull it on each node |
| `media-service/Dockerfile` (modify) | Base image `eclipse-temurin:17-jre` |
| `media-service/build.sh` (modify) | Unique dirty tags; `HELM_EXTRA_ARGS` passthrough |
| `charts/media-service/values-borg.yaml` (create) | BorgCloud chart values |
| `borg-cloud/05-media/deploy-media.sh` (create) | Secret, port-forward, build.sh |
| `borg-cloud/05-media/media-test.sh` (create) | HTTP checks through Traefik |
| `borg-cloud/Makefile` (modify) | Targets, `up`, help |

---

### Task 1: In-cluster registry and node mirrors

**Files:**
- Modify: `borg-cloud/vars.sh` (insert before `# --- Derived lists`), `borg-cloud/03-databases/lib.sh` (`wait_for`), `borg-cloud/Makefile`
- Create: `borg-cloud/04-registry/registry-lib.sh`, `borg-cloud/04-registry/registry.yaml`, `borg-cloud/04-registry/registries.yaml`, `borg-cloud/04-registry/install-registry.sh`, `borg-cloud/04-registry/registry-test.sh`

**Interfaces:**
- Consumes (from `03-databases/lib.sh`): `die`, `retry <tries> <cmd...>`, `wait_for <desc> <cmd...>`, `preflight`; (from `vars.sh`): `NODE{1,2,3}_{NAME,IP}`, `ssh_node <ip> <cmd>`.
- Produces (`04-registry/registry-lib.sh`, used by Task 3): `kr <kubectl args>` (in the `registry` namespace), `render_registry <file>`, `registry_ready` (0 when Deployment `registry` has 1 available replica), `start_registry_forward` (sets `REGISTRY_FORWARD_PID`; dies if `REGISTRY_LOCAL_PORT` is taken or the forward doesn't answer), `stop_registry_forward` (always returns 0).
- Produces (`03-databases/lib.sh`): `wait_for` prints pods and events from `${WAIT_NAMESPACE:-$DB_NAMESPACE}`.

- [ ] **Step 1: Add settings to `borg-cloud/vars.sh`**

Insert directly above `# --- Derived lists (space-separated for loops) ---`:

```bash
# --- Image registry (04-registry) ---
REGISTRY_NAMESPACE="registry"
REGISTRY_IMAGE="registry:3.1.2"
REGISTRY_NODEPORT="30500"
# Host side of the push port-forward; images are named localhost:<port>/<name>.
# Port 5000 on this host is raq-base's registry. Changing this needs
# make provision-registry (it is each node's mirror key).
REGISTRY_LOCAL_PORT="5050"
REGISTRY_STORAGE_SIZE="10Gi"

# --- media-service (05-media) ---
MEDIA_NAMESPACE="media"
MEDIA_RELEASE="media-service"

```

- [ ] **Step 2: Make `wait_for` diagnostics namespace-aware**

In `borg-cloud/03-databases/lib.sh`, inside `wait_for`, replace:

```bash
            k get pods -o wide >&2 || true
            k get events --sort-by=.lastTimestamp 2>/dev/null | tail -20 >&2 || true
```

with:

```bash
            kubectl -n "${WAIT_NAMESPACE:-$DB_NAMESPACE}" get pods -o wide >&2 || true
            kubectl -n "${WAIT_NAMESPACE:-$DB_NAMESPACE}" get events --sort-by=.lastTimestamp 2>/dev/null \
                | tail -20 >&2 || true
```

- [ ] **Step 3: Create `borg-cloud/04-registry/registry-lib.sh`**

```bash
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
    kr port-forward svc/registry "$REGISTRY_LOCAL_PORT:5000" >/dev/null 2>&1 &
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
```

- [ ] **Step 4: Write the failing test: create `borg-cloud/04-registry/registry-test.sh`**

```bash
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
```

Add to `borg-cloud/Makefile` in the variables block, after `DB_NAMESPACE   := $(call var,DB_NAMESPACE)`:

```make
REGISTRY_NAMESPACE := $(call var,REGISTRY_NAMESPACE)
```

and at the end of the file:

```make

.PHONY: registry-test
registry-test:
	bash 04-registry/registry-test.sh
```

Run: `cd borg-cloud && make registry-test; echo "exit=$?"`
Expected: `ERROR: registry is not installed or not Available (run: make provision-registry)`, non-zero exit.

- [ ] **Step 5: Create the registry manifest, the node template and `install-registry.sh`**

`borg-cloud/04-registry/registry.yaml`:

```yaml
# In-cluster image registry for BorgCloud. Pushed to through a port-forward
# (localhost:${REGISTRY_LOCAL_PORT}); nodes pull through NodePort ${REGISTRY_NODEPORT}.
# No auth or TLS: reachable only on the host-only network.
# Rendered by install-registry.sh (render_registry).
apiVersion: v1
kind: Namespace
metadata:
  name: ${REGISTRY_NAMESPACE}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: registry-data
  namespace: ${REGISTRY_NAMESPACE}
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: local-path
  resources:
    requests:
      storage: ${REGISTRY_STORAGE_SIZE}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: registry
  namespace: ${REGISTRY_NAMESPACE}
spec:
  replicas: 1
  strategy:
    type: Recreate          # the volume is ReadWriteOnce
  selector:
    matchLabels:
      app.kubernetes.io/name: registry
  template:
    metadata:
      labels:
        app.kubernetes.io/name: registry
    spec:
      containers:
        - name: registry
          image: ${REGISTRY_IMAGE}
          ports:
            - name: http
              containerPort: 5000
          readinessProbe:
            httpGet:
              path: /v2/
              port: http
            periodSeconds: 5
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              memory: 256Mi
          volumeMounts:
            - name: data
              mountPath: /var/lib/registry
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: registry-data
---
apiVersion: v1
kind: Service
metadata:
  name: registry
  namespace: ${REGISTRY_NAMESPACE}
spec:
  selector:
    app.kubernetes.io/name: registry
  ports:
    - name: http
      port: 5000
      targetPort: http
---
apiVersion: v1
kind: Service
metadata:
  name: registry-nodeport
  namespace: ${REGISTRY_NAMESPACE}
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: registry
  ports:
    - name: http
      port: 5000
      targetPort: http
      nodePort: ${REGISTRY_NODEPORT}
```

`borg-cloud/04-registry/registries.yaml`:

```yaml
# /etc/rancher/k3s/registries.yaml (written by install-registry.sh, one per node).
# Images named localhost:${REGISTRY_LOCAL_PORT}/... are pulled from the in-cluster
# registry through this node's NodePort.
mirrors:
  "localhost:${REGISTRY_LOCAL_PORT}":
    endpoint:
      - "http://${NODE_IP}:${REGISTRY_NODEPORT}"
```

`borg-cloud/04-registry/install-registry.sh`:

```bash
#!/bin/bash
# =============================================================================
# 04-registry/install-registry.sh
# Runs from HOST. Installs the in-cluster registry, then points each node's k3s
# at it (/etc/rancher/k3s/registries.yaml). k3s is restarted only on nodes whose
# file changed, one node at a time, waiting for each to be back before the next.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh
source 04-registry/registry-lib.sh

preflight

echo ">>> Registry: $REGISTRY_IMAGE in namespace $REGISTRY_NAMESPACE"
render_registry 04-registry/registry.yaml | kubectl apply -f -
WAIT_NAMESPACE=$REGISTRY_NAMESPACE wait_for "registry Available" registry_ready

# node_back <name> <ip>: that node's own API server is ready and the node is Ready
node_back() {
    ssh_node "$2" 'sudo k3s kubectl get --raw=/readyz' 2>/dev/null | grep -qx ok &&
    kubectl get node "$1" --no-headers 2>/dev/null | awk '$2 == "Ready" {ok = 1} END {exit !ok}'
}

echo ">>> Node mirrors: localhost:$REGISTRY_LOCAL_PORT -> <node IP>:$REGISTRY_NODEPORT"
for i in 1 2 3; do
    name_var="NODE${i}_NAME"; ip_var="NODE${i}_IP"
    name=${!name_var}; ip=${!ip_var}
    export NODE_IP=$ip
    want=$(render_registry 04-registry/registries.yaml)
    have=$(ssh_node "$ip" 'sudo cat /etc/rancher/k3s/registries.yaml 2>/dev/null' || true)
    if [ "$want" = "$have" ]; then
        echo "    $name: up to date"
        continue
    fi
    echo "    $name: writing registries.yaml, restarting k3s"
    printf '%s\n' "$want" | ssh_node "$ip" 'sudo tee /etc/rancher/k3s/registries.yaml >/dev/null'
    ssh_node "$ip" 'sudo systemctl restart k3s'
    WAIT_NAMESPACE=kube-system wait_for "$name back after k3s restart" node_back "$name" "$ip"
done
echo ">>> Registry ready. Test it: make registry-test"
```

In `borg-cloud/Makefile`, after the `provision-redis` target, add:

```make
.PHONY: provision-registry
provision-registry:
	@echo ">>> [04/04] Image registry (namespace $(REGISTRY_NAMESPACE))..."
	bash 04-registry/install-registry.sh
	@echo ">>> [04/04] Done."
```

Rename the step labels `[01/03]` → `[01/04]`, `[02/03]` → `[02/04]`, `[03/03]` → `[03/04]`. Change `up: vagrant-up cluster provision-databases` to `up: vagrant-up cluster provision-databases provision-registry`.

In `help`, change `Everything: vagrant-up + cluster + databases` to `Everything: vagrant-up + cluster + databases + registry`. After the line `make provision-databases 3. Postgres + MongoDB + Redis (3 members each)`, add:

```make
	@echo "  make provision-registry  4. In-cluster image registry + node mirrors"
```

Before `@echo "  Convenience:"`, insert:

```make
	@echo "  Registry (namespace $(REGISTRY_NAMESPACE)):"
	@echo "  make provision-registry  04: registry + node mirrors (restarts k3s only if needed)"
	@echo "  make registry-test       Push a test image, pull it on every node"
	@echo ""
```

Run: `cd borg-cloud && shellcheck -S warning -e SC1091 03-databases/*.sh 04-registry/*.sh`
Expected: no output.

- [ ] **Step 6: Install and run the test**

Run: `cd borg-cloud && make provision-registry`
Expected: `registry Available: ready`, then each of the 3 nodes shows `writing registries.yaml, restarting k3s` followed by `k3s-nodeN back after k3s restart: ready`. About 1–2 minutes per node.

Run: `KUBECONFIG=~/.kube/config-borg kubectl get nodes && cd borg-cloud && make db-test`
Expected: 3 nodes `Ready`; `db-test: all checks passed` (the data tier survived the rolling k3s restarts).

Run: `cd borg-cloud && make registry-test`
Expected:
```
  PASS  push localhost:5050/borg-registry-test:<ts>
  PASS  pull on k3s-node1
  PASS  pull on k3s-node2
  PASS  pull on k3s-node3
>>> registry-test: all checks passed
```

- [ ] **Step 7: Re-running changes nothing (Review Focus 5)**

Run: `cd borg-cloud && make provision-registry 2>&1 | grep -E 'up to date|restarting'`
Expected: exactly three lines `k3s-nodeN: up to date`, and no `restarting`.

- [ ] **Step 8: Taken host port is refused (Review Focus 2)**

Run:
```bash
cd borg-cloud
python3 -m http.server 5050 >/dev/null 2>&1 & blocker=$!
sleep 1
make registry-test; echo "exit=$?"
kill $blocker
pgrep -af 'port-forward svc/registry' || echo "no port-forward left"
```
Expected: `ERROR: port 5050 is already in use on this host (REGISTRY_LOCAL_PORT in vars.sh)`, a non-zero exit, and `no port-forward left`.

- [ ] **Step 9: Commit**

```bash
git add borg-cloud/vars.sh borg-cloud/Makefile borg-cloud/03-databases/lib.sh borg-cloud/04-registry/
git commit -m "borg-cloud: add in-cluster image registry with node mirrors (step 04)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Buildable image and unique dirty tags

**Files:**
- Modify: `media-service/Dockerfile`, `media-service/build.sh`

**Interfaces:**
- Produces (`build.sh`, used by Task 3): env inputs `IMAGE`, `TAG`, `NAMESPACE`, `RELEASE`, `VALUES`, `SKIP_BUILD` (unchanged) plus `HELM_EXTRA_ARGS` (extra words appended to `helm upgrade --install`). Default `TAG` is `<short sha>` for a clean `media-service/` tree, or `<short sha>-dirty-<YYYYmmddHHMMSS>` otherwise.

- [ ] **Step 1: Run the failing build**

Run: `cd media-service && mvn -q clean package -DskipTests=true && docker build -q -t media3-buildtest . ; echo "exit=$?"`
Expected: the Docker build fails because `openjdk:20-slim-buster` is not found; non-zero exit.

- [ ] **Step 2: Fix the base image**

In `media-service/Dockerfile`, replace the line `FROM openjdk:20-slim-buster` with:

```dockerfile
# openjdk images were withdrawn from Docker Hub; Temurin 17 is the maintained
# LTS JRE and matches the JDK the jar is built with (Spring Boot 2.7 supports 17).
FROM eclipse-temurin:17-jre
```

Run: `cd media-service && docker build -q -t media3-buildtest . && docker run --rm --entrypoint java media3-buildtest -version 2>&1 | head -1; docker rmi -f media3-buildtest >/dev/null`
Expected: the build succeeds, printing `openjdk version "17.…"`.

- [ ] **Step 3: Unique dirty tags and `HELM_EXTRA_ARGS` in `build.sh`**

In `media-service/build.sh`, replace:

```bash
TAG=${TAG:-$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- . || echo "-dirty")}
```

with:

```bash
# A build of uncommitted changes gets a unique tag, so every deploy of such a
# build changes the image and rolls the pods.
TAG=${TAG:-$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- . || echo "-dirty-$(date +%Y%m%d%H%M%S)")}
```

Replace:

```bash
helm upgrade --install "$RELEASE" "$CHART" \
    --namespace "$NAMESPACE" --create-namespace \
    -f "$VALUES" \
    --set image.tag="$TAG" \
    --wait --timeout 5m
```

with:

```bash
# HELM_EXTRA_ARGS: extra helm words from a wrapper, e.g. deploy-media.sh.
# shellcheck disable=SC2086
helm upgrade --install "$RELEASE" "$CHART" \
    --namespace "$NAMESPACE" --create-namespace \
    -f "$VALUES" \
    --set image.tag="$TAG" \
    ${HELM_EXTRA_ARGS:-} \
    --wait --timeout 5m
```

In the header comment, after the `SKIP_BUILD=1 TAG=abc1234 ./build.sh` example line, add:

```bash
#   (BorgCloud: use `make deploy-media` in borg-cloud/, which wraps this script)
```

Run: `cd media-service && shellcheck -S warning build.sh && bash -n build.sh && echo ok`
Expected: `ok`.

- [ ] **Step 4: Commit**

```bash
git add media-service/Dockerfile media-service/build.sh
git commit -m "media-service: build on eclipse-temurin:17-jre; unique tags for dirty builds

openjdk:20-slim-buster no longer exists on Docker Hub, so builds failed.
Builds of uncommitted changes now get a timestamped -dirty tag so each
deploy rolls out the new image. build.sh accepts HELM_EXTRA_ARGS.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Deploy media-service

**Files:**
- Create: `charts/media-service/values-borg.yaml`, `borg-cloud/05-media/deploy-media.sh`, `borg-cloud/05-media/media-test.sh`
- Modify: `borg-cloud/Makefile`

**Interfaces:**
- Consumes: `registry_ready`, `start_registry_forward`, `stop_registry_forward` (Task 1); `build.sh` env inputs incl. `HELM_EXTRA_ARGS` (Task 2); from `03-databases/lib.sh`: `preflight`, `die`, `k`, `mongo_app_uri`, `mongo_primary`, `mongo_eval`, `retry`.
- Produces: `make deploy-media [TAG=<tag> SKIP_BUILD=1]`, `make media-test`, `make media-status`. Pod template annotation `borg/mongo-uri-sha` = first 16 hex chars of `sha256(uri)`.

- [ ] **Step 1: Write the failing test: create `borg-cloud/05-media/media-test.sh`**

```bash
#!/bin/bash
# =============================================================================
# 05-media/media-test.sh
# HTTP checks against media-service through Traefik on every node. Never calls
# DELETE /api/media (it deletes every record): the test record is removed
# directly in MongoDB afterwards.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh

fail=0
ok()  { echo "  PASS  $*"; }
bad() { echo "  FAIL  $*"; fail=1; }

token="borg-media-test-$(date +%s)-$RANDOM"
body=$(mktemp)
cleanup() {
    local p
    rm -f "$body"
    p=$(mongo_primary 2>/dev/null) || return 0
    mongo_eval "$p" "$(mongo_app_uri)" "db.media.deleteMany({title: '$token'})" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for ip in $ALL_IPS; do
    code=$(curl -s -m 10 -o "$body" -w '%{http_code}' "http://$ip/api/media" || true)
    if [ "$code" = 200 ] && head -c1 "$body" | grep -q '\['; then
        ok "GET http://$ip/api/media -> 200 (JSON array)"
    else
        bad "GET http://$ip/api/media -> $code"
    fi
done

code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
    -d "{\"title\":\"$token\",\"artist\":\"borg-media-test\"}" "http://$NODE1_IP/api/media" || true)
if [ "$code" = 201 ]; then ok "POST via $NODE1_IP -> 201"; else bad "POST via $NODE1_IP -> $code"; fi

if curl -s -m 10 "http://$NODE2_IP/api/media/$token" | grep -q "\"title\":\"$token\""; then
    ok "GET via $NODE2_IP returns the record (stored in MongoDB)"
else
    bad "GET via $NODE2_IP did not return the record"
fi

if [ "$fail" -eq 0 ]; then
    echo ">>> media-test: all checks passed"
else
    echo ">>> media-test: FAILED" >&2
    exit 1
fi
```

In `borg-cloud/Makefile`, add to the variables block after `REGISTRY_NAMESPACE := ...`:

```make
MEDIA_NAMESPACE := $(call var,MEDIA_NAMESPACE)
```

and at the end of the file:

```make

.PHONY: media-test
media-test:
	bash 05-media/media-test.sh
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `cd borg-cloud && make media-test; echo "exit=$?"`
Expected: three `FAIL  GET http://192.168.56.12N/api/media -> 404` lines (Traefik has no route yet), `FAIL  POST ... -> 404`, `FAIL  GET via ... did not return the record`, `>>> media-test: FAILED`, non-zero exit.

- [ ] **Step 3: Create `charts/media-service/values-borg.yaml`**

```yaml
# =============================================================================
# BorgCloud (k3s on VirtualBox). Deployed by `make deploy-media` in borg-cloud/.
#   - image from the in-cluster registry (localhost:5050, mirrored on each node)
#   - MongoDB: the cluster's replica set (make provision-databases), database
#     media; deploy-media.sh writes the Secret media-service-mongodb
#   - Traefik (k3s built-in): http://<any node IP>/api/media
# =============================================================================
image:
  repository: localhost:5050/media3

mongodb:
  enabled: false

externalMongodb:
  existingSecret: media-service-mongodb

ingress:
  enabled: true
  className: traefik
  hosts:
    - host: ""
      paths:
        - path: /api/media
          pathType: Prefix
```

Run: `cd /home/cfrank/git/media-stream && helm lint --strict charts/media-service -f charts/media-service/values-borg.yaml && helm template t charts/media-service -f charts/media-service/values-borg.yaml --set image.tag=x | grep -E 'image:|ingressClassName|path: /api/media|name: media-service-mongodb'`
Expected: lint passes; the output shows `image: "localhost:5050/media3:x"` (or unquoted), `ingressClassName: traefik`, `path: /api/media`, `name: media-service-mongodb`, and no MongoDB StatefulSet.

- [ ] **Step 4: Create `borg-cloud/05-media/deploy-media.sh`**

```bash
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
```

In `borg-cloud/Makefile`, after the `provision-registry` target, add:

```make
# TAG=<tag> SKIP_BUILD=1 redeploys an image already in the registry
.PHONY: deploy-media
deploy-media:
	TAG="$(TAG)" SKIP_BUILD="$(SKIP_BUILD)" bash 05-media/deploy-media.sh

.PHONY: media-status
media-status:
	$(KUBECTL) -n $(MEDIA_NAMESPACE) get pods,ingress -o wide
	@$(KUBECTL) -n $(MEDIA_NAMESPACE) get deployment \
		-o jsonpath='{range .items[*]}image: {.spec.template.spec.containers[0].image}{"\n"}{end}'
	@echo "URL: http://$(NODE1_IP)/api/media  (any node IP)"
```

In `help`, before `@echo "  Convenience:"`, insert:

```make
	@echo "  media-service (namespace $(MEDIA_NAMESPACE)):"
	@echo "  make deploy-media        Build, push to the registry, helm upgrade (one command)"
	@echo "  make deploy-media TAG=<tag> SKIP_BUILD=1   Redeploy an existing image"
	@echo "  make media-status        Pods, ingress, image, URL"
	@echo "  make media-test          HTTP checks through Traefik on every node"
	@echo ""
```

Run: `cd borg-cloud && shellcheck -S warning -e SC1091 05-media/*.sh 04-registry/*.sh`
Expected: no output.

- [ ] **Step 5: Deploy**

Run: `cd borg-cloud && make deploy-media`
Expected: the Maven build, `docker push localhost:5050/media3:<sha>-dirty-<ts>` (the working tree has uncommitted changes under `media-service/`), then `helm upgrade --install` succeeds (`--wait`), then `>>> Deployed localhost:5050/media3:<tag>`. The first build takes several minutes. The pod listed by build.sh is `1/1 Running`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `cd borg-cloud && make media-test`
Expected:
```
  PASS  GET http://192.168.56.121/api/media -> 200 (JSON array)
  PASS  GET http://192.168.56.122/api/media -> 200 (JSON array)
  PASS  GET http://192.168.56.123/api/media -> 200 (JSON array)
  PASS  POST via 192.168.56.121 -> 201
  PASS  GET via 192.168.56.122 returns the record (stored in MongoDB)
>>> media-test: all checks passed
```

Then confirm the cleanup: run `cd borg-cloud && source ./vars.sh && source 03-databases/lib.sh && mongo_eval "$(mongo_primary)" "$(mongo_app_uri)" "print(db.media.countDocuments({artist: 'borg-media-test'}))"`
Expected: `0`.

- [ ] **Step 7: Status target**

Run: `cd borg-cloud && make media-status`
Expected: the media-service pod `Running`, an Ingress with class `traefik` and address(es) 192.168.56.12x, `image: localhost:5050/media3:<tag>`, and the URL line.

- [ ] **Step 8: Redeploys roll out (Review Focus 1 and 4)**

Run:
```bash
cd borg-cloud && export KUBECONFIG=~/.kube/config-borg
img() { kubectl -n media get deploy -l app.kubernetes.io/instance=media-service -o jsonpath='{.items[0].spec.template.spec.containers[0].image}'; }
ann() { kubectl -n media get deploy -l app.kubernetes.io/instance=media-service -o jsonpath='{.items[0].spec.template.metadata.annotations.borg/mongo-uri-sha}'; }
before=$(img)
make deploy-media >/dev/null
after=$(img)
echo "before=$before after=$after"; [ "$before" != "$after" ] && echo "NEW IMAGE ROLLED OUT"
source ./vars.sh; source 03-databases/lib.sh
want=$(mongo_app_uri | tr -d '\n' | sha256sum | cut -c1-16)
echo "annotation=$(ann) expected=$want"; [ "$(ann)" = "$want" ] && echo "URI HASH WIRED"
make media-test | tail -1
```
Expected: two different `-dirty-<ts>` tags and `NEW IMAGE ROLLED OUT`; `URI HASH WIRED`; `media-test: all checks passed`.

Note: `mongo_app_uri` ends with no newline from `sed`; `deploy-media.sh` hashes `$uri` via `printf '%s'`, and the check strips newlines, so both hash the same bytes.

- [ ] **Step 9: Missing registry and taken port are refused (Review Focus 2 and 3)**

Run:
```bash
cd borg-cloud && export KUBECONFIG=~/.kube/config-borg
kubectl -n registry scale deployment registry --replicas=0
kubectl -n registry wait --for=delete pod -l app.kubernetes.io/name=registry --timeout=120s
make deploy-media; echo "exit=$?"
kubectl -n registry scale deployment registry --replicas=1
kubectl -n registry rollout status deployment registry --timeout=180s
python3 -m http.server 5050 >/dev/null 2>&1 & blocker=$!
sleep 1
make deploy-media SKIP_BUILD=1 TAG=unused; echo "exit=$?"
kill $blocker
pgrep -af 'port-forward svc/registry' || echo "no port-forward left"
make media-test | tail -1
```
Expected: the first deploy prints `ERROR: the registry is not installed or not Available (run: make provision-registry)` before any Maven output, and exits non-zero. The second prints `ERROR: port 5050 is already in use on this host ...` and exits non-zero. Then `no port-forward left`, and `media-test: all checks passed` (the running release was untouched).

- [ ] **Step 10: Commit**

```bash
git add charts/media-service/values-borg.yaml borg-cloud/05-media/ borg-cloud/Makefile
git commit -m "borg-cloud: deploy media-service from the in-cluster registry (step 05)

make deploy-media builds, pushes localhost:5050/media3:<tag> and runs
helm upgrade with values-borg.yaml: the cluster's MongoDB (database
media) and a Traefik ingress on /api/media.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Acceptance run and PR

**Files:** none (verification and PR only).

- [ ] **Step 1: Deploy from nothing**

Run:
```bash
cd borg-cloud && export KUBECONFIG=~/.kube/config-borg
helm -n media uninstall media-service --wait
make deploy-media
make media-test
make registry-test
make db-test
```
Expected: the release is recreated; `media-test`, `registry-test` and `db-test` all end with `all checks passed`.

- [ ] **Step 2: Redeploy an existing image with one command**

Run: `cd borg-cloud && tag=$(KUBECONFIG=~/.kube/config-borg kubectl -n media get deploy -l app.kubernetes.io/instance=media-service -o jsonpath='{.items[0].spec.template.spec.containers[0].image}' | sed 's/.*://') && make deploy-media TAG=$tag SKIP_BUILD=1 && make media-test | tail -1`
Expected: no Maven or Docker build output, `helm upgrade` succeeds, and `media-test: all checks passed`.

- [ ] **Step 3: Resources**

Run: `KUBECONFIG=~/.kube/config-borg kubectl top nodes`
Expected: each node's memory is below about 85%. Record the numbers for the PR.

- [ ] **Step 4: Push and open the PR (the user merges)**

```bash
git push -u origin deploy-media-borg
gh pr create --base main --head deploy-media-borg \
  --title "Deploy media-service to BorgCloud via an in-cluster registry" \
  --body "<body>"
```

The body must contain: `Closes #4. Part of #1.`; links to the spec and plan; the targets (`provision-registry`, `registry-test`, `deploy-media`, `media-status`, `media-test`); the URL; the port 5050 note (5000 is raq-base's registry); the Dockerfile base-image fix and the build.sh dirty-tag and `HELM_EXTRA_ARGS` changes (which also affect the djmz flow); that `make provision-registry` restarts k3s node by node once; the actual test results and `kubectl top nodes` numbers from Tasks 1–4; and the line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Do not merge.
