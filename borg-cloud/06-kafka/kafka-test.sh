#!/bin/bash
# =============================================================================
# 06-kafka/kafka-test.sh [all|cluster|certs|tls|host]
#   cluster: replicated test topic; produce/consume in-cluster (INTERNAL :9092);
#            auto-created topic defaults
#   certs:   Secrets kafka-ca / kafka-tls: the broker certificate verifies against
#            the CA, names exactly the 4 hosts, and matches its key
#   tls:     (Task 2)
#   host:    produce/consume from the host
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
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

test_cluster() {
    local token out auto desc
    echo ">>> Topic $TOPIC"
    kbin kafka-0 kafka-topics.sh --bootstrap-server localhost:9092 --create --if-not-exists \
        --topic "$TOPIC" --partitions 3 --replication-factor 3 --config min.insync.replicas=2 >/dev/null
    if retry 15 topic_isr_full "$TOPIC"; then ok "every partition has 3 in-sync replicas"
    else bad "partitions without 3 in-sync replicas"; fi

    echo ">>> In-cluster (INTERNAL listener)"
    token="in-cluster-$(date +%s)-$RANDOM"
    if echo "$token" | kk exec -i kafka-0 -c kafka -- /opt/kafka/bin/kafka-console-producer.sh \
            --bootstrap-server localhost:9092 --topic "$TOPIC" --producer-property acks=all >/dev/null 2>&1; then
        ok "produce with acks=all via kafka-0"
    else
        bad "produce via kafka-0"
    fi
    out=$(kbin kafka-1 kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic "$TOPIC" \
            --from-beginning --timeout-ms 15000 2>/dev/null || true)
    if grep -qx "$token" <<<"$out"; then ok "consume via kafka-1"
    else bad "consume via kafka-1 did not return the message"; fi

    echo ">>> Auto-created topic defaults"
    auto="borg-kafka-auto-$(date +%s)"
    echo "x" | kk exec -i kafka-0 -c kafka -- /opt/kafka/bin/kafka-console-producer.sh \
        --bootstrap-server localhost:9092 --topic "$auto" >/dev/null 2>&1 || true
    desc=$(kbin kafka-0 kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic "$auto" 2>/dev/null || true)
    if grep -q 'ReplicationFactor: 3' <<<"$desc"; then ok "auto-created topic has 3 replicas"
    else bad "auto-created topic: $(head -1 <<<"$desc")"; fi
    out=$(kbin kafka-0 kafka-configs.sh --bootstrap-server localhost:9092 --entity-type brokers \
            --entity-name 0 --describe --all 2>/dev/null || true)
    if grep -q 'min.insync.replicas=2 ' <<<"$out"; then ok "broker default min.insync.replicas=2"
    else bad "broker default min.insync.replicas is not 2"; fi
    kbin kafka-0 kafka-topics.sh --bootstrap-server localhost:9092 --delete --topic "$auto" >/dev/null 2>&1 || true
}

test_certs() {
    local want have leaf_pub key_pub
    echo ">>> TLS certificates (secrets kafka-ca, kafka-tls)"
    kafka_ca_pem > "$work/ca.crt" 2>/dev/null || true
    kk get secret kafka-tls -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d > "$work/tls.crt" 2>/dev/null || true
    kk get secret kafka-tls -o jsonpath='{.data.tls\.key}' 2>/dev/null | base64 -d > "$work/tls.key" 2>/dev/null || true
    if [ -s "$work/ca.crt" ] && [ -s "$work/tls.crt" ] &&
       openssl verify -CAfile "$work/ca.crt" "$work/tls.crt" >/dev/null 2>&1; then
        ok "broker certificate verifies against the BorgCloud Kafka CA"
    else
        bad "broker certificate missing or not signed by the CA"
    fi
    want=$(tr ' ' '\n' <<<"$(kafka_names)" | sort)
    have=$(cert_sans "$work/tls.crt")
    if [ -n "$have" ] && [ "$have" = "$want" ]; then ok "SANs are exactly: $(tr '\n' ' ' <<<"$have")"
    else bad "SANs '$(tr '\n' ' ' <<<"$have")' (want '$(tr '\n' ' ' <<<"$want")')"; fi
    leaf_pub=$(openssl x509 -in "$work/tls.crt" -noout -pubkey 2>/dev/null || true)
    key_pub=$(openssl pkey -in "$work/tls.key" -pubout 2>/dev/null || true)
    if [ -n "$key_pub" ] && [ "$leaf_pub" = "$key_pub" ]; then ok "private key matches the certificate"
    else bad "private key missing or does not match the certificate"; fi
}

# host: plaintext EXTERNAL listener on <node IP>:9094 (replaced by TLS in Task 2)
test_host() {
    local token out
    host_kafka() {
        docker run --rm -i --network host --entrypoint "/opt/kafka/bin/$1" "$KAFKA_IMAGE" "${@:2}"
    }
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
    if grep -qx "$token" <<<"$out"; then ok "consume from host via $NODE3_IP:$KAFKA_EXTERNAL_PORT"
    else bad "consume from host via $NODE3_IP:$KAFKA_EXTERNAL_PORT did not return the message"; fi
}

kafka_pods_ready || die "Kafka is not installed or not Ready (run: make provision-kafka)"

target=${1:-all}
case "$target" in
    all)     test_cluster; test_certs; test_host ;;
    cluster) test_cluster ;;
    certs)   test_certs ;;
    host)    test_host ;;
    *) die "usage: $0 [all|cluster|certs|tls|host]" ;;
esac

if [ "$fail" -eq 0 ]; then
    echo ">>> kafka-test: all checks passed"
else
    echo ">>> kafka-test: FAILED" >&2
    exit 1
fi
