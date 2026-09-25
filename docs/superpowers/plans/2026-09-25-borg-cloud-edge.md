# BorgCloud Edge (VIP + HAProxy) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `make provision-edge` replaces k3s's Traefik/servicelb with HAProxy behind the floating VIP `192.168.56.120` (kube-vip), and media-service moves to `http://192.168.56.120/api/media`.

**Architecture:** A new host-side step `borg-cloud/07-edge/`. First, a k3s config file (`disable: [traefik, servicelb]`) is rolled onto each node, restarting k3s only where needed. Then pinned Helm releases of kube-vip (services mode, ARP) and HAProxy Kubernetes Ingress, whose `LoadBalancer` Service is pinned to the VIP. media-service's Ingress switches to class `haproxy`. Tests run from the host: curl against the VIP, ssh to the nodes for VIP ownership, and VirtualBox pause/resume for failover.

**Tech Stack:** bash, GNU make, kubectl 1.36, helm 4, k3s v1.36, kube-vip chart 0.11.1 (v1.2.3), haproxytech/kubernetes-ingress chart 1.54.2 (HAProxy 3.2.15), VirtualBox (`VBoxManage`).

**Spec:** `docs/superpowers/specs/2026-09-25-borg-cloud-edge-design.md`

## Global Constraints

- Branch `edge-haproxy-vip`. Paths in **Files:** are relative to the repository root. `Run:` commands say where they run. `git` commands run from the repository root. Stage by explicit path only. Never stage the user's uncommitted files (`.gitignore`, `.idea/workspace.xml`, `README`, `media-service/src/main/java/com/sparkle/mediaservice/service/GcsSignUrl.java`, `media-service/src/main/resources/application.properties`).
- Live cluster: `~/.kube/config-borg` (server `https://192.168.56.121:6443`). **Never run `make vagrant-destroy`.**
- `VIP_ADDRESS="192.168.56.120"`. Interface `CLUSTER_IFACE` (`enp0s8`, already in `vars.sh`).
- `/etc/rancher/k3s/config.yaml` on every node = `borg-cloud/07-edge/k3s-config.yaml` (`disable: [traefik, servicelb]`). k3s is restarted on a node only if its file differs, **or** the file is newer than k3s's last start. One node at a time; wait for `node_back` before the next.
- kube-vip: release `kube-vip` in `kube-system`, chart `kube-vip/kube-vip` `KUBE_VIP_CHART_VERSION="0.11.1"`, with `env.vip_interface=$CLUSTER_IFACE`, `vip_arp=true`, `svc_enable=true`, `svc_election=true`, `cp_enable=false`, `lb_enable=false`.
- HAProxy: release `haproxy` in `HAPROXY_NAMESPACE="haproxy-controller"`, chart `haproxytech/kubernetes-ingress` `HAPROXY_CHART_VERSION="1.54.2"`: 2 replicas, preferred anti-affinity, default IngressClass `haproxy`, Service `type: LoadBalancer` with annotation `kube-vip.io/loadbalancerIPs: 192.168.56.120` (plus `loadBalancerIP`), only ports 80 and 443 (quic/stat/admin disabled), `externalTrafficPolicy` left at `Cluster`, memory `HAPROXY_MEMORY_REQUEST="64Mi"` / `HAPROXY_MEMORY_LIMIT="256Mi"`, cpu request 50m.
- media-service: `className: haproxy`; URL `http://192.168.56.120/api/media`.
- `make up` = `vagrant-up cluster provision-edge provision-databases provision-registry provision-kafka`.
- No `cmd | grep -q` pipelines under `pipefail`: capture the output, then match it (the #11 lesson).
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Review Focus

1. **A migration interrupted between writing a node's config.yaml and restarting k3s.** The next `provision-edge` must restart that node rather than call it up to date. Pinned in Task 1, Step 7.
2. **Re-running `provision-edge` on a migrated cluster.** It must not restart k3s anywhere. Pinned in Task 4, Step 3.
3. **The VIP holder is node1, which is also the kubeconfig's API server.** Freezing it in the failover test must not cut the test off from the cluster. Pinned in Task 3 (temporary kubeconfig on a surviving node).
4. **media-service's single pod runs on the frozen node.** The failover test must not report a false failure (media is legitimately down there), but it must still prove the VIP moved and HAProxy answers. Pinned in Task 3.
5. **A fresh cluster (`make up` after `vagrant-destroy`).** `install-k3s.sh` must write config.yaml before the first k3s install, so Traefik never starts. It can't run live without destroying VMs, so Task 1, Step 8 checks the ordering in the script statically.

---

## File Structure

| File | Responsibility |
|---|---|
| `borg-cloud/vars.sh` (modify) | VIP and edge settings |
| `borg-cloud/07-edge/k3s-config.yaml` (create) | The k3s config for every node |
| `borg-cloud/07-edge/edge-lib.sh` (create) | `node_back`, `k3s_config_current`, `traefik_gone`, `vip_holders`, `haproxy_ready`, `http_code` |
| `borg-cloud/07-edge/install-edge.sh` (create) | Disable Traefik/servicelb (rolling), kube-vip, HAProxy |
| `borg-cloud/07-edge/edge-test.sh` (create) | `[all|k3s|vip]` checks |
| `borg-cloud/07-edge/edge-failover-test.sh` (create) | Pause the VIP holder, check failover, resume |
| `borg-cloud/02-k3s/install-k3s.sh` (modify) | Write config.yaml before installing k3s |
| `charts/media-service/values-borg.yaml` (modify) | `className: haproxy` |
| `borg-cloud/05-media/media-test.sh`, `deploy-media.sh` (modify) | Use the VIP |
| `borg-cloud/Makefile` (modify) | Targets, `up`, help, media URL |

---

### Task 1: Disable Traefik and servicelb (rolling)

**Files:**
- Modify: `borg-cloud/vars.sh`, `borg-cloud/02-k3s/install-k3s.sh`, `borg-cloud/Makefile`
- Create: `borg-cloud/07-edge/k3s-config.yaml`, `borg-cloud/07-edge/edge-lib.sh`, `borg-cloud/07-edge/edge-test.sh`, `borg-cloud/07-edge/install-edge.sh`

**Interfaces:**
- Consumes: `03-databases/lib.sh` (`preflight`, `die`, `wait_for` with `WAIT_NAMESPACE`, `retry`); `vars.sh` (`ssh_node`, `NODE{1,2,3}_{NAME,IP}`, `CLUSTER_IFACE`).
- Produces (`07-edge/edge-lib.sh`, used by Tasks 2–4):
  - `node_back <name> <ip>`: 0 when that node's own API server is ready and the node is Ready
  - `k3s_config_current <ip>`: 0 when the node's config.yaml equals `07-edge/k3s-config.yaml` and is not newer than k3s's start
  - `traefik_gone`: 0 when there are no Traefik or `svclb-*` pods and no `traefik`/`traefik-crd` HelmChart
  - `vip_holders [exclude-ip]`: prints the name of each node that has the VIP on `$CLUSTER_IFACE`, skipping `exclude-ip`
  - `haproxy_ready`: defined in Task 2
  - `http_code <url>`: prints curl's HTTP code, or `000`
- Produces: `07-edge/install-edge.sh` with a function `disable_traefik`; `07-edge/edge-test.sh [all|k3s|vip]`.

- [ ] **Step 1: Settings, the k3s config file, and helpers**

Insert into `borg-cloud/vars.sh` directly above `# --- Derived lists (space-separated for loops) ---`:

```bash
# --- Edge: floating VIP + HAProxy ingress (07-edge) ---
VIP_ADDRESS="192.168.56.120"               # kube-vip ARP on CLUSTER_IFACE; HAProxy's LoadBalancer IP
KUBE_VIP_CHART_VERSION="0.11.1"            # kube-vip/kube-vip -> kube-vip v1.2.3
HAPROXY_CHART_VERSION="1.54.2"             # haproxytech/kubernetes-ingress -> HAProxy 3.2.15
HAPROXY_NAMESPACE="haproxy-controller"
HAPROXY_MEMORY_REQUEST="64Mi"
HAPROXY_MEMORY_LIMIT="256Mi"

```

Create `borg-cloud/07-edge/k3s-config.yaml`:

```yaml
# /etc/rancher/k3s/config.yaml (BorgCloud). Read by k3s at startup.
# Traefik and servicelb are replaced by HAProxy on a kube-vip VIP (07-edge).
disable:
  - traefik
  - servicelb
```

Create `borg-cloud/07-edge/edge-lib.sh`:

```bash
#!/bin/bash
# =============================================================================
# 07-edge/edge-lib.sh
# Edge helpers. Source after vars.sh and 03-databases/lib.sh.
# =============================================================================

export VIP_ADDRESS HAPROXY_NAMESPACE CLUSTER_IFACE

# node_back <name> <ip>: that node's own API server is ready and the node is Ready
node_back() {
    local rz nodes
    rz=$(ssh_node "$2" 'sudo k3s kubectl get --raw=/readyz' 2>/dev/null) || return 1
    [ "$rz" = ok ] || return 1
    nodes=$(kubectl get node "$1" --no-headers 2>/dev/null) || return 1
    awk '$2 == "Ready" {ok = 1} END {exit !ok}' <<<"$nodes"
}

# k3s_config_current <ip>: config.yaml equals 07-edge/k3s-config.yaml AND is not
# newer than the running k3s (a file written by an interrupted run doesn't count)
k3s_config_current() {
    local ip=$1 have times
    have=$(ssh_node "$ip" 'sudo cat /etc/rancher/k3s/config.yaml 2>/dev/null' || true)
    [ "$have" = "$(cat 07-edge/k3s-config.yaml)" ] || return 1
    times=$(ssh_node "$ip" 'echo "$(sudo stat -c %Y /etc/rancher/k3s/config.yaml) $(date -d "$(systemctl show -p ActiveEnterTimestamp --value k3s)" +%s)"') \
        || return 1
    awk '{exit !($1 <= $2)}' <<<"$times"
}

# traefik_gone: no Traefik or svclb pods, no bundled Traefik HelmCharts
traefik_gone() {
    local pods charts
    pods=$(kubectl -n kube-system get pods --no-headers -o custom-columns=N:.metadata.name 2>/dev/null) || return 1
    charts=$(kubectl -n kube-system get helmcharts.helm.cattle.io --no-headers \
        -o custom-columns=N:.metadata.name 2>/dev/null || true)
    ! grep -qE '^(traefik|svclb-)' <<<"$pods" && ! grep -qxE 'traefik|traefik-crd' <<<"$charts"
}

# vip_holders [exclude-ip]: names of nodes with the VIP on CLUSTER_IFACE
vip_holders() {
    local i name_var ip_var addrs
    for i in 1 2 3; do
        name_var="NODE${i}_NAME"; ip_var="NODE${i}_IP"
        [ "${!ip_var}" = "${1:-}" ] && continue
        addrs=$(ssh_node "${!ip_var}" "ip -4 -o addr show dev $CLUSTER_IFACE" 2>/dev/null || true)
        if grep -qF " $VIP_ADDRESS/" <<<"$addrs"; then echo "${!name_var}"; fi
    done
}

# http_code <url>: the HTTP status code, or 000 if nothing answered
http_code() { curl -s -m 5 -o /dev/null -w '%{http_code}' "$1" || true; }
```

- [ ] **Step 2: Write the failing test: create `borg-cloud/07-edge/edge-test.sh`**

```bash
#!/bin/bash
# =============================================================================
# 07-edge/edge-test.sh [all|k3s|vip]
#   k3s: every node runs with 07-edge/k3s-config.yaml; Traefik and servicelb are
#        gone; node IPs no longer answer on port 80
#   vip: the VIP answers HTTP from HAProxy; exactly one node holds it; haproxy is
#        the default IngressClass
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh
source 07-edge/edge-lib.sh

fail=0
ok()  { echo "  PASS  $*"; }
bad() { echo "  FAIL  $*"; fail=1; }

test_k3s() {
    local i name_var ip_var code
    echo ">>> k3s: Traefik and servicelb disabled"
    for i in 1 2 3; do
        name_var="NODE${i}_NAME"; ip_var="NODE${i}_IP"
        if k3s_config_current "${!ip_var}"; then ok "${!name_var}: config.yaml loaded"
        else bad "${!name_var}: config.yaml missing, different, or not loaded"; fi
    done
    if traefik_gone; then ok "no Traefik or svclb pods, no Traefik HelmCharts"
    else bad "Traefik or svclb still present"; fi
    for ip in $ALL_IPS; do
        code=$(http_code "http://$ip/")
        if [ "$code" = 000 ]; then ok "$ip:80 closed"; else bad "$ip:80 still answers ($code)"; fi
    done
}

test_vip() {
    local code holders classes
    echo ">>> VIP $VIP_ADDRESS"
    code=$(http_code "http://$VIP_ADDRESS/")
    if [ "$code" != 000 ]; then ok "http://$VIP_ADDRESS/ answers ($code)"
    else bad "http://$VIP_ADDRESS/ does not answer"; fi
    holders=$(vip_holders)
    if [ "$(grep -c . <<<"$holders")" = 1 ]; then ok "held by exactly one node: $holders"
    else bad "VIP holders: '$(tr '\n' ' ' <<<"$holders")' (want exactly one)"; fi
    classes=$(kubectl get ingressclass -o jsonpath='{range .items[*]}{.metadata.name}={.metadata.annotations.ingressclass\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null || true)
    if grep -qx 'haproxy=true' <<<"$classes"; then ok "IngressClass haproxy is the default"
    else bad "IngressClass haproxy is not the default: $(tr '\n' ' ' <<<"$classes")"; fi
}

target=${1:-all}
case "$target" in
    all) test_k3s; test_vip ;;
    k3s) test_k3s ;;
    vip) test_vip ;;
    *) die "usage: $0 [all|k3s|vip]" ;;
esac

if [ "$fail" -eq 0 ]; then
    echo ">>> edge-test: all checks passed"
else
    echo ">>> edge-test: FAILED" >&2
    exit 1
fi
```

Add to `borg-cloud/Makefile`, in the variables block after `KAFKA_NAMESPACE := $(call var,KAFKA_NAMESPACE)`:

```make
VIP_ADDRESS := $(call var,VIP_ADDRESS)
```

and at the end of the file:

```make

.PHONY: edge-test
edge-test:
	bash 07-edge/edge-test.sh
```

Run: `cd borg-cloud && bash 07-edge/edge-test.sh k3s; echo "exit=$?"`
Expected: three `FAIL  k3s-nodeN: config.yaml missing...`, `FAIL  Traefik or svclb still present`, three `FAIL  192.168.56.12N:80 still answers (404)`, `>>> edge-test: FAILED`, `exit=1`.

- [ ] **Step 3: Create `borg-cloud/07-edge/install-edge.sh` (Traefik/servicelb part)**

```bash
#!/bin/bash
# =============================================================================
# 07-edge/install-edge.sh
# Runs from HOST. Replaces k3s's Traefik/servicelb with HAProxy on the VIP:
#   1. /etc/rancher/k3s/config.yaml (disable traefik, servicelb) on each node,
#      restarting k3s one node at a time, only where not already loaded
#   2. kube-vip (services mode, ARP) and HAProxy behind a LoadBalancer on the VIP
# Safe to re-run.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh
source 07-edge/edge-lib.sh

disable_traefik() {
    local i name_var ip_var name ip
    echo ">>> k3s: disable Traefik and servicelb (/etc/rancher/k3s/config.yaml)"
    for i in 1 2 3; do
        name_var="NODE${i}_NAME"; ip_var="NODE${i}_IP"
        name=${!name_var}; ip=${!ip_var}
        if k3s_config_current "$ip"; then
            echo "    $name: up to date"
            continue
        fi
        echo "    $name: writing config.yaml, restarting k3s"
        ssh_node "$ip" 'sudo mkdir -p /etc/rancher/k3s && sudo tee /etc/rancher/k3s/config.yaml >/dev/null' \
            < 07-edge/k3s-config.yaml
        ssh_node "$ip" 'sudo systemctl restart k3s'
        WAIT_NAMESPACE=kube-system wait_for "$name back after k3s restart" node_back "$name" "$ip"
    done
    # k3s may leave the bundled Traefik release behind; remove it through helm-controller
    if kubectl -n kube-system get helmcharts.helm.cattle.io traefik traefik-crd >/dev/null 2>&1; then
        echo "    removing bundled Traefik HelmCharts"
        kubectl -n kube-system delete helmcharts.helm.cattle.io traefik traefik-crd --ignore-not-found
    fi
    WAIT_NAMESPACE=kube-system wait_for "Traefik and svclb pods gone" traefik_gone
}

preflight
disable_traefik
echo ">>> Edge ready."
```

In `borg-cloud/Makefile`, after the `provision-kafka` target, add:

```make
.PHONY: provision-edge
provision-edge:
	@echo ">>> [edge] VIP $(VIP_ADDRESS) + HAProxy ingress (replaces Traefik)..."
	bash 07-edge/install-edge.sh
	@echo ">>> [edge] Done."
```

Run: `cd borg-cloud && shellcheck -S warning -e SC1091 07-edge/*.sh`
Expected: no output.

- [ ] **Step 4: Run the migration**

Run: `cd borg-cloud && make provision-edge`
Expected: each node shows `writing config.yaml, restarting k3s` then `k3s-nodeN back after k3s restart: ready`; then possibly `removing bundled Traefik HelmCharts`; then `Traefik and svclb pods gone: ready`. media-service is now unreachable until Task 3. That is expected.

- [ ] **Step 5: Run the test to confirm it passes**

Run: `cd borg-cloud && bash 07-edge/edge-test.sh k3s && make db-test | tail -1 && make kafka-test | tail -1`
Expected: every `k3s` check `PASS` (config loaded on 3 nodes; Traefik/svclb gone; all three node IPs `:80 closed`); `edge-test: all checks passed`; `db-test` and `kafka-test` pass (the data tier survived the rolling restarts).

- [ ] **Step 6: Fresh clusters write the config before installing k3s**

In `borg-cloud/02-k3s/install-k3s.sh`, directly after the line `K3S_TOKEN=$(cat "$K3S_TOKEN_FILE")`, add:

```bash

# k3s reads /etc/rancher/k3s/config.yaml at startup: Traefik and servicelb stay off
# (07-edge replaces them with HAProxy on a kube-vip VIP)
for ip in $ALL_IPS; do
    ssh_node "$ip" 'sudo mkdir -p /etc/rancher/k3s && sudo tee /etc/rancher/k3s/config.yaml >/dev/null' \
        < 07-edge/k3s-config.yaml
done
```

Run: `cd borg-cloud && shellcheck -S warning -e SC1091 02-k3s/install-k3s.sh && awk '/07-edge\/k3s-config.yaml/ && !c {c = NR} /^install_server "\$NODE1_IP"$/ && !s {s = NR} END {print (c && s && c < s) ? "ORDER OK" : "ORDER WRONG"}' 02-k3s/install-k3s.sh`
Expected: `ORDER OK` (Review Focus 5).

- [ ] **Step 7: An interrupted migration is finished (Review Focus 1)**

Run:
```bash
cd borg-cloud && source ./vars.sh
ssh_node "$NODE3_IP" 'sudo touch /etc/rancher/k3s/config.yaml'   # newer than k3s's start = "written, not restarted"
bash 07-edge/edge-test.sh k3s | grep node3
make provision-edge | grep -E 'up to date|restarting'
bash 07-edge/edge-test.sh k3s | tail -1
```
Expected: `FAIL  k3s-node3: config.yaml missing, different, or not loaded`; then `k3s-node1: up to date`, `k3s-node2: up to date`, `k3s-node3: writing config.yaml, restarting k3s`; then `edge-test: all checks passed`.

- [ ] **Step 8: Commit**

```bash
git add borg-cloud/vars.sh borg-cloud/Makefile borg-cloud/02-k3s/install-k3s.sh borg-cloud/07-edge/
git commit -m "borg-cloud: disable Traefik and servicelb via k3s config (edge step 07, part 1)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: kube-vip and HAProxy on the VIP

**Files:**
- Modify: `borg-cloud/07-edge/edge-lib.sh` (add `haproxy_ready`), `borg-cloud/07-edge/install-edge.sh`

**Interfaces:**
- Consumes: Task 1 helpers; `edge-test.sh vip`.
- Produces: `haproxy_ready`: 0 when Deployment `haproxy-kubernetes-ingress` has 2 available replicas, the Service's load-balancer IP is `$VIP_ADDRESS`, and `http://$VIP_ADDRESS/` answers.

- [ ] **Step 1: Run the failing test**

Run: `cd borg-cloud && bash 07-edge/edge-test.sh vip; echo "exit=$?"`
Expected: `FAIL  http://192.168.56.120/ does not answer`, `FAIL  VIP holders: '' (want exactly one)`, `FAIL  IngressClass haproxy is not the default`, `exit=1`.

- [ ] **Step 2: Add `haproxy_ready` to `edge-lib.sh`**

Append to `borg-cloud/07-edge/edge-lib.sh`:

```bash

# haproxy_ready: 2 HAProxy replicas available, the Service holds the VIP, and the
# VIP answers HTTP
haproxy_ready() {
    local avail lbip
    avail=$(kubectl -n "$HAPROXY_NAMESPACE" get deployment haproxy-kubernetes-ingress \
        -o jsonpath='{.status.availableReplicas}' 2>/dev/null) || return 1
    [ "$avail" = 2 ] || return 1
    lbip=$(kubectl -n "$HAPROXY_NAMESPACE" get service haproxy-kubernetes-ingress \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) || return 1
    [ "$lbip" = "$VIP_ADDRESS" ] || return 1
    [ "$(http_code "http://$VIP_ADDRESS/")" != 000 ]
}
```

- [ ] **Step 3: Install kube-vip and HAProxy in `install-edge.sh`**

In `borg-cloud/07-edge/install-edge.sh`, add these functions after `disable_traefik() { ... }`:

```bash
install_kube_vip() {
    echo ">>> kube-vip (services mode, ARP on $CLUSTER_IFACE)"
    helm repo add kube-vip https://kube-vip.github.io/helm-charts --force-update >/dev/null
    helm repo update kube-vip >/dev/null
    helm upgrade --install kube-vip kube-vip/kube-vip \
        --version "$KUBE_VIP_CHART_VERSION" --namespace kube-system \
        --set-string env.vip_interface="$CLUSTER_IFACE" \
        --set-string env.vip_arp=true \
        --set-string env.svc_enable=true \
        --set-string env.svc_election=true \
        --set-string env.cp_enable=false \
        --set-string env.lb_enable=false \
        --wait --timeout "${DB_WAIT_TIMEOUT}s"
}

install_haproxy() {
    local svclb
    svclb=$(kubectl -n kube-system get pods --no-headers -o custom-columns=N:.metadata.name 2>/dev/null || true)
    ! grep -q '^svclb-' <<<"$svclb" || die "servicelb pods still running; they would claim ports 80/443"
    echo ">>> HAProxy ingress (2 replicas) on $VIP_ADDRESS"
    helm repo add haproxytech https://haproxytech.github.io/helm-charts --force-update >/dev/null
    helm repo update haproxytech >/dev/null
    helm upgrade --install haproxy haproxytech/kubernetes-ingress \
        --version "$HAPROXY_CHART_VERSION" --namespace "$HAPROXY_NAMESPACE" --create-namespace \
        --set controller.replicaCount=2 \
        --set controller.ingressClassResource.default=true \
        --set controller.service.type=LoadBalancer \
        --set-string "controller.service.annotations.kube-vip\.io/loadbalancerIPs=$VIP_ADDRESS" \
        --set controller.service.loadBalancerIP="$VIP_ADDRESS" \
        --set controller.service.enablePorts.quic=false \
        --set controller.service.enablePorts.stat=false \
        --set controller.service.enablePorts.admin=false \
        --set controller.resources.requests.cpu=50m \
        --set controller.resources.requests.memory="$HAPROXY_MEMORY_REQUEST" \
        --set controller.resources.limits.memory="$HAPROXY_MEMORY_LIMIT" \
        --set-json 'controller.affinity={"podAntiAffinity":{"preferredDuringSchedulingIgnoredDuringExecution":[{"weight":100,"podAffinityTerm":{"topologyKey":"kubernetes.io/hostname","labelSelector":{"matchLabels":{"app.kubernetes.io/name":"kubernetes-ingress"}}}}]}}' \
        --wait --timeout "${DB_WAIT_TIMEOUT}s"
    WAIT_NAMESPACE=$HAPROXY_NAMESPACE wait_for "HAProxy answering on $VIP_ADDRESS" haproxy_ready
}
```

Replace the main block at the end:

```bash
preflight
disable_traefik
echo ">>> Edge ready."
```

with:

```bash
preflight
disable_traefik
install_kube_vip
install_haproxy
echo ">>> Edge ready: http://$VIP_ADDRESS/ (HAProxy; default IngressClass haproxy)"
```

Run: `cd borg-cloud && shellcheck -S warning -e SC1091 07-edge/*.sh && helm template kv kube-vip/kube-vip --version 0.11.1 -n kube-system --set-string env.vip_interface=enp0s8 --set-string env.svc_election=true --set-string env.lb_enable=false | grep -A1 -E 'name: (vip_interface|svc_election|lb_enable|cp_enable)$'`
Expected: shellcheck silent; the rendered DaemonSet env shows `vip_interface` = `enp0s8`, `svc_election` = `"true"`, `lb_enable` = `"false"`, `cp_enable` = `"false"`. If a name is missing from the render, STOP and read `helm show values kube-vip/kube-vip --version 0.11.1`: the value names must be the chart's own.

- [ ] **Step 4: Install**

Run: `cd borg-cloud && make provision-edge`
Expected: three `up to date` lines (no k3s restarts), `kube-vip ...` and `HAProxy ...` releases deployed, `HAProxy answering on 192.168.56.120: ready`, `Edge ready: http://192.168.56.120/`.

Run: `KUBECONFIG=~/.kube/config-borg kubectl -n haproxy-controller get pods -o wide && KUBECONFIG=~/.kube/config-borg kubectl -n haproxy-controller get svc haproxy-kubernetes-ingress`
Expected: 2 `Running` HAProxy pods (on different nodes if possible); the Service is `LoadBalancer` with `EXTERNAL-IP 192.168.56.120` and ports `80` and `443` only.

- [ ] **Step 5: Run the test to confirm it passes**

Run: `cd borg-cloud && make edge-test`
Expected: all `k3s` and `vip` checks `PASS`, including `http://192.168.56.120/ answers (404)` (HAProxy's default backend) and `held by exactly one node: k3s-nodeN`; `edge-test: all checks passed`.

- [ ] **Step 6: Commit**

```bash
git add borg-cloud/07-edge/
git commit -m "borg-cloud: kube-vip + HAProxy ingress on VIP 192.168.56.120 (edge step 07, part 2)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: media-service on the VIP, and the failover test

**Files:**
- Modify: `charts/media-service/values-borg.yaml`, `borg-cloud/05-media/media-test.sh`, `borg-cloud/05-media/deploy-media.sh`, `borg-cloud/Makefile`
- Create: `borg-cloud/07-edge/edge-failover-test.sh`

**Interfaces:**
- Consumes: `vip_holders`, `http_code`, `node_back`, `haproxy_ready` (Tasks 1–2); `05-media/media-test.sh`; `make deploy-media TAG= SKIP_BUILD=1`.
- Produces: `media-test.sh` targets `$VIP_ADDRESS`; `make edge-failover-test`.

- [ ] **Step 1: Write the failing test: point `media-test` at the VIP**

In `borg-cloud/05-media/media-test.sh`:
- after `source 03-databases/lib.sh`, add `source 07-edge/edge-lib.sh`
- replace the whole `for ip in $ALL_IPS; do ... done` block with:

```bash
code=$(curl -s -m 10 -o "$body" -w '%{http_code}' "http://$VIP_ADDRESS/api/media" || true)
if [ "$code" = 200 ] && head -c1 "$body" | grep -q '\['; then
    ok "GET http://$VIP_ADDRESS/api/media -> 200 (JSON array)"
else
    bad "GET http://$VIP_ADDRESS/api/media -> $code"
fi
```

- replace `"http://$NODE1_IP/api/media" || true)` with `"http://$VIP_ADDRESS/api/media" || true)`, and `via $NODE1_IP` with `via $VIP_ADDRESS` (twice)
- replace the GET-by-title block with:

```bash
out=$(curl -s -m 10 "http://$VIP_ADDRESS/api/media/$token" || true)
if grep -q "\"title\":\"$token\"" <<<"$out"; then
    ok "GET by title via $VIP_ADDRESS returns the record (stored in MongoDB)"
