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

# resync_clock: a paused VM's clock stops, and chrony only notices at its next
# poll (minutes). Make it measure now and step the clock, so the node's API
# server and etcd aren't running tens of seconds behind the rest of the cluster.
resync_clock() {
    retry 30 ssh_node "$frozen_ip" true 2>/dev/null || return 0
    ssh_node "$frozen_ip" 'sudo chronyc burst 4/4 >/dev/null; sleep 12; sudo chronyc makestep >/dev/null' || true
}

resume() {
    VBoxManage controlvm "$frozen" resume 2>/dev/null || true
    resync_clock
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
resync_clock
all_ready() { [ "$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 == "Ready"' | wc -l)" -eq 3 ]; }
WAIT_NAMESPACE=kube-system wait_for "3 nodes Ready" all_ready
export KUBECONFIG=$KUBECONFIG_OUT
bash 07-edge/edge-test.sh vip | tail -1
echo ">>> edge-failover-test: passed"
