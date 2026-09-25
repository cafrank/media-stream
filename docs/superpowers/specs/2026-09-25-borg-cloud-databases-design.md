# BorgCloud data tier: Redis, MongoDB, PostgreSQL (3 members each)

- **Issue:** #6 (part of epic #1, builds on #2)
- **Date:** 2026-09-25
- **Status:** Design approved, awaiting spec review

## Goal

Add make targets to `borg-cloud/` that install a replicated data tier into the existing
3-node k3s cluster. Each database runs 3 members, one per node, so the tier survives the
loss of any single node, the same tolerance as the cluster's embedded etcd. `make up`
builds VMs, the cluster and the databases in one step.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Placement | Workloads inside k3s, not separate VMs | No new VMs. The host has ~9 GB RAM free, and each node has ~2.8 GB available and ~36 GB disk. |
| Size | 3 members per database (issue originally said 2) | A real majority for elections. MongoDB avoids the primary-secondary-arbiter problem where majority writes stall while a data member is down. |
| Postgres | CloudNativePG operator | Handles replication and failover through the Kubernetes API, with no quorum sidecar needed. |
| MongoDB | MongoDB community operator (`MongoDBCommunity` resource) | Handles replica-set setup, SCRAM users and connection-string Secrets. |
| Redis | Plain StatefulSet in this repo: redis + Sentinel sidecar | Needs no operator. Bitnami charts are ruled out because their free images have been frozen in `bitnamilegacy` since 2025. |
| Credentials | Generated in-cluster as k8s Secrets, never written to disk | Running provisioning again reuses existing Secrets. `make db-info` reads them back from the cluster. |
| VM memory | Stays at 4 GB | The databases plus operators need ~1.3–1.5 GB per node, which leaves ≥1.3 GB per node for apps. Limits can be changed in `vars.sh`. |
| Backups | Out of scope | — |

## Layout

```
borg-cloud/
  03-databases/
    install-databases.sh   # host-side runner (kubectl/helm against $KUBECONFIG_OUT)
    operators.sh           # pinned helm installs of CNPG and the MongoDB operator
    postgres.yaml          # CNPG Cluster "pg"
    mongodb.yaml           # MongoDBCommunity "mongo"
    redis.yaml             # Redis+Sentinel StatefulSet, Services, ConfigMap
  vars.sh                  # + DB_NAMESPACE, operator/chart versions, image tags,
                           #   per-DB storage and memory sizes
  Makefile                 # + database targets; `up` includes provision-databases
```

`install-databases.sh` takes an optional argument (`all` | `postgres` | `mongo` | `redis`)
so the per-database targets reuse it. Its manifests are templated with values from `vars.sh`
(via `envsubst`) before `kubectl apply`.

All resources go in the namespace `databases` (`DB_NAMESPACE`).

## Makefile targets

| Target | Does |
|---|---|
| `make provision-databases` | Step 03: operators and all three databases, then waits until each is Ready |
| `make provision-postgres` / `provision-mongo` / `provision-redis` | Installs one database (and its operator if needed) |
| `make db-status` | Pods per database, the current primary, and replication state |
| `make db-info` | In-cluster connection strings, with credentials read from Secrets |
| `make db-test` | Checks that data written on the primary can be read on every replica |
| `make db-failover-test` | Deletes each primary pod and verifies promotion, that writes resume, and that the old pod rejoins |
| `make db-uninstall` | Removes the databases and their PVCs, then the operators (warns, pauses 3 s) |

`make up` becomes `vagrant-up cluster provision-databases`. `make cluster` is unchanged
(base + k3s). `help` documents the new targets.

## Components

### Common

- Namespace: `databases`.
- Each member: strict pod anti-affinity on `kubernetes.io/hostname` (required, not
  preferred), so there is exactly one member per node, and a `local-path` PVC. The size
  defaults to `2Gi` (`DB_STORAGE_SIZE`).
- Memory requests/limits come from `vars.sh`. Defaults: Postgres 512Mi, MongoDB 512Mi, Redis
  256Mi, Sentinel 64Mi.
- Versions are pinned in `vars.sh`: the CNPG chart, the MongoDB operator chart, and the Redis
  image. The Postgres and MongoDB major versions are pinned in their manifests.
- `local-path` volumes are tied to a node. When a VM is rebuilt, its member starts empty and
  re-syncs from the other two.

### PostgreSQL: CNPG `Cluster` "pg"