else
    bad "GET by title via $VIP_ADDRESS did not return the record"
fi
```

- update the header comment: `HTTP checks against media-service through HAProxy on the VIP.`

Run: `cd borg-cloud && make media-test; echo "exit=$?"`
Expected: `FAIL  GET http://192.168.56.120/api/media -> 404` (HAProxy has no route: the Ingress still says class `traefik`), `FAIL  POST via 192.168.56.120 -> 404`, `FAIL  GET by title ...`, non-zero exit.

- [ ] **Step 2: Switch media-service to HAProxy**

In `charts/media-service/values-borg.yaml`:
- change `  className: traefik` to `  className: haproxy`
- in the header comment, change `#   - Traefik (k3s built-in): http://<any node IP>/api/media` to `#   - HAProxy ingress on the VIP (make provision-edge): http://192.168.56.120/api/media`

In `borg-cloud/05-media/deploy-media.sh`:
- after `source 04-registry/registry-lib.sh`, add `source 07-edge/edge-lib.sh`
- change `echo "    http://$NODE1_IP/api/media   (any node IP works; check: make media-test)"` to `echo "    http://$VIP_ADDRESS/api/media   (check: make media-test)"`

In `borg-cloud/Makefile`, in `media-status`, change `@echo "URL: http://$(NODE1_IP)/api/media  (any node IP)"` to `@echo "URL: http://$(VIP_ADDRESS)/api/media"`.

