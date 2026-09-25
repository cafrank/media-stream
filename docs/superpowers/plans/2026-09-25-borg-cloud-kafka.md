# BorgCloud Kafka Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `make provision-kafka` (and `make up`) installs a 3-broker KRaft Kafka cluster in namespace `kafka`, one broker per node, reachable in-cluster on `kafka-bootstrap.kafka.svc:9092` and from the host on `<node IP>:9094`.

**Architecture:** A new host-side step `borg-cloud/06-kafka/` in the style of steps 03 and 04: bash scripts that source `vars.sh` and `03-databases/lib.sh`, and a manifest rendered with a restricted `envsubst`. A plain StatefulSet runs `apache/kafka:4.3.1`, each pod as broker and controller. A POSIX `sh` startup script in a ConfigMap writes `server.properties`, formats the volume once and starts Kafka. Checks run CLI tools inside the broker pods (in-cluster), and in a throwaway `docker run` of the same image on the host (external).

**Tech Stack:** bash, GNU make, kubectl 1.36, Kafka 4.3.1 (KRaft), k3s (`local-path`, hostPort through the flannel portmap plugin), Docker 29 on the host.

**Spec:** `docs/superpowers/specs/2026-09-25-borg-cloud-kafka-design.md`

## Global Constraints

- Branch `kafka-borg`. Paths in **Files:** blocks are relative to the repository root. `Run:` commands say where they run. `git` commands run from the repository root. Stage by explicit path only. Never stage the user's uncommitted files (`.gitignore`, `.idea/workspace.xml`, `README`, `media-service/src/main/java/com/sparkle/mediaservice/service/GcsSignUrl.java`, `media-service/src/main/resources/application.properties`).
- Live cluster: `~/.kube/config-borg`. **Never run `make vagrant-destroy`.**
- Namespace `kafka` (`KAFKA_NAMESPACE`). StatefulSet `kafka`, pods `kafka-0..2`. Services `kafka-headless` (headless, `publishNotReadyAddresses: true`, ports 9092/9093) and `kafka-bootstrap` (ClusterIP 9092). Secret `kafka-cluster-id` (key `id`), created only if absent.
- `KAFKA_IMAGE="apache/kafka:4.3.1"`, `KAFKA_STORAGE_SIZE="5Gi"`, `KAFKA_HEAP="384m"`, `KAFKA_MEMORY_REQUEST="512Mi"`, `KAFKA_MEMORY_LIMIT="768Mi"`, `KAFKA_EXTERNAL_PORT="9094"`.
- Listeners: `INTERNAL://:9092` (advertised `kafka-N.kafka-headless.<ns>.svc.cluster.local:9092`, inter-broker), `CONTROLLER://:9093`, `EXTERNAL://:9094` (hostPort 9094, advertised `$HOST_IP:9094`). All PLAINTEXT. No authentication.
- Defaults: `num.partitions=3`, `default.replication.factor=3`, `min.insync.replicas=2`, `offsets.topic.replication.factor=3`, `transaction.state.log.replication.factor=3`, `transaction.state.log.min.isr=2`.
- StatefulSet: 3 replicas, `podManagementPolicy: Parallel`, `RollingUpdate`, required anti-affinity on `kubernetes.io/hostname`, `fsGroup: 1000`, a `local-path` PVC `data` at `/var/lib/kafka/data`.
- `make up` = `vagrant-up cluster provision-databases provision-registry provision-kafka`.
- The test topic is `borg-kafka-test`.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Review Focus

1. **Re-running `make provision-kafka` on a healthy cluster.** Nothing may change: the same cluster ID and the same pod UIDs. A new cluster ID would make every broker refuse its volume. Pinned in Task 3, Step 3.
2. **All three brokers restarting at once** (VMs halted and started). The quorum must re-form and messages written before must still be readable. Pinned in Task 2 (`full_restart` scenario).
3. **A client that produces to a topic nobody created** (auto-creation, the common app case). The topic must get 3 replicas and `min.insync.replicas=2`, not a single replica. Pinned in Task 1, Step 2 (`kafka-test` auto-create check).
4. **Broker memory under the 768Mi limit during the tests.** No broker may be OOM-killed or restarted. Pinned in Task 4, Step 1 (`restartCount` check).
5. **`make kafka-uninstall` when nothing is installed.** It must finish cleanly. Pinned in Task 3, Step 5.

---

## File Structure

