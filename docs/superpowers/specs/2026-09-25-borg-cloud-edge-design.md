# BorgCloud edge: floating VIP + HAProxy replacing Traefik (#12, part 1)

- **Issue:** #12, part 1 of 2 (part of epic #1; builds on #2, #4, #11)
- **Date:** 2026-09-25
- **Status:** Design approved, awaiting spec review

## Goal

Give BorgCloud one stable entry point that survives losing any node: the floating VIP
**192.168.56.120**, served by **HAProxy** as the cluster's ingress controller. k3s's
bundled Traefik (and its servicelb load balancer) is removed. media-service moves to
`http://192.168.56.120/api/media`.

Part 2 (a separate spec) will route Kafka over TLS/SNI through this HAProxy on port 443
and remove the `node:9094` listener. Part 1 opens port 443 on the VIP but routes nothing
there yet.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Split | #12 in two parts; this is part 1 (edge) | Part 1 is useful on its own and gets tested before Kafka depends on it. |
| VIP | `192.168.56.120` (`VIP_ADDRESS`) | Inside BorgCloud's `.12x` block; free (no ping reply). |
| VIP mechanism | kube-vip in **services** mode as the `LoadBalancer` provider (ARP on `enp0s8`); HAProxy behind a `type: LoadBalancer` Service pinned to the VIP | Failover follows a healthy HAProxy pod on any node, not only the node holding the VIP. Standard Kubernetes pattern. Chosen over a control-plane VIP with host-port HAProxy, and over keepalived. |
| Ingress | HAProxy Technologies `kubernetes-ingress`; default IngressClass `haproxy` | Supports TCP services and SSL passthrough, which part 2 needs. |
| Traefik, servicelb | Disabled through `/etc/rancher/k3s/config.yaml` (`disable: [traefik, servicelb]`) | servicelb would also claim 80/443 for HAProxy's Service; nothing else uses either. |
| `externalTrafficPolicy` | `Cluster` | The VIP node forwards to a healthy HAProxy pod anywhere. Apps see an internal source IP. |
| `make up` | `vagrant-up cluster provision-edge provision-databases provision-registry provision-kafka` | The edge is cluster infrastructure. |

## Layout

```
borg-cloud/
  02-k3s/install-k3s.sh     # new clusters: write config.yaml (disable list) before installing k3s
  07-edge/
    edge-lib.sh             # helpers (namespaces, VIP holder, readiness)
    k3s-config.yaml         # the /etc/rancher/k3s/config.yaml written to every node
    install-edge.sh         # disable Traefik/servicelb (rolling), kube-vip, HAProxy
    edge-test.sh            # checks below
    edge-failover-test.sh   # pause the VIP holder's VM; VIP moves; HTTP keeps working
  vars.sh                   # + VIP_ADDRESS, chart versions, HAProxy memory
  Makefile                  # + provision-edge, edge-test, edge-failover-test; up
charts/media-service/values-borg.yaml   # ingress className: haproxy
borg-cloud/05-media/*       # URL and checks use the VIP
```

New `vars.sh` settings: `VIP_ADDRESS="192.168.56.120"`, `KUBE_VIP_CHART_VERSION="0.11.1"`
(kube-vip v1.2.3), `HAPROXY_CHART_VERSION="1.54.2"` (HAProxy 3.2.15),
`HAPROXY_NAMESPACE="haproxy-controller"`, `HAPROXY_MEMORY_REQUEST="64Mi"`,
`HAPROXY_MEMORY_LIMIT="256Mi"`. The interface is the existing `CLUSTER_IFACE` (`enp0s8`).

The directory is `07-edge` because steps are numbered in the order they were added.
`make up` runs it right after `cluster`.

## Makefile targets

| Target | Does |
|---|---|
| `make provision-edge` | Disables Traefik and servicelb (rolling k3s restart only where needed), installs kube-vip and HAProxy, and waits until the VIP answers |
| `make edge-test` | Non-destructive checks (below) |
| `make edge-failover-test` | Disruptive: pauses the VM holding the VIP, checks failover, then resumes it |

## Components

### Disabling Traefik and servicelb

- `07-edge/k3s-config.yaml`:
  ```yaml
  # /etc/rancher/k3s/config.yaml (BorgCloud). Read by k3s at startup.
  disable:
    - traefik
    - servicelb
  ```
- **New clusters:** `02-k3s/install-k3s.sh` writes this file to each node before
  installing k3s. Existing flags are unchanged.
- **Existing clusters:** for each node in turn, `install-edge.sh` restarts k3s only if the
  node's file differs from `k3s-config.yaml`, **or** if the file is newer than the running
  k3s's start time (`systemctl show k3s -p ActiveEnterTimestamp`). The second rule covers
  a run interrupted between writing and restarting. It writes the file if it differs,
  restarts k3s, and waits until that node's API server is ready and the node is Ready
  (`node_back`, as in step 04), before moving on. A node that doesn't come back stops the
  rollout with its name.