- `instances: 3`, using the official CNPG PostgreSQL image, major version 17.
- A bootstrap `initdb` creates the database `app`, owned by `app`. CNPG generates the Secret
  `pg-app` (username, password, uri). The superuser stays disabled.
- The operator creates these Services: `pg-rw` (current primary), `pg-ro` (replicas) and
  `pg-r` (any member).
- Failover is automatic, through the operator.

### MongoDB: `MongoDBCommunity` "mongo"

- `members: 3`, `type: ReplicaSet`, MongoDB `7.0` (matches the media-service chart). The
  replica set is named `mongo`, which is the operator's default: the resource name.
- User `app` with `readWrite` on the database `media`. The provisioning script creates the
  password Secret `mongo-app-password` only if it is missing. The operator writes the
  connection-string Secret `mongo-media-app` (keys `connectionString.standard` and
  `connectionString.standardSrv`).
- Implementation must confirm the current chart first. The standalone
  `mongodb-kubernetes-operator` repo was archived in 2025 in favour of `mongodb-kubernetes`,
  which still serves the `MongoDBCommunity` resource. Use whichever chart is current and pin it.

### Redis: StatefulSet "redis" + Sentinel

- 3 pods. Each has containers `redis` (6379) and `sentinel` (26379), using the official
  `redis` image, pinned.
- The headless Service `redis-headless` gives stable per-pod DNS
  (`redis-N.redis-headless.databases.svc.cluster.local`). Sentinel runs with
  `resolve-hostnames yes` and `announce-hostnames yes`, so restarted pods with new IPs
  remain recognised.
- The Service `redis-sentinel` (26379) is the client entry point. The master name is
  `mymaster` and the quorum is 2.
- The init container writes the configs to an `emptyDir`:
  1. It asks the Sentinels on the other pods (`SENTINEL get-master-addr-by-name mymaster`).
     If any answers, that host is the primary and this pod starts as its replica.
  2. If none answers (first boot of the set), `redis-0` starts as primary and the others
     replicate `redis-0`.
  This keeps a restarted former primary from starting as a second primary.
- Auth: the Secret `redis-auth` (key `password`) is created only if it is missing. It is used
  for `requirepass` and `masterauth`, and as Sentinel's `auth-pass` and `requirepass`.
- There is deliberately no plain "primary" Service, because it would point to the wrong pod
  after a failover. Clients must be Sentinel-aware (Spring Data Redis supports this).

## Error handling and idempotency

- The scripts use `set -euo pipefail`, as in steps 01 and 02.
- Preflight: `kubectl` and `helm` are on the host `PATH`, `$KUBECONFIG_OUT` exists, and 3
  nodes are Ready. Otherwise the script exits with a clear message.
- Operators are installed with `helm upgrade --install --version <pinned> --wait`, and
  resources with `kubectl apply`. Running again converges on the same state.
- Secrets are created only when absent. They are never regenerated.
- Each database waits for readiness with a timeout of ~5 minutes (`DB_WAIT_TIMEOUT`). On
  timeout, the script prints `kubectl get pods` and the recent namespace events, then exits
  non-zero.
  - Postgres: the `Cluster` reports 3 ready instances.
  - MongoDB: the resource's `status.phase` is `Running`.
  - Redis: 3/3 pods Ready, and Sentinel reports 2 replicas for `mymaster`.

## Verification

`make db-test` (non-destructive):
- Postgres: create a test table and insert a row through the primary, then read it on each
  replica pod.
- MongoDB: insert with `w: "majority"`, then read on each secondary (`readPreference: secondary`, direct connection).
- Redis: `SET` on the primary found through Sentinel, then `GET` on both replicas.

`make db-failover-test` (disruptive; not part of `make up`), for each database:
delete the primary pod → wait for a new primary → write successfully → the deleted pod
rejoins as a replica.

### Acceptance run (on the live cluster, before the PR)

1. `make provision-databases` on a cluster with no databases.
2. `make provision-databases` again: no changes, Secrets unchanged.
3. `make db-test`, then `make db-failover-test`.
4. `make db-uninstall`, then `make provision-databases`.
5. `make vagrant-destroy && make up`: only with the user's explicit go-ahead, because it
   destroys the current VMs.

## Out of scope

Backups and point-in-time recovery, TLS between clients and databases, access from outside
the cluster, monitoring/exporters, and wiring media-service to the new MongoDB (its chart
still runs its own MongoDB by default).
