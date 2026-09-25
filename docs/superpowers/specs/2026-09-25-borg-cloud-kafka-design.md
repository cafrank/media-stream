# BorgCloud: 3-broker Kafka (KRaft) in the kafka namespace

- **Issue:** #11 (part of epic #1; builds on #2)
- **Date:** 2026-09-25
- **Status:** Design approved, awaiting spec review

## Goal

`make provision-kafka` installs a 3-broker Kafka cluster into BorgCloud, with one broker per
k3s node, in the namespace `kafka`. It is reachable inside the cluster and from the host,
and it survives the loss of any one node. `make up` includes it.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Install | Plain StatefulSet running `apache/kafka:4.3.1` | No operator pods. Nodes have only ~1.3–1.7 GB free and the host ~4 GB, so memory goes to the brokers. It follows the Redis StatefulSet pattern from #6. Strimzi 1.2.0 was the alternative. |
| Mode | KRaft, each pod both broker and controller | 3 voters, so one node can be lost (the same tolerance as etcd). Kafka 4 has no ZooKeeper. |
| Access | In-cluster, plus from the host | Host tools can produce and consume. |
| External listener | `hostPort` 9094 on each broker, advertising `status.hostIP:9094` | One broker per node, so ports never collide, and it needs no per-broker Services. |
| Security | Plaintext, no authentication | As with the registry: only the cluster and the host-only network (192.168.56.0/24) can reach it. |
| Durability defaults | Replication factor 3, `min.insync.replicas=2` | Writes with `acks=all` survive any one broker being down. |
| Memory | Heap 384 MB; request 512Mi, limit 768Mi per broker (`vars.sh`) | It fits current headroom. VM memory stays at 4 GB. |
| `make up` | Includes `provision-kafka` (after `provision-registry`) | Per #11. |

## Layout

```
borg-cloud/
  06-kafka/
    install-kafka.sh     # cluster-ID Secret, apply, wait for pods and quorum
    kafka.yaml           # Namespace, ConfigMap (startup script), 2 Services, StatefulSet
    kafka-test.sh        # produce/consume in-cluster and from the host
    kafka-failover-test.sh
  vars.sh                # + Kafka settings
  Makefile               # + targets below; `up` includes provision-kafka
```

Step 06 follows 05 (the media deploy, which is not part of `make up`).

New `vars.sh` settings: `KAFKA_NAMESPACE="kafka"`, `KAFKA_IMAGE="apache/kafka:4.3.1"`,
`KAFKA_STORAGE_SIZE="5Gi"`, `KAFKA_HEAP="384m"`, `KAFKA_MEMORY_REQUEST="512Mi"`,
`KAFKA_MEMORY_LIMIT="768Mi"`, `KAFKA_EXTERNAL_PORT="9094"`.

## Makefile targets

| Target | Does |
|---|---|
| `make provision-kafka` | Step 06: installs Kafka; waits until 3 pods are Ready and the quorum has 3 voters and a leader |
| `make kafka-test` | Non-destructive produce/consume checks (below) |
| `make kafka-failover-test` | Disruptive: deletes one broker, checks writes and reads continue, and checks it rejoins |
| `make kafka-status` | Pods per node, quorum status, topics |
| `make kafka-uninstall` | Deletes the namespace (data and volumes). Warns and pauses 3 seconds. |

`make up` becomes `vagrant-up cluster provision-databases provision-registry provision-kafka`.

Addresses:
- In-cluster: `kafka-bootstrap.kafka.svc.cluster.local:9092`
- Host: `192.168.56.121:9094` (any node IP)
- Broker to broker: `kafka-N.kafka-headless.kafka.svc.cluster.local:9092`, controllers on `:9093`

## Components

### StatefulSet `kafka`

- 3 replicas; `podManagementPolicy: Parallel` (the quorum needs all voters starting);
  `updateStrategy: RollingUpdate` (one broker at a time). Required pod anti-affinity on
  `kubernetes.io/hostname`.