| File | Responsibility |
|---|---|
| `borg-cloud/vars.sh` (modify) | Kafka settings |
| `borg-cloud/06-kafka/kafka-lib.sh` (create) | `kk`, `render_kafka`, `kbin`, `kafka_pods_ready`, `kafka_quorum_ok`, `topic_isr_full` |
| `borg-cloud/06-kafka/kafka.yaml` (create) | Namespace, ConfigMap `kafka-scripts` (start.sh), 2 Services, StatefulSet |
| `borg-cloud/06-kafka/install-kafka.sh` (create) | Cluster-ID Secret, apply, wait for pods and quorum |
| `borg-cloud/06-kafka/kafka-test.sh` (create) | Topic, in-cluster and host round trips, auto-create check |
| `borg-cloud/06-kafka/kafka-failover-test.sh` (create) | One broker down; all brokers restarted |
| `borg-cloud/Makefile` (modify) | Targets, `up`, help |

---

### Task 1: Kafka StatefulSet, install and `kafka-test`

**Files:**
- Modify: `borg-cloud/vars.sh` (insert before `# --- Derived lists`), `borg-cloud/Makefile`
- Create: `borg-cloud/06-kafka/kafka-lib.sh`, `borg-cloud/06-kafka/kafka-test.sh`, `borg-cloud/06-kafka/kafka.yaml`, `borg-cloud/06-kafka/install-kafka.sh`

**Interfaces:**
- Consumes (from `03-databases/lib.sh`): `die`, `retry <tries> <cmd...>`, `wait_for <desc> <cmd...>` (honours `WAIT_NAMESPACE`), `preflight`. From `vars.sh`: `NODE{1,2,3}_IP`.
- Produces (`06-kafka/kafka-lib.sh`, used by Tasks 2–3):
  - `kk <kubectl args>`: kubectl in `$KAFKA_NAMESPACE`
  - `render_kafka <file>`
  - `kbin <pod> <script> <args...>`: runs `/opt/kafka/bin/<script>` in that pod's `kafka` container
  - `kafka_pods_ready`: 0 when StatefulSet `kafka` has 3 ready replicas
  - `kafka_quorum_ok`: 0 when `kafka-0` reports a leader and 3 current voters
  - `topic_isr_full <topic>`: 0 when every partition has 3 in-sync replicas
- Produces: `06-kafka/kafka-test.sh` (exit 0 = all checks passed).

- [ ] **Step 1: Settings and helpers**

Insert into `borg-cloud/vars.sh` directly above `# --- Derived lists (space-separated for loops) ---`:

```bash
# --- Kafka (06-kafka) ---
KAFKA_NAMESPACE="kafka"
KAFKA_IMAGE="apache/kafka:4.3.1"
KAFKA_STORAGE_SIZE="5Gi"                   # per broker, local-path
KAFKA_HEAP="384m"                          # JVM -Xms/-Xmx
KAFKA_MEMORY_REQUEST="512Mi"
KAFKA_MEMORY_LIMIT="768Mi"
KAFKA_EXTERNAL_PORT="9094"                 # hostPort on each node: <node IP>:9094

```

Create `borg-cloud/06-kafka/kafka-lib.sh`:

```bash
#!/bin/bash
# =============================================================================
# 06-kafka/kafka-lib.sh
# Kafka helpers. Source after vars.sh and 03-databases/lib.sh.
# =============================================================================

export KAFKA_NAMESPACE KAFKA_IMAGE KAFKA_STORAGE_SIZE KAFKA_HEAP KAFKA_MEMORY_REQUEST \
       KAFKA_MEMORY_LIMIT KAFKA_EXTERNAL_PORT

# Only these variables are substituted into kafka.yaml; start.sh's own shell
# variables ($NS, $N, $HOST_IP, ...) are left alone.
# shellcheck disable=SC2016
KAFKA_VARS='${KAFKA_NAMESPACE} ${KAFKA_IMAGE} ${KAFKA_STORAGE_SIZE} ${KAFKA_HEAP} ${KAFKA_MEMORY_REQUEST} ${KAFKA_MEMORY_LIMIT} ${KAFKA_EXTERNAL_PORT}'

kk() { kubectl -n "$KAFKA_NAMESPACE" "$@"; }

render_kafka() { envsubst "$KAFKA_VARS" < "$1"; }

# kbin <pod> <script> <args...>: run a Kafka CLI tool inside a broker pod
kbin() {
    local pod=$1 script=$2; shift 2
    kk exec "$pod" -c kafka -- "/opt/kafka/bin/$script" "$@"
}

kafka_pods_ready() {
    [ "$(kk get statefulset kafka -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = 3 ]
}

# kafka_quorum_ok: kafka-0 reports a leader and 3 current voters
kafka_quorum_ok() {
    local out
    out=$(kbin kafka-0 kafka-metadata-quorum.sh --bootstrap-server localhost:9092 describe --status 2>/dev/null) \
        || return 1
    echo "$out" | awk '
        /^LeaderId:/      { if ($2 + 0 >= 0) leader = 1 }
        /^CurrentVoters:/ { voters = gsub(/"id"/, "") }
        END { exit !(leader && voters == 3) }'
}

# topic_isr_full <topic>: every partition has 3 in-sync replicas
topic_isr_full() {
    kbin kafka-0 kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic "$1" 2>/dev/null |
        awk '/Partition:/ {
                 n++
                 for (i = 1; i <= NF; i++) if ($i == "Isr:" && split($(i + 1), a, ",") != 3) bad = 1
             }
             END { exit !(n > 0 && !bad) }'
}
```

