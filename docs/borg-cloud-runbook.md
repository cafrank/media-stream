# BorgCloud Cluster Runbook

Sep 25, 2026 · @Colin

_Exported from the Claude Doc [BorgCloud Cluster Runbook](https://claude.ai/code/artifact/e70da90d-3be9-439d-b65e-7ea3f7e70c84); update both when the cluster changes._

## Quick reference

Everything external goes through one address, the floating VIP **192.168.56.120**. Run every `make` command from `borg-cloud/` in the repo, and point kubectl at the cluster with `export KUBECONFIG=~/.kube/config-borg`.

| What | Address | How to reach it |
| --- | --- | --- |
| Floating VIP (HAProxy) | `192.168.56.120` ports 80, 443 | From the host; kube-vip moves it between nodes |
| Nodes | `k3s-node1` `192.168.56.121`, `k3s-node2` `.122`, `k3s-node3` `.123` | `make ssh-node1` (2, 3) |
| Kubernetes API | `https://192.168.56.121:6443` (any node IP works) | kubeconfig `~/.kube/config-borg` |
| HAProxy stats dashboard | `http://localhost:1024/` (metrics at `/metrics`) | `kubectl -n haproxy-controller port-forward deploy/haproxy-kubernetes-ingress 1024:1024` |
| media-service | `http://192.168.56.120/api/media` | From the host, through HAProxy |
| RecordPool web app | `http://192.168.56.120/` | From the host, through HAProxy; `/api/media` still goes to media-service |
| Kafka (host, TLS) | `kafka.borg.test:443`; brokers `kafka-0/1/2.kafka.borg.test:443` | Hosts file entries + CA: `make kafka-hosts`, `make kafka-ca` |
| Kafka (in-cluster) | `kafka-bootstrap.kafka.svc.cluster.local:9092` (plaintext) | Pods only |
| PostgreSQL | `pg-rw.databases.svc.cluster.local:5432` (read-write), `pg-ro` (read-only) | Pods only; credentials: `make db-info` |
| MongoDB | replica set `mongo`, database `media` | Pods only; URI: `make db-info` |
| Redis (Sentinel) | `redis-sentinel.databases.svc.cluster.local:26379`, master `mymaster` | Pods only; password: `make db-info` |
| Image registry | push `localhost:5050/<image>` (port-forward); nodes pull via NodePort `30500` | `make deploy-media` and `make deploy-record-pool` handle it |

The databases and in-cluster Kafka have no host address. To reach one from your machine, port-forward it, for example `kubectl -n databases port-forward svc/pg-rw 5432:5432`. Don't use port 5000 on the host for BorgCloud: raq-base's `raq-registry` holds it.

## Starting the cluster

`make up` builds everything from nothing in about 30–40 minutes. After that, start and stop the existing VMs with the `vagrant-*` targets, which keep all data.

**Prerequisites on the host:** VirtualBox 7, Vagrant ≥ 2.3, kubectl, helm, docker, mvn and a JDK (for media-service builds), openssl, envsubst (`gettext-base`) and curl. About 12 GB of free RAM: each of the 3 VMs gets 4 GB.

### First-time build

1. `make up` runs these steps in order (each can also be run on its own):
   1. `make vagrant-up`: creates the 3 VMs in the VirtualBox group `/BorgCloud`
   2. `make cluster`: base OS setup plus a k3s HA install (3 servers, embedded etcd), and writes the kubeconfig
   3. `make provision-edge`: floating VIP `192.168.56.120` plus HAProxy (Traefik stays disabled)
   4. `make provision-databases`: PostgreSQL, MongoDB, Redis (3 members each)
   5. `make provision-registry`: in-cluster image registry plus node mirrors
   6. `make provision-kafka`: 3 Kafka brokers, TLS certificates, SNI routes
2. `make deploy-media`: builds and deploys media-service (not part of `make up`).
3. `make kafka-hosts`, then add the 4 printed lines to `/etc/hosts` (once per host).
4. `make kafka-ca`: writes `.kafka-ca.crt` for Kafka clients.
5. Run the health check (see Health check and troubleshooting below).

Every `provision-*` step can be re-run safely; on a healthy cluster it changes nothing.

### Daily start and stop

| Task | Command | Notes |
| --- | --- | --- |
| Start stopped VMs | `make vagrant-start` | Boots without re-provisioning. Give it \~3 minutes, then run `make cluster-status` |
| Stop (clean shutdown) | `make vagrant-halt` | Safest way to stop; the clocks resync on boot |
| Suspend | `make vagrant-suspend` | Saves RAM state |
| Resume | `make vagrant-resume` | Then resync the clocks (below) |
| VM state | `make vagrant-status` |  |
| Nodes and pods | `make cluster-status` |  |

**After a resume, resync the clocks.** A suspended VM's clock stops, and chrony only notices at its next poll, which can take minutes. Until then, Redis Sentinel and the API servers misbehave. Run:

```bash
for ip in 192.168.56.121 192.168.56.122 192.168.56.123; do
  ssh -i ~/.ssh/cluster_id_rsa ubuntu@$ip 'sudo chronyc burst 4/4 >/dev/null; sleep 12; sudo chronyc makestep'
done
```

## HAProxy and the floating VIP

HAProxy (2 replicas, namespace `haproxy-controller`) is the cluster's only ingress. It sits behind a `LoadBalancer` Service on `192.168.56.120`, which kube-vip announces from one node at a time.

- Port 80 serves HTTP routes: media-service.
- Port 443 passes Kafka TLS through, routed by server name (SNI).

### Status dashboard

1. `export KUBECONFIG=~/.kube/config-borg`
2. `kubectl -n haproxy-controller port-forward deploy/haproxy-kubernetes-ingress 1024:1024`
3. Open `http://localhost:1024/`. The page refreshes every 10 s and shows each frontend and backend with its servers' up/down state, sessions and errors.

Prometheus metrics are at `http://localhost:1024/metrics`. Each replica has its own counters, and the port-forward picks one pod. To view a specific replica, port-forward that pod instead: `kubectl -n haproxy-controller get pods`, then `kubectl -n haproxy-controller port-forward pod/<name> 1024:1024`.

### Common checks

| Task | Command |
| --- | --- |
| Full edge check (VIP answers, one holder, Traefik gone, node :80 closed) | `make edge-test` |
| Which node holds the VIP | `kubectl -n haproxy-controller get lease kubevip-haproxy-kubernetes-ingress -o jsonpath='{.spec.holderIdentity}'` |
| VIP answers | `curl -sI http://192.168.56.120/` (404 from HAProxy's default backend is normal) |
| Routes | `kubectl get ingress -A` (class `haproxy`) |
| Controller logs | `kubectl -n haproxy-controller logs deploy/haproxy-kubernetes-ingress --tail=100` |
| Rendered config | `kubectl -n haproxy-controller exec deploy/haproxy-kubernetes-ingress -- cat /etc/haproxy/haproxy.cfg` |
| Re-apply the edge | `make provision-edge` (restarts k3s on a node only if its config changed) |

### Failover

`make edge-failover-test` is disruptive:

1. It freezes the VM that holds the VIP.
2. It checks that another node takes the VIP within seconds and HAProxy keeps answering.
3. It resumes the VM and resyncs its clock.
4. It requires one stable VIP holder for 60 s before passing.

After a single VM hangs and recovers, its kube-vip can briefly reclaim the VIP, so HTTP may flap for a few minutes before settling. This is a known limitation.

## media-service

media-service runs in namespace `media` at `http://192.168.56.120/api/media`, and stores its data in the cluster's MongoDB (database `media`). `make deploy-media` builds the current checkout, pushes it to the in-cluster registry and upgrades the Helm release in one command.

| Task | Command | Notes |
| --- | --- | --- |
| Deploy or redeploy | `make deploy-media` | Maven build, Docker build, push `localhost:5050/media3:<tag>`, `helm upgrade`. Uncommitted changes under `media-service/` give a `<sha>-dirty-<time>` tag |
| Redeploy an existing image | `make deploy-media TAG=<tag> SKIP_BUILD=1` | No build. Find the tag with `make media-status` |
| Status | `make media-status` | Pods, Ingress, image tag, URL |
| Test | `make media-test` | GET list, POST a record and read it back by title through the VIP, then delete the test record in MongoDB |
| Logs | `kubectl -n media logs deploy/media-service --tail=100` |  |
| Remove | `helm -n media uninstall media-service` | Data stays in MongoDB |

Prerequisites for a deploy: `make provision-databases`, `make provision-registry` and `make provision-edge` have run. The deploy stops early and names the missing step otherwise.

**Never call `DELETE /api/media`: it deletes every record.** The test suite never uses it.

The Helm chart is `charts/media-service` with `values-borg.yaml`. Rollouts pause 5 s on shutdown (`preStopSleepSeconds`) so requests aren't dropped.

## RecordPool web app

The RecordPool web app (the Expo static export of `record-pool/`, served by nginx) runs in namespace `record-pool` at `http://192.168.56.120/`, with 2 replicas spread across nodes. Its Ingress takes `/` on the VIP. media-service's `/api/media` is a longer prefix, so HAProxy still sends it to media-service, and the app calls the API on the same origin.

| Task | Command | Notes |
| --- | --- | --- |
| Deploy or redeploy | `make deploy-record-pool` | Docker build (runs `npx expo export --platform web` inside), push `localhost:5050/record-pool:<tag>`, `helm upgrade`. Uncommitted changes under `record-pool/` give a `<sha>-dirty-<time>` tag |
| Redeploy an existing image | `make deploy-record-pool TAG=<tag> SKIP_BUILD=1` | No build. Find the tag with `make record-pool-status` |
| Status | `make record-pool-status` | Pods, Ingress, image tag, URL |
| Test | `make record-pool-test` | App shell, bundle cache headers and deep links through the VIP, `/api/media` still reaches media-service, a track's signed stream and download URLs resolve on the CDN, then `helm test` |
| Logs | `kubectl -n record-pool logs deploy/record-pool --tail=100` |  |
| Remove | `helm -n record-pool uninstall record-pool` | Stateless |

Prerequisites for a deploy: `make provision-registry` and `make provision-edge` have run. The host needs only docker; Node.js runs inside the build image.

The API base URL is built into the bundle: `EXPO_PUBLIC_API_URL` at build time, empty for the same origin. The Helm chart is `charts/record-pool` with `values-borg.yaml`; see its README.

### RecordPool downloads

Tracks are files on the CDN origin (`www.my12inch.com`, Apache) at `/prev/gen3/<song_id>.mp4` for video and `.mp3` for audio. media-service hands out short-lived signed URLs to them:

- `GET /api/media/{id}/stream` returns a signed URL as text, for playback.
- `POST /api/media/{id}/download` returns `{"url": ..., "expiresAt": ...}`. The URL carries `download=1` inside the signed part.

Both return 404 for an unknown id or a track without a `song_id`. There is no entitlement or quota check yet.

The CDN is a different origin from the app, so browsers ignore the `download` attribute. The file is saved only when the origin answers a `download=1` request with `Content-Disposition: attachment`. Without that header, Download plays the file in the tab instead, and `make record-pool-test` prints a WARN. On the origin (needs `mod_headers` and `mod_setenvif`):

```apache
<Location /prev/gen3/>
    SetEnvIf Query_String "(^|&)download=1(&|$)" FORCE_DL
    Header set Content-Disposition "attachment" env=FORCE_DL
</Location>
```

Check it with `curl -sI "<url from POST /api/media/{id}/download>" | grep -i content-disposition`.

The origin doesn't verify signatures yet: a URL with a wrong `Signature` or a past `Expires` still gets 200.

## Databases: PostgreSQL, MongoDB, Redis

All three run in namespace `databases`, 3 members each, one per node, so each survives losing any one node. `make db-info` prints every connection string and password, read live from the cluster's Secrets.

| Database | Managed by | Members | Clients connect to |
| --- | --- | --- | --- |
| PostgreSQL 17 | CloudNativePG operator (`cnpg-system`) | `pg-1..3` | `pg-rw:5432` (primary), `pg-ro` (replicas); database/user `app`, Secret `pg-app` |
| MongoDB 7.0 | MongoDB operator (`MongoDBCommunity`) | `mongo-0..2`, replica set `mongo` | URI from `make db-info` (database `media`, user `app`, authSource `admin`) |
| Redis 8 + Sentinel | StatefulSet `redis` | `redis-0..2` | Sentinel `redis-sentinel:26379`, master `mymaster`, Secret `redis-auth` |

| Task | Command |
| --- | --- |
| Install or re-apply all three | `make provision-databases` (or `provision-postgres`, `provision-mongo`, `provision-redis`) |
| Members, primaries, roles | `make db-status` |
| Connection info and credentials | `make db-info` |
| Replication test (write primary, read every replica) | `make db-test` |
| Failover test (disruptive) | `make db-failover-test`. It deletes each primary, then deletes all 3 Redis pods at once |
| Remove all three, data included | `make db-uninstall` |

### Shells

- **PostgreSQL:** `kubectl -n databases exec -it $(kubectl -n databases get cluster pg -o jsonpath='{.status.currentPrimary}') -c postgres -- psql -d app`
- **MongoDB:** `kubectl -n databases exec -it mongo-0 -c mongod -- env HOME=/tmp mongosh "<URI from make db-info>"`. `HOME=/tmp` avoids a mongosh warning about an unwritable home directory.
- **Redis:** `kubectl -n databases exec -it redis-0 -c redis -- sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning'`
- **From the host:** port-forward first, for example `kubectl -n databases port-forward svc/pg-rw 5432:5432`.

Redis clients must be Sentinel-aware, because there is no fixed primary Service. Redis's Sentinel config lives on each pod's volume, so a full restart keeps the latest primary.

## Image registry

A `registry:3.1.2` pod in namespace `registry` stores images on a 10 Gi volume. How images get in and out:

- **Push:** the host pushes to `localhost:5050` through a temporary `kubectl port-forward`. Docker allows plain HTTP to localhost, so nothing on the host is configured.
- **Pull:** each node's k3s mirrors `localhost:5050` to its own NodePort `30500` (`/etc/rancher/k3s/registries.yaml`).

| Task | Command |
| --- | --- |
| Install, or re-apply the node mirrors | `make provision-registry` (restarts k3s on a node only if its mirror config isn't loaded) |
| Test push plus pull on every node | `make registry-test` |
| Push your own image | `kubectl -n registry port-forward svc/registry 5050:5000`, then `docker push localhost:5050/<name>:<tag>` |
| List images | `curl -s http://localhost:5050/v2/_catalog` (with the port-forward running) |

The push refuses to start if host port 5050 is in use, so it can never push to the wrong registry. The registry has no garbage collection: each deploy of uncommitted changes adds about 50 MB.

## Kafka

Kafka runs 3 brokers (Kafka 4.3.1, KRaft) in namespace `kafka`, one per node. Topics default to 3 replicas and `min.insync.replicas=2`.

- **Inside the cluster:** apps use plaintext `kafka-bootstrap.kafka.svc.cluster.local:9092`.
- **From the host:** TLS through HAProxy only, at `kafka.borg.test:443`. Each broker is reached by its own name, `kafka-N.kafka.borg.test`, and nothing listens on node IPs.

### Host client setup (once)

1. `make kafka-hosts`: add the 4 printed lines (`192.168.56.120 kafka.borg.test` and so on) to `/etc/hosts`.
2. `make kafka-ca`: writes the CA certificate to `borg-cloud/.kafka-ca.crt`.
3. Client settings:

```properties
bootstrap.servers=kafka.borg.test:443
security.protocol=SSL
ssl.truststore.type=PEM
ssl.truststore.location=/path/to/borg-cloud/.kafka-ca.crt
```

A quick CLI check with no local Kafka install. Put `ca.crt` and the settings above (with `ssl.truststore.location=/tls/ca.crt`) in a directory under your home, then run:

```bash
docker run --rm -it --network host -v "$PWD:/tls:ro" --entrypoint /opt/kafka/bin/kafka-topics.sh \
  apache/kafka:4.3.1 --bootstrap-server kafka.borg.test:443 --command-config /tls/client.properties --list
```

### Operations

| Task | Command |
| --- | --- |
| Install or re-apply (certificates, brokers, SNI routes) | `make provision-kafka` (needs the edge; brokers roll only if their config or certificate changed) |
| Pods, quorum, topics | `make kafka-status` |
| Full test (in-cluster, certificates, TLS per name, host produce/consume, node :9094 closed) | `make kafka-test` |
| Failover test (disruptive): one broker down, then all 3 restarted | `make kafka-failover-test` |
| TLS check for one name | `openssl s_client -connect 192.168.56.120:443 -servername kafka-0.kafka.borg.test -CAfile .kafka-ca.crt </dev/null` |
| Broker logs | `kubectl -n kafka logs kafka-0 --tail=100` |
| Remove Kafka and its data | `make kafka-uninstall` |

**A reinstall creates a new CA.** After `make kafka-uninstall` and `make provision-kafka`, run `make kafka-ca` again and reload clients. Broker settings live in the `start.sh` ConfigMap in `06-kafka/kafka.yaml`. Editing it and re-running `make provision-kafka` rolls the brokers one at a time.

## Health check and troubleshooting

The five non-destructive tests together check the whole cluster in about 3 minutes. Each prints `all checks passed` or lists its failures.

```bash
cd borg-cloud
make cluster-status
for t in edge-test db-test registry-test kafka-test media-test; do make $t 2>&1 | grep -E 'test: |FAIL'; done
KUBECONFIG=~/.kube/config-borg kubectl top nodes   # keep each node under ~85% memory
```

### Known problems

| Symptom | Cause | Fix |
| --- | --- | --- |
| A node is `NotReady` and its `192.168.56.12x` doesn't answer ping; its kernel log shows `Unexpected TXQ (0) queue failure` | VirtualBox virtio NIC fault | `vagrant reload k3s-nodeN` (from `borg-cloud/`). The Vagrantfile now uses Intel 82540EM NICs; an older VM picks that up on its next reload |
| Redis failover never happens; Sentinel `INFO` shows `sentinel_tilt:1`; etcd logs "clock drift" | Clock steps, or a VM resumed from suspend or pause | Resync the clocks (see Starting the cluster). chrony must be installed on the nodes (`make provision-base`) |
| `http://192.168.56.120/` doesn't answer | kube-vip or HAProxy down, or no VIP holder | `make edge-test`, check the VIP lease holder, then `make provision-edge` |
| media-service `ImagePullBackOff` after a rebuild | The rebuilt registry is empty | `make deploy-media` (a full build, not `SKIP_BUILD=1`) |
| `port 5050 is already in use` | A leftover port-forward or another process | `pgrep -af 'kubectl.*port-forward svc/registry'`, then stop it |
| Kafka client: `PKIX path building failed` or "unable to verify" | CA changed by a reinstall | `make kafka-ca` and reload the client |
| Kafka client: unknown host `kafka-N.kafka.borg.test` | Missing hosts file entries | `make kafka-hosts` and add the lines |
| Deploy or install stops with "run: make provision-…" | A prerequisite step is missing | Run the step it names |

If something is stuck, re-running the matching `provision-*` target is safe; each one only changes what is out of date.

## Teardown and rebuild

Remove one service with its own uninstall target. `make vagrant-destroy` deletes the whole cluster and all its data.

| Scope | Command | What is lost |
| --- | --- | --- |
| media-service | `helm -n media uninstall media-service` | Nothing (data is in MongoDB) |
| Kafka | `make kafka-uninstall` | Topics, messages, the CA (clients need `make kafka-ca` after reinstall) |
| Databases | `make db-uninstall` | All PostgreSQL, MongoDB and Redis data; new passwords on reinstall |
| k3s only (keep VMs) | `make k3s-uninstall` | Everything in the cluster |
| Everything | `make vagrant-destroy` | The VMs and all data (asks nothing; 3 s pause to Ctrl-C) |

**Full rebuild:** `make vagrant-destroy && make up`, then `make deploy-media` and `make kafka-ca`. Your `/etc/hosts` lines stay valid, because the names and the VIP don't change.
