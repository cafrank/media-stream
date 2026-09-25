#!/bin/bash
# =============================================================================
# 01-base/setup-base.sh
# Runs from HOST. Applies OS prerequisites for k3s to all nodes in parallel.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh

SCRIPT=$(mktemp /tmp/borg-base.XXXXXX.sh)
trap 'rm -f "$SCRIPT"' EXIT

cat > "$SCRIPT" <<'REMOTE'
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "=== Base: packages ==="
apt-get update -qq
apt-get install -y -qq curl jq nfs-common open-iscsi ca-certificates >/dev/null

# VirtualBox guest clocks here run ~4% off real time. systemd-timesyncd can only
# fix that by stepping the clock (~1.4s every ~30s), which puts Redis Sentinel
# into TILT mode (no failover) and makes etcd report clock drift. chrony slews
# and learns the frequency error instead; installing it replaces timesyncd.
echo "=== Base: chrony (time sync) ==="
apt-get install -y -qq chrony >/dev/null
systemctl enable --now chrony >/dev/null

echo "=== Base: disable swap ==="
swapoff -a
sed -i '/\bswap\b/s/^/#/' /etc/fstab

echo "=== Base: kernel modules ==="
cat > /etc/modules-load.d/k3s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

echo "=== Base: sysctl ==="
cat > /etc/sysctl.d/99-k3s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
fs.inotify.max_user_watches         = 524288
fs.inotify.max_user_instances       = 512
EOF
sysctl --system -q

echo "=== Base: disable ufw ==="
systemctl disable --now ufw 2>/dev/null || true

echo "=== Base: $(hostname -s) done ==="
REMOTE

pids=()
for ip in $ALL_IPS; do
    ( run_on "$ip" "$SCRIPT" 2>&1 | sed "s/^/[$ip] /" ) &
    pids+=($!)
done

rc=0
for pid in "${pids[@]}"; do wait "$pid" || rc=1; done
exit $rc