- [ ] **Step 2: Write the failing test: create `borg-cloud/06-kafka/kafka-test.sh`**

```bash
#!/bin/bash
# =============================================================================
# 06-kafka/kafka-test.sh
# Non-destructive checks: a replicated test topic, produce/consume inside the
# cluster (INTERNAL listener) and from the host (EXTERNAL listener, <node IP>:9094,
# via a throwaway container of the Kafka image), and topic auto-creation defaults.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh
source 06-kafka/kafka-lib.sh

TOPIC=borg-kafka-test
fail=0
ok()  { echo "  PASS  $*"; }
bad() { echo "  FAIL  $*"; fail=1; }

kafka_pods_ready || die "Kafka is not installed or not Ready (run: make provision-kafka)"

# host_kafka <script> <args...>: a Kafka CLI tool on the host, through the EXTERNAL listener
host_kafka() {
    docker run --rm -i --network host --entrypoint "/opt/kafka/bin/$1" "$KAFKA_IMAGE" "${@:2}"
}

echo ">>> Topic $TOPIC"
kbin kafka-0 kafka-topics.sh --bootstrap-server localhost:9092 --create --if-not-exists \
    --topic "$TOPIC" --partitions 3 --replication-factor 3 --config min.insync.replicas=2 >/dev/null
if retry 15 topic_isr_full "$TOPIC"; then
    ok "every partition has 3 in-sync replicas"
else
    bad "partitions without 3 in-sync replicas"
fi

echo ">>> In-cluster (INTERNAL listener)"
token="in-cluster-$(date +%s)-$RANDOM"
if echo "$token" | kk exec -i kafka-0 -c kafka -- /opt/kafka/bin/kafka-console-producer.sh \
        --bootstrap-server localhost:9092 --topic "$TOPIC" --producer-property acks=all >/dev/null 2>&1; then
    ok "produce with acks=all via kafka-0"
else
    bad "produce via kafka-0"
fi
if kbin kafka-1 kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic "$TOPIC" \
        --from-beginning --timeout-ms 15000 2>/dev/null | grep -qx "$token"; then
    ok "consume via kafka-1"
else
    bad "consume via kafka-1 did not return the message"
fi

echo ">>> From the host (EXTERNAL listener, port $KAFKA_EXTERNAL_PORT)"
token="host-$(date +%s)-$RANDOM"
if echo "$token" | host_kafka kafka-console-producer.sh --bootstrap-server "$NODE1_IP:$KAFKA_EXTERNAL_PORT" \
        --topic "$TOPIC" --producer-property acks=all >/dev/null 2>&1; then
    ok "produce from host via $NODE1_IP:$KAFKA_EXTERNAL_PORT"
else
    bad "produce from host via $NODE1_IP:$KAFKA_EXTERNAL_PORT"
fi
if host_kafka kafka-console-consumer.sh --bootstrap-server "$NODE3_IP:$KAFKA_EXTERNAL_PORT" --topic "$TOPIC" \
        --from-beginning --timeout-ms 20000 2>/dev/null | grep -qx "$token"; then
    ok "consume from host via $NODE3_IP:$KAFKA_EXTERNAL_PORT (all 3 partition leaders reachable)"
else
    bad "consume from host via $NODE3_IP:$KAFKA_EXTERNAL_PORT did not return the message"
fi

echo ">>> Auto-created topic defaults"
auto="borg-kafka-auto-$(date +%s)"
echo "x" | kk exec -i kafka-0 -c kafka -- /opt/kafka/bin/kafka-console-producer.sh \
    --bootstrap-server localhost:9092 --topic "$auto" >/dev/null 2>&1 || true
desc=$(kbin kafka-0 kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic "$auto" 2>/dev/null || true)
if echo "$desc" | grep -q 'ReplicationFactor: 3'; then
    ok "auto-created topic has 3 replicas"
else
    bad "auto-created topic: $(echo "$desc" | head -1)"
fi
# A topic only lists min.insync.replicas when it overrides the broker default,
# so check the broker default itself
if kbin kafka-0 kafka-configs.sh --bootstrap-server localhost:9092 --entity-type brokers \
        --entity-name 0 --describe --all 2>/dev/null | grep -q 'min.insync.replicas=2 '; then
    ok "broker default min.insync.replicas=2"
else
    bad "broker default min.insync.replicas is not 2"
fi
kbin kafka-0 kafka-topics.sh --bootstrap-server localhost:9092 --delete --topic "$auto" >/dev/null 2>&1 || true

if [ "$fail" -eq 0 ]; then
    echo ">>> kafka-test: all checks passed"
else
    echo ">>> kafka-test: FAILED" >&2
    exit 1
fi
```

