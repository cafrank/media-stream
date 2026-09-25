#!/bin/bash
# =============================================================================
# 06-kafka/install-kafka.sh
# Runs from HOST. Installs the 3-broker Kafka cluster (namespace $KAFKA_NAMESPACE).
# Safe to re-run: kubectl apply, and the cluster ID Secret is never regenerated
# (a new ID would make every broker refuse its formatted volume).
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh
source 06-kafka/kafka-lib.sh
source 06-kafka/kafka-tls.sh
source 07-edge/edge-lib.sh

preflight
# External access goes through HAProxy on the VIP (make provision-edge)
if ! kubectl get ingressclass haproxy >/dev/null 2>&1 || [ "$(http_code "http://$VIP_ADDRESS/")" = 000 ]; then
    die "the edge (HAProxy on $VIP_ADDRESS) is not installed (run: make provision-edge)"
fi

kubectl create namespace "$KAFKA_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
if kk get secret kafka-cluster-id >/dev/null 2>&1; then
    echo "    secret/kafka-cluster-id exists (kept)"
else
    # Kafka cluster ID: 16 random bytes, base64url without padding (22 chars)
    id=$(openssl rand 16 | base64 | tr '+/' '-_' | tr -d '=')
    kk create secret generic kafka-cluster-id --from-literal=id="$id" >/dev/null
    echo "    secret/kafka-cluster-id created"
fi

tls_work=$(mktemp -d)
trap 'rm -rf "$tls_work"' EXIT
echo ">>> Kafka TLS (CA + broker certificate for $(kafka_names))"
ensure_kafka_tls "$tls_work"

echo ">>> Kafka: StatefulSet kafka (3 brokers, $KAFKA_IMAGE)"
# A reissued broker certificate changes the pod template, so the brokers roll
KAFKA_TLS_SHA=$(kk get secret kafka-tls -o jsonpath='{.data.tls\.crt}' | sha256sum | cut -c1-16)
KAFKA_SCRIPTS_SHA=$(kafka_scripts_sha 06-kafka/kafka.yaml)
render_kafka 06-kafka/kafka.yaml | kubectl apply -f -
# A changed pod template rolls the brokers one at a time; wait for that to finish
# (the old pods would otherwise still count as 3 Ready)
kk rollout status statefulset kafka --timeout=900s
WAIT_NAMESPACE=$KAFKA_NAMESPACE wait_for "3 Kafka brokers Ready" kafka_pods_ready
WAIT_NAMESPACE=$KAFKA_NAMESPACE wait_for "controller quorum (leader + 3 voters)" kafka_quorum_ok
echo ">>> Kafka ready: kafka-bootstrap.$KAFKA_NAMESPACE.svc.cluster.local:9092 (in-cluster),"
echo "    $KAFKA_DOMAIN:443 via $VIP_ADDRESS (host, TLS: make kafka-ca, make kafka-hosts). Test it: make kafka-test"