Run:
```bash
cd borg-cloud && export KUBECONFIG=~/.kube/config-borg
tag=$(kubectl -n media get deploy media-service -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's/.*://')
make deploy-media TAG=$tag SKIP_BUILD=1 | tail -2
kubectl -n media get ingress media-service
```
Expected: `>>> Deployed localhost:5050/media3:<tag>`, `http://192.168.56.120/api/media`; the Ingress shows `CLASS haproxy` and `ADDRESS 192.168.56.120`.

- [ ] **Step 3: Run the test to confirm it passes**

Run: `cd borg-cloud && make media-test`
Expected: `PASS  GET http://192.168.56.120/api/media -> 200 (JSON array)`, `PASS  POST via 192.168.56.120 -> 201`, `PASS  GET by title via 192.168.56.120 returns the record ...`, `media-test: all checks passed`.

- [ ] **Step 4: Create `borg-cloud/07-edge/edge-failover-test.sh`**

```bash
#!/bin/bash
# =============================================================================
# 07-edge/edge-failover-test.sh
# DISRUPTIVE: freezes the VM holding the VIP (VBoxManage pause), checks that
# another node takes the VIP and HAProxy still answers on it (and media-service,
# unless its only pod was on the frozen node), then resumes the VM. A trap
# always resumes it.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh
source 07-edge/edge-lib.sh

command -v VBoxManage >/dev/null || die "VBoxManage not found on PATH"
haproxy_ready || die "edge not ready (run: make provision-edge)"

holders=$(vip_holders)
[ "$(grep -c . <<<"$holders")" = 1 ] || die "expected exactly one VIP holder, got: $holders"
frozen=$holders
frozen_ip=""
for i in 1 2 3; do
    name_var="NODE${i}_NAME"; ip_var="NODE${i}_IP"
    [ "${!name_var}" = "$frozen" ] && frozen_ip=${!ip_var}
done
# Talk to the API through a node that stays up (node1 may be the one frozen)
alive_ip=$NODE1_IP
[ "$frozen_ip" = "$NODE1_IP" ] && alive_ip=$NODE2_IP
tmpkc=$(mktemp)
sed "s|https://[0-9.]*:6443|https://$alive_ip:6443|" "$KUBECONFIG_OUT" > "$tmpkc"
export KUBECONFIG=$tmpkc

resume() {
    VBoxManage controlvm "$frozen" resume 2>/dev/null || true
    rm -f "$tmpkc"
}
trap resume EXIT

media_node=$(kubectl -n "$MEDIA_NAMESPACE" get pods -l app.kubernetes.io/instance="$MEDIA_RELEASE" \
    -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || true)

echo ">>> Freezing $frozen ($frozen_ip), which holds $VIP_ADDRESS"
VBoxManage controlvm "$frozen" pause

moved() { local h; h=$(vip_holders "$frozen_ip"); [ "$(grep -c . <<<"$h")" = 1 ]; }
WAIT_NAMESPACE=$HAPROXY_NAMESPACE wait_for "VIP on another node" moved
echo "    VIP now on: $(vip_holders "$frozen_ip")"

vip_answers() { [ "$(http_code "http://$VIP_ADDRESS/")" != 000 ]; }
WAIT_NAMESPACE=$HAPROXY_NAMESPACE wait_for "HAProxy answering on $VIP_ADDRESS" vip_answers

if [ "$media_node" = "$frozen" ]; then
    echo "    media-service's only pod is on the frozen node: skipping media-test (expected outage)"
else
    retry 30 bash 05-media/media-test.sh >/dev/null || die "media-test failed through the moved VIP"
    echo "    media-test passed through the moved VIP"
fi

echo ">>> Resuming $frozen"
VBoxManage controlvm "$frozen" resume
all_ready() { [ "$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 == "Ready"' | wc -l)" -eq 3 ]; }
WAIT_NAMESPACE=kube-system wait_for "3 nodes Ready" all_ready
export KUBECONFIG=$KUBECONFIG_OUT
bash 07-edge/edge-test.sh vip | tail -1
echo ">>> edge-failover-test: passed"
```