- Image `${KAFKA_IMAGE}`, running as the image's user (uid 1000), with `fsGroup: 1000`.
- A `local-path` PVC `data` of `${KAFKA_STORAGE_SIZE}` mounted at `/var/lib/kafka/data`.
- Ports: 9092 (`internal`), 9093 (`controller`), 9094 (`external`, `hostPort: 9094`).
- Env: `KAFKA_HEAP_OPTS=-Xms${KAFKA_HEAP} -Xmx${KAFKA_HEAP}`; `HOST_IP` from
  `status.hostIP`; `POD_NAME` from `metadata.name`; `CLUSTER_ID` from Secret
  `kafka-cluster-id` (key `id`).
- Resources: requests cpu 100m, memory `${KAFKA_MEMORY_REQUEST}`; limit memory
  `${KAFKA_MEMORY_LIMIT}`.
- Readiness: TCP 9092. Liveness: TCP 9092 with a generous initial delay.
- The command runs the startup script from the ConfigMap `kafka-scripts`.

### Startup script (`kafka-scripts`, `start.sh`)

1. `N=${POD_NAME##*-}`. It writes `/tmp/server.properties` (the image's config directory is
   not used), containing:
   ```
   process.roles=broker,controller
   node.id=N
   controller.quorum.voters=0@kafka-0.kafka-headless.<ns>.svc.cluster.local:9093,1@...,2@...
   listeners=INTERNAL://:9092,CONTROLLER://:9093,EXTERNAL://:9094
   advertised.listeners=INTERNAL://kafka-N.kafka-headless.<ns>.svc.cluster.local:9092,EXTERNAL://$HOST_IP:9094
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
   ```
   The namespace comes from the service-account namespace file.
2. `kafka-storage.sh format --ignore-formatted -t "$CLUSTER_ID" -c /tmp/server.properties`.
   It does nothing on an already formatted volume.
3. `exec kafka-server-start.sh /tmp/server.properties`.

### Cluster ID

A Kafka UUID (16 random bytes, base64url without padding, 22 characters), generated on the
host with `openssl` and stored in Secret `kafka-cluster-id` (key `id`) **only if it doesn't
exist**. A changed ID would make brokers refuse their formatted volumes.

### Services

- `kafka-headless`: `clusterIP: None`, `publishNotReadyAddresses: true`, ports 9092 and 9093.
  Brokers must resolve each other before they are Ready.
- `kafka-bootstrap`: ClusterIP, port 9092.

## Error handling

- Scripts use `set -euo pipefail` and the step-03 helpers (`preflight`, `die`, `wait_for`
  with `WAIT_NAMESPACE`, `retry`). A timeout prints pods and events.
- Waits (up to `DB_WAIT_TIMEOUT`): StatefulSet `readyReplicas` = 3; then
  `kafka-metadata-quorum.sh --bootstrap-server localhost:9092 describe --status` in `kafka-0`
  reports `LeaderId` ≥ 0 and 3 `CurrentVoters`.
- Re-running `provision-kafka` on a healthy cluster changes nothing (same Secret, same pod
  UIDs).

## Verification

`make kafka-test`:
1. Create topic `borg-kafka-test` if missing (`--partitions 3 --replication-factor 3
   --config min.insync.replicas=2`), then check `kafka-topics.sh --describe` shows 3 in-sync
   replicas for every partition.
2. In-cluster: produce a unique token with `acks=all` via `kafka-0` (INTERNAL listener);
   consume from the beginning via `kafka-1`, and check the token is present.
3. From the host: `docker run --rm --network host ${KAFKA_IMAGE}` runs the console producer
   and consumer against `192.168.56.121:9094`, with a fresh token, and checks the round trip.

`make kafka-failover-test`: delete `kafka-2`; while it is gone, produce with `acks=all` and
consume through `kafka-0` (this must succeed with 2 in-sync replicas); wait for `kafka-2`
Ready and for every partition of `borg-kafka-test` to show 3 in-sync replicas again; then run
`kafka-test`.

### Acceptance run (live cluster, before the PR)

1. `make provision-kafka` from nothing, then again (no change).
2. `make kafka-test`, then `make kafka-failover-test`.
3. `make kafka-uninstall`, then again (clean), then `make provision-kafka`.
4. `make db-test` and `make media-test` still pass.
5. `kubectl top nodes`: every node below ~85% memory. If not, stop and ask the user (raise VM
   memory or shrink the heaps).

## Out of scope

Authentication and TLS, Kafka Connect, Schema Registry, a UI, monitoring, topic management
beyond the test topic, and changes to media-service.
