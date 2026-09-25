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

# mirror_loaded <ip>: the running k3s has loaded this node's mirror (k3s writes the
# containerd hosts.toml from registries.yaml at startup), so a file written by an
# interrupted run, without the restart that follows, doesn't count as up to date
mirror_loaded() {
    ssh_node "$1" "sudo grep -qF '[host.\"http://$1:$REGISTRY_NODEPORT/v2\"]' \
        '/var/lib/rancher/k3s/agent/etc/containerd/certs.d/localhost:$REGISTRY_LOCAL_PORT/hosts.toml'" 2>/dev/null
}

echo ">>> Node mirrors: localhost:$REGISTRY_LOCAL_PORT -> <node IP>:$REGISTRY_NODEPORT"
for i in 1 2 3; do
    name_var="NODE${i}_NAME"; ip_var="NODE${i}_IP"
    name=${!name_var}; ip=${!ip_var}
    export NODE_IP=$ip
    want=$(render_registry 04-registry/registries.yaml)
    have=$(ssh_node "$ip" 'sudo cat /etc/rancher/k3s/registries.yaml 2>/dev/null' || true)
    if [ "$want" = "$have" ]; then
        if mirror_loaded "$ip"; then
            echo "    $name: up to date"
            continue
        fi
        echo "    $name: registries.yaml written but not loaded, restarting k3s"
    else
        echo "    $name: writing registries.yaml, restarting k3s"
        printf '%s\n' "$want" | ssh_node "$ip" 'sudo tee /etc/rancher/k3s/registries.yaml >/dev/null'
    fi
    ssh_node "$ip" 'sudo systemctl restart k3s'
    WAIT_NAMESPACE=kube-system wait_for "$name back after k3s restart" node_back "$name" "$ip"
done
echo ">>> Registry ready. Test it: make registry-test"