Add to `borg-cloud/Makefile`, in the variables block after `MEDIA_NAMESPACE := $(call var,MEDIA_NAMESPACE)`:

```make
KAFKA_NAMESPACE := $(call var,KAFKA_NAMESPACE)
```

and at the end of the file:

```make

.PHONY: kafka-test
kafka-test:
	bash 06-kafka/kafka-test.sh
```

Run: `cd borg-cloud && make kafka-test; echo "exit=$?"`
Expected: `ERROR: Kafka is not installed or not Ready (run: make provision-kafka)`, non-zero exit.

- [ ] **Step 3: Create `borg-cloud/06-kafka/kafka.yaml`**

```yaml
# Kafka: 3-broker KRaft cluster (each pod is broker + controller), one per node.
#   in-cluster: kafka-bootstrap.${KAFKA_NAMESPACE}.svc.cluster.local:9092
#   host:       <any node IP>:${KAFKA_EXTERNAL_PORT} (hostPort; each broker advertises its node IP)
# Plaintext, no authentication (cluster and host-only network only).
# Rendered by install-kafka.sh (render_kafka): only the variables in KAFKA_VARS
# are substituted; start.sh's own shell variables are left alone.
apiVersion: v1
kind: Namespace
metadata:
  name: ${KAFKA_NAMESPACE}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: kafka-scripts
  namespace: ${KAFKA_NAMESPACE}
data:
  start.sh: |
    #!/bin/sh
    # Writes this broker's server.properties, formats its volume on first start
    # (--ignore-formatted: no-op afterwards) and runs Kafka.
    set -eu
    NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
    N=${POD_NAME##*-}
    H="kafka-headless.$NS.svc.cluster.local"
    cat > /tmp/server.properties <<EOF
    process.roles=broker,controller
    node.id=$N
    controller.quorum.voters=0@kafka-0.$H:9093,1@kafka-1.$H:9093,2@kafka-2.$H:9093
    listeners=INTERNAL://:9092,CONTROLLER://:9093,EXTERNAL://:${KAFKA_EXTERNAL_PORT}
    advertised.listeners=INTERNAL://kafka-$N.$H:9092,EXTERNAL://$HOST_IP:${KAFKA_EXTERNAL_PORT}
    listener.security.protocol.map=INTERNAL:PLAINTEXT,CONTROLLER:PLAINTEXT,EXTERNAL:PLAINTEXT
    inter.broker.listener.name=INTERNAL
    controller.listener.names=CONTROLLER
    log.dirs=/var/lib/kafka/data
    num.partitions=3
    default.replication.factor=3
    min.insync.replicas=2
    offsets.topic.replication.factor=3
    transaction.state.log.replication.factor=3
    transaction.state.log.min.isr=2
    EOF
    echo "start: node.id=$N advertised INTERNAL kafka-$N.$H:9092 EXTERNAL $HOST_IP:${KAFKA_EXTERNAL_PORT}"
    /opt/kafka/bin/kafka-storage.sh format --ignore-formatted -t "$CLUSTER_ID" -c /tmp/server.properties
    exec /opt/kafka/bin/kafka-server-start.sh /tmp/server.properties
---
# Per-broker DNS. publishNotReadyAddresses: brokers must reach each other (the
# controller quorum) before they are Ready.
apiVersion: v1
kind: Service
metadata:
  name: kafka-headless
  namespace: ${KAFKA_NAMESPACE}
spec:
  clusterIP: None
  publishNotReadyAddresses: true
  selector:
    app.kubernetes.io/name: kafka
  ports:
    - name: internal
      port: 9092
    - name: controller
      port: 9093
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-bootstrap
  namespace: ${KAFKA_NAMESPACE}
spec:
  selector:
    app.kubernetes.io/name: kafka
  ports:
    - name: internal
      port: 9092
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka
  namespace: ${KAFKA_NAMESPACE}
spec:
  serviceName: kafka-headless
  replicas: 3
  # The controller quorum needs all voters starting together
  podManagementPolicy: Parallel
  updateStrategy:
    type: RollingUpdate
  selector:
    matchLabels:
      app.kubernetes.io/name: kafka
  template:
    metadata:
      labels:
        app.kubernetes.io/name: kafka
    spec:
      securityContext:
        fsGroup: 1000            # the image runs as appuser (uid/gid 1000)
      terminationGracePeriodSeconds: 60
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - topologyKey: kubernetes.io/hostname
              labelSelector:
                matchLabels:
                  app.kubernetes.io/name: kafka
      containers:
        - name: kafka
          image: ${KAFKA_IMAGE}
          command: ["sh", "/scripts/start.sh"]
          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: HOST_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.hostIP
            - name: CLUSTER_ID
              valueFrom:
                secretKeyRef:
                  name: kafka-cluster-id
                  key: id
            - name: KAFKA_HEAP_OPTS
              value: "-Xms${KAFKA_HEAP} -Xmx${KAFKA_HEAP}"
          ports:
            - name: internal
              containerPort: 9092
            - name: controller
              containerPort: 9093
            - name: external
              containerPort: ${KAFKA_EXTERNAL_PORT}
              hostPort: ${KAFKA_EXTERNAL_PORT}
          readinessProbe:
            tcpSocket:
              port: internal
            periodSeconds: 5
          livenessProbe:
            tcpSocket:
              port: internal
            initialDelaySeconds: 60
            periodSeconds: 20
            failureThreshold: 6
          resources:
            requests:
              cpu: 100m
              memory: ${KAFKA_MEMORY_REQUEST}
            limits:
              memory: ${KAFKA_MEMORY_LIMIT}
          volumeMounts:
            - name: scripts
              mountPath: /scripts
            - name: data
              mountPath: /var/lib/kafka/data
      volumes:
        - name: scripts
          configMap:
            name: kafka-scripts
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: local-path
        resources:
          requests:
            storage: ${KAFKA_STORAGE_SIZE}
```

