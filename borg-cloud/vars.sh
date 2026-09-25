#!/bin/bash
# =============================================================================
# vars.sh - Shared BorgCloud k3s cluster configuration
# Read by the Vagrantfile, the Makefile and all provisioning scripts:
#   source "$(dirname "$0")/../vars.sh"
# =============================================================================

# --- VirtualBox ---
VBOX_GROUP="/BorgCloud"
VM_BOX="ubuntu/jammy64"
VM_MEMORY="4096"
VM_CPUS="2"

# --- Node IPs (Host-Only network: VirtualBox 192.168.56.0/24) ---
# .101-.103 are used by raq-base; BorgCloud uses .121-.123
NODE1_IP="192.168.56.121"
NODE2_IP="192.168.56.122"
NODE3_IP="192.168.56.123"
NODE1_NAME="k3s-node1"
NODE2_NAME="k3s-node2"
NODE3_NAME="k3s-node3"

# --- Network interface names on VMs ---
# NIC1 = NAT       (internet access,  enp0s3)
# NIC2 = Host-Only (cluster traffic,  enp0s8)
NAT_IFACE="enp0s3"
CLUSTER_IFACE="enp0s8"

# --- SSH user on VMs ---
SSH_USER="ubuntu"
SSH_KEY="$HOME/.ssh/cluster_id_rsa"

# --- k3s ---
# Empty = latest stable channel. Pin e.g. "v1.31.4+k3s1" for reproducible builds.
K3S_VERSION=""
K3S_CLUSTER_CIDR="10.42.0.0/16"
K3S_SERVICE_CIDR="10.43.0.0/16"
K3S_TOKEN_FILE=".k3s-token"            # Generated on first provision (gitignored)
KUBECONFIG_OUT="$HOME/.kube/config-borg"

# --- Derived lists (space-separated for loops) ---
ALL_IPS="$NODE1_IP $NODE2_IP $NODE3_IP"
ALL_NAMES="$NODE1_NAME $NODE2_NAME $NODE3_NAME"

# Helper: SSH to a node
ssh_node() {
    local ip=$1; shift
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR "$SSH_USER@$ip" "$@"
}

# Helper: SCP a file to a node
scp_to() {
    local file=$1; local ip=$2; local dest=$3
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR "$file" "$SSH_USER@$ip:$dest"
}

# Helper: run a script on a remote node as root
run_on() {
    local ip=$1; local script=$2
    scp_to "$script" "$ip" "/tmp/$(basename "$script")"
    ssh_node "$ip" "chmod +x /tmp/$(basename "$script") && sudo /tmp/$(basename "$script")"
}