In `borg-cloud/Makefile`, after `edge-test`, add:

```make

.PHONY: edge-failover-test
edge-failover-test:
	@echo "WARNING: This freezes the VM holding the VIP for about a minute. Ctrl-C to abort."
	@sleep 3
	bash 07-edge/edge-failover-test.sh
```

Run: `cd borg-cloud && shellcheck -S warning -e SC1091 07-edge/*.sh 05-media/*.sh`
Expected: no output.

- [ ] **Step 5: Run the failover test (Review Focus 3 and 4)**

Run: `cd borg-cloud && make edge-failover-test`
Expected: `Freezing k3s-nodeN ...`, `VIP on another node: ready`, `VIP now on: k3s-nodeM` (M ≠ N), `HAProxy answering on 192.168.56.120: ready`, then either `media-test passed through the moved VIP` or the skip line; `Resuming ...`, `3 nodes Ready: ready`, `edge-test: all checks passed`, `>>> edge-failover-test: passed`.

Then: `cd borg-cloud && make db-test | tail -1 && make kafka-test | tail -1 && make media-test | tail -1`
Expected: all pass.

Run: `VBoxManage list runningvms | grep -c k3s-node && VBoxManage showvminfo k3s-node1 --machinereadable | grep VMState=`
Expected: `3`, and `VMState="running"` (no VM left paused).