- [ ] **Step 4: Create `borg-cloud/06-kafka/install-kafka.sh` and the targets**

```bash
#!/bin/bash
# =============================================================================
# 06-kafka/install-kafka.sh
# Runs from HOST. Installs the 3-broker Kafka cluster (namespace $KAFKA_NAMESPACE).
# Safe to re-run: kubectl apply, and the cluster ID Secret is never regenerated
# (a new ID would make every broker refuse its formatted volume).
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh
source 06-kafka/kafka-lib.sh

preflight

kubectl create namespace "$KAFKA_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
if kk get secret kafka-cluster-id >/dev/null 2>&1; then
    echo "    secret/kafka-cluster-id exists (kept)"
else
    # Kafka cluster ID: 16 random bytes, base64url without padding (22 chars)
    id=$(openssl rand 16 | base64 | tr '+/' '-_' | tr -d '=')
    kk create secret generic kafka-cluster-id --from-literal=id="$id" >/dev/null
    echo "    secret/kafka-cluster-id created"
fi

echo ">>> Kafka: StatefulSet kafka (3 brokers, $KAFKA_IMAGE)"
render_kafka 06-kafka/kafka.yaml | kubectl apply -f -
WAIT_NAMESPACE=$KAFKA_NAMESPACE wait_for "3 Kafka brokers Ready" kafka_pods_ready
WAIT_NAMESPACE=$KAFKA_NAMESPACE wait_for "controller quorum (leader + 3 voters)" kafka_quorum_ok
echo ">>> Kafka ready: kafka-bootstrap.$KAFKA_NAMESPACE.svc.cluster.local:9092 (in-cluster),"
echo "    $NODE1_IP:$KAFKA_EXTERNAL_PORT (host; any node IP). Test it: make kafka-test"
```

In `borg-cloud/Makefile`, after the `provision-registry` target, add:

```make
.PHONY: provision-kafka
provision-kafka:
	@echo ">>> [05/05] Kafka (namespace $(KAFKA_NAMESPACE))..."
	bash 06-kafka/install-kafka.sh
	@echo ">>> [05/05] Done."

.PHONY: kafka-status
kafka-status:
	$(KUBECTL) -n $(KAFKA_NAMESPACE) get pods -o wide
	@$(KUBECTL) -n $(KAFKA_NAMESPACE) exec kafka-0 -c kafka -- /opt/kafka/bin/kafka-metadata-quorum.sh \
		--bootstrap-server localhost:9092 describe --status | grep -E '^(LeaderId|CurrentVoters|HighWatermark)'
	@$(KUBECTL) -n $(KAFKA_NAMESPACE) exec kafka-0 -c kafka -- /opt/kafka/bin/kafka-topics.sh \
		--bootstrap-server localhost:9092 --list
```

