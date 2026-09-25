#!/bin/bash
# =============================================================================
# 06-kafka/kafka-failover-test.sh [all|one-down|full-restart]
# DISRUPTIVE.
#   one-down:     delete kafka-2; acks=all writes and reads keep working through
#                 kafka-0 (2 in-sync replicas remain); kafka-2 rejoins.
#   full-restart: delete all 3 brokers at once (as a VM halt/start does); the
#                 quorum re-forms and a message written before is still there.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh
source 06-kafka/kafka-lib.sh

TOPIC=borg-kafka-test
kafka_pods_ready || die "Kafka is not installed or not Ready (run: make provision-kafka)"
kbin kafka-0 kafka-topics.sh --bootstrap-server localhost:9092 --create --if-not-exists \
    --topic "$TOPIC" --partitions 3 --replication-factor 3 --config min.insync.replicas=2 >/dev/null

produce() { # produce <pod> <message>
    echo "$2" | kk exec -i "$1" -c kafka -- /opt/kafka/bin/kafka-console-producer.sh \
        --bootstrap-server localhost:9092 --topic "$TOPIC" --producer-property acks=all >/dev/null 2>&1
}
consumed() { # consumed <pod> <message>: the topic contains the message
    local out   # captured first: `cmd | grep -q` under pipefail can fail on SIGPIPE
    out=$(kbin "$1" kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic "$TOPIC" \
        --from-beginning --timeout-ms 20000 2>/dev/null || true)
    grep -qx "$2" <<<"$out"
}
pod_uid() { kk get pod "$1" -o jsonpath='{.metadata.uid}' 2>/dev/null; }
# pod_down <pod> <old uid>: the pod was replaced or is not Ready
pod_down() {
    [ "$(pod_uid "$1")" != "$2" ] ||
    [ "$(kk get pod "$1" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)" != true ]
}

one_down() {
    local uid token
    uid=$(pod_uid kafka-2)
    echo ">>> Kafka: deleting kafka-2"
    kk delete pod kafka-2 --wait=false >/dev/null
    WAIT_NAMESPACE=$KAFKA_NAMESPACE wait_for "kafka-2 down" pod_down kafka-2 "$uid"
    token="one-down-$(date +%s)-$RANDOM"
    produce kafka-0 "$token" || die "Kafka: acks=all produce failed with one broker down"
    consumed kafka-0 "$token" || die "Kafka: message written with one broker down was not read back"
    echo "    acks=all write and read worked with one broker down"
    WAIT_NAMESPACE=$KAFKA_NAMESPACE wait_for "3 brokers Ready" kafka_pods_ready
    WAIT_NAMESPACE=$KAFKA_NAMESPACE wait_for "every partition back to 3 in-sync replicas" topic_isr_full "$TOPIC"
}

full_restart() {
    local token
    token="before-restart-$(date +%s)-$RANDOM"
    produce kafka-0 "$token" || die "Kafka: produce before restart failed"
    echo ">>> Kafka: deleting all 3 brokers at once"
    kk delete pod kafka-0 kafka-1 kafka-2 --wait=true >/dev/null
    WAIT_NAMESPACE=$KAFKA_NAMESPACE wait_for "3 brokers Ready" kafka_pods_ready
    WAIT_NAMESPACE=$KAFKA_NAMESPACE wait_for "controller quorum (leader + 3 voters)" kafka_quorum_ok
    WAIT_NAMESPACE=$KAFKA_NAMESPACE wait_for "every partition back to 3 in-sync replicas" topic_isr_full "$TOPIC"
    consumed kafka-1 "$token" || die "Kafka: message written before the restart is gone"
    echo "    quorum re-formed; message written before the restart is still there"
}

target=${1:-all}
case "$target" in
    all)          one_down; full_restart ;;
    one-down)     one_down ;;
    full-restart) full_restart ;;
    *) die "usage: $0 [all|one-down|full-restart]" ;;
esac
bash 06-kafka/kafka-test.sh
echo ">>> kafka-failover-test: passed"