- [ ] **Step 6: Commit**

```bash
git add charts/media-service/values-borg.yaml borg-cloud/05-media/media-test.sh borg-cloud/05-media/deploy-media.sh borg-cloud/Makefile borg-cloud/07-edge/edge-failover-test.sh
git commit -m "borg-cloud: media-service on the HAProxy VIP; edge failover test

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `make up`, help, idempotency

**Files:**
- Modify: `borg-cloud/Makefile`

- [ ] **Step 1: Write the failing check**

Run: `cd borg-cloud && make -n up | grep -c install-edge.sh`
Expected: `0`.

- [ ] **Step 2: Wire `make up` and help**

Change `up: vagrant-up cluster provision-databases provision-registry provision-kafka` to:

```make
up: vagrant-up cluster provision-edge provision-databases provision-registry provision-kafka
```

In `help`, change `Everything: vagrant-up + cluster + databases + registry + kafka` to `Everything: vagrant-up + cluster + edge + databases + registry + kafka`. After the line `make cluster             2. Base OS prep + k3s HA install + kubeconfig`, add:

```make
	@echo "  make provision-edge      2b. VIP $(VIP_ADDRESS) + HAProxy ingress (replaces Traefik)"
```

Before `@echo "  Databases (namespace $(DB_NAMESPACE), one member per node):"`, insert:

```make
	@echo "  Edge (VIP $(VIP_ADDRESS); step 07-edge):"
	@echo "  make provision-edge      Disable Traefik/servicelb, kube-vip + HAProxy on the VIP"
	@echo "  make edge-test           VIP answers, one holder, Traefik gone, node :80 closed"
	@echo "  make edge-failover-test  Freeze the VIP holder's VM; VIP moves (disruptive)"
	@echo ""