Rename the step labels `[01/04]` → `[01/05]`, `[02/04]` → `[02/05]`, `[03/04]` → `[03/05]`, `[04/04]` → `[04/05]`.

Run: `cd borg-cloud && shellcheck -S warning -e SC1091 06-kafka/*.sh`
Expected: no output.

Run: `cd borg-cloud && source ./vars.sh && source 03-databases/lib.sh && source 06-kafka/kafka-lib.sh && render_kafka 06-kafka/kafka.yaml | grep -E 'HOST_IP:9094|\$NS|\$N\b|-Xmx384m|image: apache' | head`
Expected: lines still containing `$HOST_IP:9094`, `$NS` and `$N` (left for start.sh), `-Xmx384m`, and `image: apache/kafka:4.3.1`.

- [ ] **Step 5: Install**

Run: `cd borg-cloud && make provision-kafka`
Expected: `secret/kafka-cluster-id created`, then `3 Kafka brokers Ready: ready` and `controller quorum (leader + 3 voters): ready`. The first image pull takes a few minutes.

Run: `KUBECONFIG=~/.kube/config-borg kubectl -n kafka get pods -o wide && KUBECONFIG=~/.kube/config-borg kubectl -n kafka logs kafka-1 | grep '^start:'`
Expected: `kafka-0..2` `1/1 Running`, each on a different node; `start: node.id=1 advertised INTERNAL kafka-1.kafka-headless.kafka.svc.cluster.local:9092 EXTERNAL 192.168.56.12x:9094`, where 12x is the node that kafka-1 runs on.

If a pod crash-loops, run `kubectl -n kafka logs <pod> --previous | tail -40`. A startup-script or server.properties error is a bug in this task: fix it (using superpowers:systematic-debugging) and ledger the ruling.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `cd borg-cloud && make kafka-test`
Expected:
```
>>> Topic borg-kafka-test
  PASS  every partition has 3 in-sync replicas
>>> In-cluster (INTERNAL listener)
  PASS  produce with acks=all via kafka-0
  PASS  consume via kafka-1
>>> From the host (EXTERNAL listener, port 9094)
  PASS  produce from host via 192.168.56.121:9094
  PASS  consume from host via 192.168.56.123:9094 (all 3 partition leaders reachable)
>>> Auto-created topic defaults
  PASS  auto-created topic has 3 replicas
  PASS  broker default min.insync.replicas=2
>>> kafka-test: all checks passed
```

- [ ] **Step 7: Commit**

```bash
git add borg-cloud/vars.sh borg-cloud/Makefile borg-cloud/06-kafka/
git commit -m "borg-cloud: add 3-broker KRaft Kafka (step 06)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Failover test

**Files:**
- Create: `borg-cloud/06-kafka/kafka-failover-test.sh`
- Modify: `borg-cloud/Makefile`

**Interfaces:**
- Consumes: `kk`, `kbin`, `kafka_pods_ready`, `kafka_quorum_ok`, `topic_isr_full` (Task 1); `wait_for`, `die` (step 03); `06-kafka/kafka-test.sh`.

- [ ] **Step 1: Write the failing check**

Run: `cd borg-cloud && make kafka-failover-test; echo "exit=$?"`
Expected: `No rule to make target 'kafka-failover-test'`, `exit=2`.

- [ ] **Step 2: Create `borg-cloud/06-kafka/kafka-failover-test.sh`**

```bash
#!/bin/bash
# =============================================================================
# 06-kafka/kafka-failover-test.sh [all|one-down|full-restart]
# DISRUPTIVE.
#   one-down:     delete kafka-2; acks=all writes and reads keep working through
#                 kafka-0 (2 in-sync replicas remain); kafka-2 rejoins.
#   full-restart: delete all 3 brokers at once (as a VM halt/start does); the
#                 quorum re-forms and a message written before is still there.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh
source 06-kafka/kafka-lib.sh

TOPIC=borg-kafka-test
kafka_pods_ready || die "Kafka is not installed or not Ready (run: make provision-kafka)"
kbin kafka-0 kafka-topics.sh --bootstrap-server localhost:9092 --create --if-not-exists \
    --topic "$TOPIC" --partitions 3 --replication-factor 3 --config min.insync.replicas=2 >/dev/null