- After all nodes: if the Traefik resources are still there, it deletes the bundled
  HelmCharts (`kube-system/traefik`, `kube-system/traefik-crd`). It then waits until no
  Traefik or `svclb-*` pods remain.
- This runs **before** HAProxy is installed. media-service is unreachable for those few
  minutes of the migration.

### kube-vip (`kube-system`)

- `helm upgrade --install kube-vip kube-vip/kube-vip --version $KUBE_VIP_CHART_VERSION`. It
  runs as a DaemonSet on all nodes with host networking, configured for:
  - services mode (`svc_enable=true`, `svc_election=true`)
  - no control-plane VIP (`cp_enable=false`)
  - ARP (`vip_arp=true`) on `vip_interface=$CLUSTER_IFACE`
- A Service's IP comes from its annotation `kube-vip.io/loadbalancerIPs`. There is no
  cloud-provider and no address pool.
- Implementation must confirm the chart's value names for these settings (`helm show
  values`) and pin them.

### HAProxy (`haproxy-controller`)

- `helm upgrade --install haproxy haproxytech/kubernetes-ingress --version $HAPROXY_CHART_VERSION`
  with:
  - `controller.replicaCount=2` and preferred pod anti-affinity
  - IngressClass `haproxy`, marked default
  - Service `type: LoadBalancer`, annotation `kube-vip.io/loadbalancerIPs: $VIP_ADDRESS`,
    ports 80 (`http`) and 443 (`https`), `externalTrafficPolicy: Cluster`
  - memory request/limit from `vars.sh`
- Readiness: the Deployment is Available with 2 replicas, the Service's
  `status.loadBalancer.ingress[0].ip` equals `$VIP_ADDRESS`, and `curl http://$VIP_ADDRESS/`
  gets an HTTP answer from HAProxy (the default backend returns 404).

### media-service

- `charts/media-service/values-borg.yaml`: `ingress.className: haproxy`.
- `05-media/media-test.sh`: all HTTP checks target `$VIP_ADDRESS` (GET list, POST, GET by
  title), and it additionally checks that node IPs no longer answer on port 80.
- `05-media/deploy-media.sh` and `make media-status` print `http://$VIP_ADDRESS/api/media`.
- `install-edge.sh` doesn't deploy media-service. After the edge is up, the operator runs
  `make deploy-media SKIP_BUILD=1 TAG=<current tag>` (no rebuild) to switch the Ingress class.

## Error handling

- Scripts use `set -euo pipefail` and the shared helpers (`preflight`, `die`, `wait_for`
  with `WAIT_NAMESPACE`, `retry`), with pinned `helm upgrade --install --wait`.
- Before installing HAProxy, `install-edge.sh` confirms that no `svclb-*` pods remain, so
  nothing else claims ports 80/443.
- Re-running `provision-edge` on a configured cluster changes nothing: no k3s restarts,
  and the Helm releases are unchanged.
- No `cmd | grep -q` pipelines under `pipefail` (the #11 SIGPIPE lesson): capture output
  first, then match.

## Verification

`make edge-test`:
1. `curl http://$VIP_ADDRESS/` returns an HTTP response from HAProxy.
2. Exactly one node holds the VIP: kube-vip's lease for the HAProxy Service, or `ip addr`
   on each node shows the VIP on exactly one.
3. No Traefik pods, no `svclb-*` pods, and no `traefik` HelmChart in `kube-system`.
4. IngressClass `haproxy` exists and is the default.
5. Node IPs (`.121`–`.123`) no longer answer on port 80.

`make edge-failover-test` (needs `VBoxManage` on the host):
1. Find the node holding the VIP.
2. `VBoxManage controlvm <node> pause`.
3. Within ~60s another node holds the VIP, and `media-test` passes through it.
4. `VBoxManage controlvm <node> resume`, then wait for 3 Ready nodes.
5. `db-test` and `kafka-test` pass (they tolerate one node being briefly frozen).

A trap resumes the VM on any exit, so a failed test never leaves a VM paused.

### Acceptance run (live cluster, before the PR)

1. `make provision-edge` (the migration away from Traefik), then again (no restarts).
2. `make edge-test`; `make deploy-media SKIP_BUILD=1 TAG=<current>`; `make media-test`.
3. `make edge-failover-test`; then `db-test`, `kafka-test`, `registry-test`.
4. `kubectl top nodes`: every node below ~85% memory.

## Out of scope (part 2 or later)

Kafka TLS/SNI routing, removing `node:9094`, TLS termination for HTTP, certificates,
DNS names, a VIP for the Kubernetes API (`:6443`), and an address pool for other
`LoadBalancer` Services.
