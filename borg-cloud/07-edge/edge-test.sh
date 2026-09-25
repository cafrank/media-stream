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
