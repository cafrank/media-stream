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

preflight
disable_traefik
install_kube_vip
install_haproxy
echo ">>> Edge ready: http://$VIP_ADDRESS/ (HAProxy; default IngressClass haproxy)"
