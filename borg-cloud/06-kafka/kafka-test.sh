#!/bin/bash
# =============================================================================
# 06-kafka/kafka-test.sh
# Non-destructive checks: a replicated test topic, produce/consume inside the
# cluster (INTERNAL listener) and from the host (EXTERNAL listener, <node IP>:9094,
# via a throwaway container of the Kafka image), and topic auto-creation defaults.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh
source 06-kafka/kafka-lib.sh

TOPIC=borg-kafka-test
fail=0
ok()  { echo "  PASS  $*"; }
bad() { echo "  FAIL  $*"; fail=1; }

kafka_pods_ready || die "Kafka is not installed or not Ready (run: make provision-kafka)"

# host_kafka <script> <args...>: a Kafka CLI tool on the host, through the EXTERNAL listener
host_kafka() {
    docker run --rm -i --network host --entrypoint "/opt/kafka/bin/$1" "$KAFKA_IMAGE" "${@:2}"
}

echo ">>> Topic $TOPIC"
kbin kafka-0 kafka-topics.sh --bootstrap-server localhost:9092 --create --if-not-exists \
    --topic "$TOPIC" --partitions 3 --replication-factor 3 --config min.insync.replicas=2 >/dev/null
if retry 15 topic_isr_full "$TOPIC"; then
    ok "every partition has 3 in-sync replicas"
else
    bad "partitions without 3 in-sync replicas"
fi

echo ">>> In-cluster (INTERNAL listener)"
token="in-cluster-$(date +%s)-$RANDOM"
if echo "$token" | kk exec -i kafka-0 -c kafka -- /opt/kafka/bin/kafka-console-producer.sh \
        --bootstrap-server localhost:9092 --topic "$TOPIC" --producer-property acks=all >/dev/null 2>&1; then
    ok "produce with acks=all via kafka-0"
else
    bad "produce via kafka-0"
fi
# Capture before grepping: under pipefail, `cmd | grep -q` fails when grep exits
# early and the writer gets SIGPIPE, even though the match was found.
out=$(kbin kafka-1 kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic "$TOPIC" \
        --from-beginning --timeout-ms 15000 2>/dev/null || true)
if grep -qx "$token" <<<"$out"; then
    ok "consume via kafka-1"
else
    bad "consume via kafka-1 did not return the message"
fi

echo ">>> From the host (EXTERNAL listener, port $KAFKA_EXTERNAL_PORT)"
token="host-$(date +%s)-$RANDOM"
if echo "$token" | host_kafka kafka-console-producer.sh --bootstrap-server "$NODE1_IP:$KAFKA_EXTERNAL_PORT" \
        --topic "$TOPIC" --producer-property acks=all >/dev/null 2>&1; then
    ok "produce from host via $NODE1_IP:$KAFKA_EXTERNAL_PORT"
else
    bad "produce from host via $NODE1_IP:$KAFKA_EXTERNAL_PORT"
fi
out=$(host_kafka kafka-console-consumer.sh --bootstrap-server "$NODE3_IP:$KAFKA_EXTERNAL_PORT" --topic "$TOPIC" \
        --from-beginning --timeout-ms 20000 2>/dev/null || true)
if grep -qx "$token" <<<"$out"; then
    ok "consume from host via $NODE3_IP:$KAFKA_EXTERNAL_PORT (all 3 partition leaders reachable)"
else
    bad "consume from host via $NODE3_IP:$KAFKA_EXTERNAL_PORT did not return the message"
fi

echo ">>> Auto-created topic defaults"
auto="borg-kafka-auto-$(date +%s)"
echo "x" | kk exec -i kafka-0 -c kafka -- /opt/kafka/bin/kafka-console-producer.sh \
    --bootstrap-server localhost:9092 --topic "$auto" >/dev/null 2>&1 || true
desc=$(kbin kafka-0 kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic "$auto" 2>/dev/null || true)
if echo "$desc" | grep -q 'ReplicationFactor: 3'; then
    ok "auto-created topic has 3 replicas"
else
    bad "auto-created topic: $(echo "$desc" | head -1)"
fi
# A topic only lists min.insync.replicas when it overrides the broker default,
# so check the broker default itself
out=$(kbin kafka-0 kafka-configs.sh --bootstrap-server localhost:9092 --entity-type brokers \
        --entity-name 0 --describe --all 2>/dev/null || true)
if grep -q 'min.insync.replicas=2 ' <<<"$out"; then
    ok "broker default min.insync.replicas=2"
else
    bad "broker default min.insync.replicas is not 2"
fi
kbin kafka-0 kafka-topics.sh --bootstrap-server localhost:9092 --delete --topic "$auto" >/dev/null 2>&1 || true

if [ "$fail" -eq 0 ]; then
    echo ">>> kafka-test: all checks passed"
else
    echo ">>> kafka-test: FAILED" >&2
    exit 1
fi