produce() { # produce <pod> <message>
    echo "$2" | kk exec -i "$1" -c kafka -- /opt/kafka/bin/kafka-console-producer.sh \
        --bootstrap-server localhost:9092 --topic "$TOPIC" --producer-property acks=all >/dev/null 2>&1
}
consumed() { # consumed <pod> <message>: the topic contains the message
    kbin "$1" kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic "$TOPIC" \
        --from-beginning --timeout-ms 20000 2>/dev/null | grep -qx "$2"
}
pod_uid() { kk get pod "$1" -o jsonpath='{.metadata.uid}' 2>/dev/null; }
# pod_down <pod> <old uid>: the pod was replaced or is not Ready
pod_down() {
    [ "$(pod_uid "$1")" != "$2" ] ||
    [ "$(kk get pod "$1" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)" != true ]
}

one_down() {
    local uid token
    uid=$(pod_uid kafka-2)
    echo ">>> Kafka: deleting kafka-2"
    kk delete pod kafka-2 --wait=false >/dev/null
    WAIT_NAMESPACE=$KAFKA_NAMESPACE wait_for "kafka-2 down" pod_down kafka-2 "$uid"
    token="one-down-$(date +%s)-$RANDOM"
    produce kafka-0 "$token" || die "Kafka: acks=all produce failed with one broker down"
    consumed kafka-0 "$token" || die "Kafka: message written with one broker down was not read back"
    echo "    acks=all write and read worked with one broker down"
    WAIT_NAMESPACE=$KAFKA_NAMESPACE wait_for "3 brokers Ready" kafka_pods_ready
    WAIT_NAMESPACE=$KAFKA_NAMESPACE wait_for "every partition back to 3 in-sync replicas" topic_isr_full "$TOPIC"
}

full_restart() {
    local token
    token="before-restart-$(date +%s)-$RANDOM"
    produce kafka-0 "$token" || die "Kafka: produce before restart failed"
    echo ">>> Kafka: deleting all 3 brokers at once"
    kk delete pod kafka-0 kafka-1 kafka-2 --wait=true >/dev/null
    WAIT_NAMESPACE=$KAFKA_NAMESPACE wait_for "3 brokers Ready" kafka_pods_ready
    WAIT_NAMESPACE=$KAFKA_NAMESPACE wait_for "controller quorum (leader + 3 voters)" kafka_quorum_ok
    WAIT_NAMESPACE=$KAFKA_NAMESPACE wait_for "every partition back to 3 in-sync replicas" topic_isr_full "$TOPIC"
    consumed kafka-1 "$token" || die "Kafka: message written before the restart is gone"
    echo "    quorum re-formed; message written before the restart is still there"
}

target=${1:-all}
case "$target" in
    all)          one_down; full_restart ;;
    one-down)     one_down ;;
    full-restart) full_restart ;;
    *) die "usage: $0 [all|one-down|full-restart]" ;;
esac
bash 06-kafka/kafka-test.sh
echo ">>> kafka-failover-test: passed"
```

In `borg-cloud/Makefile`, after `kafka-test`, add:

```make

.PHONY: kafka-failover-test
kafka-failover-test:
	@echo "WARNING: This deletes Kafka broker pods. Ctrl-C to abort."
	@sleep 3
	bash 06-kafka/kafka-failover-test.sh
