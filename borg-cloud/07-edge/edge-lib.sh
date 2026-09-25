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

# traefik_gone: no Traefik or svclb pods, no bundled Traefik HelmCharts, and no
# traefik Service (a LoadBalancer Service left Terminating is still tracked by
# kube-vip and keeps kube-proxy REJECT rules on the node IPs)
traefik_gone() {
    local pods charts
    pods=$(kubectl -n kube-system get pods --no-headers -o custom-columns=N:.metadata.name 2>/dev/null) || return 1
    charts=$(kubectl -n kube-system get helmcharts.helm.cattle.io --no-headers \
        -o custom-columns=N:.metadata.name 2>/dev/null || true)
    ! grep -qE '^(traefik|svclb-)' <<<"$pods" && ! grep -qxE 'traefik|traefik-crd' <<<"$charts" &&
    ! kubectl -n kube-system get service traefik >/dev/null 2>&1
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
