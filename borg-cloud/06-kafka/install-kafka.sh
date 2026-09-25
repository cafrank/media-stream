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

preflight

kubectl create namespace "$KAFKA_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
if kk get secret kafka-cluster-id >/dev/null 2>&1; then
    echo "    secret/kafka-cluster-id exists (kept)"
else
    # Kafka cluster ID: 16 random bytes, base64url without padding (22 chars)
    id=$(openssl rand 16 | base64 | tr '+/' '-_' | tr -d '=')
    kk create secret generic kafka-cluster-id --from-literal=id="$id" >/dev/null
    echo "    secret/kafka-cluster-id created"
fi

echo ">>> Kafka: StatefulSet kafka (3 brokers, $KAFKA_IMAGE)"
render_kafka 06-kafka/kafka.yaml | kubectl apply -f -
WAIT_NAMESPACE=$KAFKA_NAMESPACE wait_for "3 Kafka brokers Ready" kafka_pods_ready
WAIT_NAMESPACE=$KAFKA_NAMESPACE wait_for "controller quorum (leader + 3 voters)" kafka_quorum_ok
echo ">>> Kafka ready: kafka-bootstrap.$KAFKA_NAMESPACE.svc.cluster.local:9092 (in-cluster),"
echo "    $NODE1_IP:$KAFKA_EXTERNAL_PORT (host; any node IP). Test it: make kafka-test"
