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