```

Run: `cd borg-cloud && shellcheck -S warning -e SC1091 06-kafka/*.sh`
Expected: no output.

- [ ] **Step 3: Run it**

Run: `cd borg-cloud && make kafka-failover-test`
Expected: `acks=all write and read worked with one broker down`, then `every partition back to 3 in-sync replicas: ready`, then `quorum re-formed; message written before the restart is still there`, then `kafka-test: all checks passed` and `>>> kafka-failover-test: passed`. About 3–6 minutes.

- [ ] **Step 4: Commit**

```bash
git add borg-cloud/Makefile borg-cloud/06-kafka/kafka-failover-test.sh
git commit -m "borg-cloud: add kafka-failover-test (one broker down, full restart)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Uninstall, idempotency, `make up`, help

**Files:**
- Modify: `borg-cloud/Makefile`

**Interfaces:**
- Consumes: `install-kafka.sh` (Task 1); namespace `kafka`.

- [ ] **Step 1: Write the failing check**

Run: `cd borg-cloud && make -n up | grep -c install-kafka.sh`
Expected: `0`.

- [ ] **Step 2: Wire `make up`, uninstall and help**

Change `up: vagrant-up cluster provision-databases provision-registry` to:

```make
up: vagrant-up cluster provision-databases provision-registry provision-kafka
```

After `kafka-status`, add:

```make

.PHONY: kafka-uninstall
kafka-uninstall:
	@echo "WARNING: This deletes Kafka and all its data (namespace $(KAFKA_NAMESPACE)). Ctrl-C to abort."
	@sleep 3
	$(KUBECTL) delete namespace $(KAFKA_NAMESPACE) --ignore-not-found --wait=true
```

In `help`, change `Everything: vagrant-up + cluster + databases + registry` to `Everything: vagrant-up + cluster + databases + registry + kafka`. After the line `make provision-registry  4. In-cluster image registry + node mirrors`, add:

```make
	@echo "  make provision-kafka     5. Kafka, 3 brokers (KRaft)"
```

Before `@echo "  Convenience:"`, insert:

```make
	@echo "  Kafka (namespace $(KAFKA_NAMESPACE); step 06-kafka):"
	@echo "  make provision-kafka     3 brokers, one per node (KRaft, plaintext)"
	@echo "  make kafka-status        Pods, controller quorum, topics"
	@echo "  make kafka-test          Produce/consume in-cluster and from the host"
	@echo "  make kafka-failover-test One broker down; all brokers restarted (disruptive)"
	@echo "  make kafka-uninstall     Delete Kafka and its data"
	@echo "    in-cluster: kafka-bootstrap.$(KAFKA_NAMESPACE).svc.cluster.local:9092"
	@echo "    host:       $(NODE1_IP):9094 (any node IP)"
	@echo ""
```

Run: `cd borg-cloud && make -n up | grep -c install-kafka.sh && make help | grep -c kafka`
Expected: `1`, then `7` or more.

- [ ] **Step 3: Re-running changes nothing (Review Focus 1)**

Run:
```bash
cd borg-cloud && export KUBECONFIG=~/.kube/config-borg
snap() {
    kubectl -n kafka get secret kafka-cluster-id -o jsonpath='{.data.id}{"\n"}' | sha256sum | cut -c1-12
    kubectl -n kafka get pods -o jsonpath='{range .items[*]}{.metadata.name}={.metadata.uid}{"\n"}{end}' | sort
}
before=$(snap); make provision-kafka | grep -E 'secret/|ready'; after=$(snap)
[ "$before" = "$after" ] && echo "IDEMPOTENT" || diff <(echo "$before") <(echo "$after")
```
Expected: `secret/kafka-cluster-id exists (kept)`, both waits `ready`, and `IDEMPOTENT`.

- [ ] **Step 4: Status target**

Run: `cd borg-cloud && make kafka-status`
Expected: 3 `Running` pods on 3 nodes; `LeaderId:` with 0, 1 or 2; `CurrentVoters:` listing ids 0, 1 and 2; and `borg-kafka-test` in the topic list.

- [ ] **Step 5: Uninstall, uninstall again, reinstall (Review Focus 5)**

Run: `cd borg-cloud && make kafka-uninstall && make kafka-uninstall; echo "exit=$?"`
Expected: the first deletes the namespace; the second prints nothing to delete and `exit=0`.

Run: `cd borg-cloud && make provision-kafka | grep -E 'secret/|ready' && make kafka-test | tail -1`
Expected: `secret/kafka-cluster-id created` (a fresh cluster), both waits `ready`, and `kafka-test: all checks passed`.

- [ ] **Step 6: Commit**

```bash
git add borg-cloud/Makefile
git commit -m "borg-cloud: add kafka-uninstall, include Kafka in make up, document targets

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Acceptance run and PR

**Files:** none.

- [ ] **Step 1: Full check and broker restarts (Review Focus 4)**

Run:
```bash
cd borg-cloud && export KUBECONFIG=~/.kube/config-borg
make kafka-test | tail -1
make kafka-failover-test | tail -1
make db-test | tail -1
make media-test | tail -1
kubectl -n kafka get pods -o jsonpath='{range .items[*]}{.metadata.name} restarts={.status.containerStatuses[0].restartCount} lastTerminated={.status.containerStatuses[0].lastState.terminated.reason}{"\n"}{end}'
kubectl top nodes
```
Expected: all four suites end with `passed`; every broker shows `restarts=0` and an empty `lastTerminated` (no `OOMKilled`); every node's memory is below about 85%.

If any node is at or above ~85%, or a broker was `OOMKilled`, **stop and ask the user** whether to raise `VM_MEMORY` or shrink `KAFKA_HEAP`/limits, as the spec requires.

- [ ] **Step 2: Push and open the PR (the user merges)**

```bash
git push -u origin kafka-borg
gh pr create --base main --head kafka-borg \
  --title "BorgCloud: 3-broker Kafka (KRaft) in the kafka namespace" \
  --body "<body>"
```

The body must contain: `Closes #11. Part of #1.`; links to the spec and plan; the targets; both addresses; the design choices (a plain StatefulSet, KRaft combined roles, a hostPort external listener, plaintext, RF 3 / `min.insync.replicas=2`, memory settings); that `make up` now includes Kafka; the actual results from Tasks 1–4, including the `kubectl top nodes` numbers and broker restart counts; and `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Do not merge.
