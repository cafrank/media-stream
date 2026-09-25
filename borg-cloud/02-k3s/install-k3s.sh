#!/bin/bash
# =============================================================================
# 02-k3s/install-k3s.sh
# Runs from HOST. Installs a 3-server HA k3s cluster with embedded etcd:
#   node1: server --cluster-init
#   node2/3: server --server https://node1:6443
# Then fetches the kubeconfig to $KUBECONFIG_OUT.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh

if [ ! -s "$K3S_TOKEN_FILE" ]; then
    echo ">>> Generating cluster token ($K3S_TOKEN_FILE)..."
    (umask 077; openssl rand -hex 32 > "$K3S_TOKEN_FILE")
fi
K3S_TOKEN=$(cat "$K3S_TOKEN_FILE")

# install_server <node-ip> [join-ip]
install_server() {
    local ip=$1 join=${2:-}
    local init_arg="--cluster-init"
    [ -n "$join" ] && init_arg="--server https://$join:6443"

    ssh_node "$ip" "sudo env \
        INSTALL_K3S_VERSION='$K3S_VERSION' \
        K3S_TOKEN='$K3S_TOKEN' \
        sh -c 'curl -sfL https://get.k3s.io | sh -s - server \
            $init_arg \
            --node-ip $ip \
            --advertise-address $ip \
            --flannel-iface $CLUSTER_IFACE \
            --tls-san $ip --tls-san $NODE1_IP --tls-san $NODE2_IP --tls-san $NODE3_IP \
            --cluster-cidr $K3S_CLUSTER_CIDR \
            --service-cidr $K3S_SERVICE_CIDR \
            --write-kubeconfig-mode 644'"
}

wait_ready() {
    local ip=$1
    echo ">>> Waiting for $ip to report Ready..."
    for _ in $(seq 1 60); do
        if ssh_node "$NODE1_IP" "sudo k3s kubectl get nodes -o wide 2>/dev/null" \
                | awk -v ip="$ip" '$6 == ip && $2 == "Ready" {found=1} END {exit !found}'; then
            return 0
        fi
        sleep 5
    done
    echo "ERROR: $ip did not become Ready" >&2
    return 1
}

echo ">>> [1/3] Bootstrapping $NODE1_NAME ($NODE1_IP) with --cluster-init..."
install_server "$NODE1_IP"
wait_ready "$NODE1_IP"

# etcd members must join one at a time
echo ">>> [2/3] Joining $NODE2_NAME ($NODE2_IP)..."
install_server "$NODE2_IP" "$NODE1_IP"
wait_ready "$NODE2_IP"

echo ">>> [3/3] Joining $NODE3_NAME ($NODE3_IP)..."
install_server "$NODE3_IP" "$NODE1_IP"
wait_ready "$NODE3_IP"

echo ">>> Fetching kubeconfig → $KUBECONFIG_OUT"
mkdir -p "$(dirname "$KUBECONFIG_OUT")"
ssh_node "$NODE1_IP" "cat /etc/rancher/k3s/k3s.yaml" \
    | sed -e "s|https://127.0.0.1:6443|https://$NODE1_IP:6443|" \
          -e "s|: default$|: borg|" \
    > "$KUBECONFIG_OUT"
chmod 600 "$KUBECONFIG_OUT"

ssh_node "$NODE1_IP" "sudo k3s kubectl get nodes -o wide"