```

Run: `cd borg-cloud && make -n up | grep -c install-edge.sh && make help | grep -c 'edge'`
Expected: `1`, then `5` or more.

- [ ] **Step 3: Re-running changes nothing (Review Focus 2)**

Run:
```bash
cd borg-cloud && source ./vars.sh
starts() { for ip in $ALL_IPS; do ssh_node "$ip" 'systemctl show -p ActiveEnterTimestamp --value k3s'; done; }
before=$(starts); make provision-edge | grep -E 'up to date|restarting|Edge ready'; after=$(starts)
[ "$before" = "$after" ] && echo "NO K3S RESTARTS" || diff <(echo "$before") <(echo "$after")
```
Expected: three `up to date` lines, `Edge ready: http://192.168.56.120/ ...`, and `NO K3S RESTARTS`.

- [ ] **Step 4: Commit**

```bash
git add borg-cloud/Makefile
git commit -m "borg-cloud: include the edge in make up; document edge targets

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Acceptance run and PR

- [ ] **Step 1: Full check**

Run:
```bash
cd borg-cloud && export KUBECONFIG=~/.kube/config-borg
for t in edge-test media-test db-test kafka-test registry-test; do make $t 2>&1 | grep -E 'test: '; done
kubectl top nodes
kubectl -n haproxy-controller get pods -o jsonpath='{range .items[*]}{.metadata.name} restarts={.status.containerStatuses[0].restartCount}{"\n"}{end}'
```
Expected: every suite ends with `passed`; node memory below about 85% (if not, **stop and ask the user**); HAProxy pods `restarts=0`.

- [ ] **Step 2: Push and open the PR (the user merges)**

```bash
git push -u origin edge-haproxy-vip
gh pr create --base main --head edge-haproxy-vip \
  --title "BorgCloud edge: HAProxy on a floating VIP, replacing Traefik (#12 part 1)" \
  --body "<body>"
```

The body must contain:
- `Part of #12 (part 1 of 2). Part of #1.` (not `Closes`: part 2, Kafka TLS/SNI, remains)
- links to the spec and plan
- the targets
- the new media URL `http://192.168.56.120/api/media`
- that `provision-edge` rolls k3s once on existing clusters and media-service needs `make deploy-media SKIP_BUILD=1 TAG=<current>` after migrating
- the actual results from Tasks 1–5, including `kubectl top nodes`
- `🤖 Generated with [Claude Code](https://claude.com/claude-code)`

Do not merge.
