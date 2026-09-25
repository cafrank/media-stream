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

# --- Databases (03-databases) ---
DB_NAMESPACE="databases"
CNPG_NAMESPACE="cnpg-system"
CNPG_CHART_VERSION="0.29.1"                # cnpg/cloudnative-pg -> operator 1.30.1
MONGODB_OPERATOR_CHART_VERSION="1.12.0"    # mongodb/mongodb-kubernetes
PG_IMAGE="ghcr.io/cloudnative-pg/postgresql:17.11"
MONGODB_VERSION="7.0.43"                   # quay.io/mongodb/mongodb-community-server:<v>-ubi8
REDIS_IMAGE="redis:8.10.2-alpine"
DB_STORAGE_SIZE="2Gi"                      # per member, local-path
PG_MEMORY="512Mi"
MONGO_MEMORY="512Mi"
REDIS_MEMORY="256Mi"
SENTINEL_MEMORY="64Mi"
DB_WAIT_TIMEOUT="300"                      # seconds, per readiness wait

# --- Image registry (04-registry) ---
REGISTRY_NAMESPACE="registry"
REGISTRY_IMAGE="registry:3.1.2"
REGISTRY_NODEPORT="30500"
# Host side of the push port-forward; images are named localhost:<port>/<name>.
# Port 5000 on this host is raq-base's registry. Changing this needs
# make provision-registry (it is each node's mirror key).
REGISTRY_LOCAL_PORT="5050"
REGISTRY_STORAGE_SIZE="10Gi"

# --- media-service (05-media) ---
MEDIA_NAMESPACE="media"
MEDIA_RELEASE="media-service"

# --- Kafka (06-kafka) ---
KAFKA_NAMESPACE="kafka"
KAFKA_IMAGE="apache/kafka:4.3.1"
KAFKA_STORAGE_SIZE="5Gi"                   # per broker, local-path
KAFKA_HEAP="384m"                          # JVM -Xms/-Xmx
KAFKA_MEMORY_REQUEST="512Mi"
KAFKA_MEMORY_LIMIT="768Mi"
KAFKA_EXTERNAL_PORT="9094"                 # broker's TLS listener (container port; reached via HAProxy)
KAFKA_DOMAIN="kafka.borg.test"             # host clients: kafka.<domain>, kafka-N.<domain> -> VIP:443 (TLS/SNI)

# --- Edge: floating VIP + HAProxy ingress (07-edge) ---
VIP_ADDRESS="192.168.56.120"               # kube-vip ARP on CLUSTER_IFACE; HAProxy's LoadBalancer IP
KUBE_VIP_CHART_VERSION="0.11.1"            # kube-vip/kube-vip -> kube-vip v1.2.3
HAPROXY_CHART_VERSION="1.54.2"             # haproxytech/kubernetes-ingress -> HAProxy 3.2.15
HAPROXY_NAMESPACE="haproxy-controller"
HAPROXY_MEMORY_REQUEST="64Mi"
HAPROXY_MEMORY_LIMIT="256Mi"

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
