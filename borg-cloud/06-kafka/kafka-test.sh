#!/bin/bash
# =============================================================================
# 06-kafka/kafka-test.sh [all|cluster|certs|tls|host]
#   cluster: replicated test topic; produce/consume in-cluster (INTERNAL :9092);
#            auto-created topic defaults
#   certs:   Secrets kafka-ca / kafka-tls: the broker certificate verifies against
#            the CA, names exactly the 4 hosts, and matches its key
#   tls:     each of the 4 names gets a TLS handshake on VIP:443 that verifies
#            against the CA; no SNI / an unknown name does not reach a broker
#   host:    produce/consume over TLS through kafka.<domain>:443 (every broker's
#            name must route to it); node:9094 no longer answers
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./vars.sh
source 03-databases/lib.sh
source 06-kafka/kafka-lib.sh
source 07-edge/edge-lib.sh

TOPIC=borg-kafka-test
fail=0
ok()  { echo "  PASS  $*"; }
bad() { echo "  FAIL  $*"; fail=1; }
# Scratch dir under borg-cloud/, not /tmp: it is bind-mounted into a docker container,
# and the docker daemon doesn't necessarily see this shell's /tmp (git-ignored)
work=$(mktemp -d "$PWD/.kafka-test.XXXXXX")
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
    # the private key is piped straight from the Secret: it is never written to disk
    key_pub=$(kk get secret kafka-tls -o jsonpath='{.data.tls\.key}' 2>/dev/null | base64 -d 2>/dev/null |
        openssl pkey -pubout 2>/dev/null || true)
    if [ -n "$key_pub" ] && [ "$leaf_pub" = "$key_pub" ]; then ok "private key matches the certificate"
    else bad "private key missing or does not match the certificate"; fi
}

# handshake <name|""> <cafile>: 0 when a TLS handshake on VIP:443 with that SNI
# name verifies against the CA and the name (no name: plain chain check)
handshake() {
    local out
    if [ -n "$1" ]; then
        out=$(openssl s_client -connect "$VIP_ADDRESS:443" -servername "$1" -CAfile "$2" \
            -verify_return_error -verify_hostname "$1" </dev/null 2>&1 || true)
    else
        out=$(openssl s_client -connect "$VIP_ADDRESS:443" -CAfile "$2" -verify_return_error </dev/null 2>&1 || true)
    fi
    grep -q 'Verify return code: 0 (ok)' <<<"$out"
}

test_tls() {
    local n
    echo ">>> TLS via HAProxy on $VIP_ADDRESS:443 (SNI passthrough)"
    kafka_ca_pem > "$work/ca.crt"
    for n in $(kafka_names); do
        if handshake "$n" "$work/ca.crt"; then ok "$n: handshake verifies against the Kafka CA"
        else bad "$n: no verified handshake"; fi
    done
    if handshake "" "$work/ca.crt"; then bad "no SNI name: reached a Kafka broker"
    else ok "no SNI name: not routed to Kafka"; fi
    if handshake "nope.$KAFKA_DOMAIN" "$work/ca.crt"; then bad "unknown name: reached a Kafka broker"
    else ok "unknown name: not routed to Kafka"; fi
}

test_host() {
    local token out n ip
    local addhosts=()
    for n in $(kafka_names); do addhosts+=(--add-host "$n:$VIP_ADDRESS"); done
    kafka_ca_pem > "$work/ca.crt"
    printf 'security.protocol=SSL\nssl.truststore.type=PEM\nssl.truststore.location=/tls/ca.crt\nacks=all\n' \
        > "$work/client.properties"
    chmod 755 "$work"; chmod 644 "$work/ca.crt" "$work/client.properties"
    host_kafka() {
        docker run --rm -i --network host "${addhosts[@]}" -v "$work:/tls:ro" \
            --entrypoint "/opt/kafka/bin/$1" "$KAFKA_IMAGE" "${@:2}"
    }
    echo ">>> From the host over TLS ($KAFKA_DOMAIN -> $VIP_ADDRESS:443)"
    token="host-tls-$(date +%s)-$RANDOM"
    if echo "$token" | host_kafka kafka-console-producer.sh --bootstrap-server "$KAFKA_DOMAIN:443" \
            --topic "$TOPIC" --command-config /tls/client.properties >/dev/null 2>&1; then
        ok "produce over TLS via $KAFKA_DOMAIN:443"
    else
        bad "produce over TLS via $KAFKA_DOMAIN:443"
    fi
    out=$(host_kafka kafka-console-consumer.sh --bootstrap-server "$KAFKA_DOMAIN:443" --topic "$TOPIC" \
            --from-beginning --timeout-ms 30000 --command-config /tls/client.properties 2>/dev/null || true)
    if grep -qx "$token" <<<"$out"; then
        ok "consume over TLS from all 3 partitions (every kafka-N.$KAFKA_DOMAIN routes to its broker)"
    else
        bad "consume over TLS did not return the message"
    fi
    for ip in $ALL_IPS; do
        if timeout 3 bash -c "exec 3<>/dev/tcp/$ip/$KAFKA_EXTERNAL_PORT" 2>/dev/null; then
            bad "$ip:$KAFKA_EXTERNAL_PORT still answers"
        else
            ok "$ip:$KAFKA_EXTERNAL_PORT closed"
        fi
    done
}

kafka_pods_ready || die "Kafka is not installed or not Ready (run: make provision-kafka)"

target=${1:-all}
case "$target" in
    all)     test_cluster; test_certs; test_tls; test_host ;;
    cluster) test_cluster ;;
    certs)   test_certs ;;
    tls)     test_tls ;;
    host)    test_host ;;
    *) die "usage: $0 [all|cluster|certs|tls|host]" ;;
esac

if [ "$fail" -eq 0 ]; then
    echo ">>> kafka-test: all checks passed"
else
    echo ">>> kafka-test: FAILED" >&2
    exit 1
fi
