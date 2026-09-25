#!/bin/bash
# =============================================================================
# 06-kafka/kafka-tls.sh
# ensure_kafka_tls <workdir>: the BorgCloud Kafka CA and the broker certificate
# (SANs: kafka_names), created once with openssl and stored only as Secrets.
# The broker certificate is reissued if its SANs no longer match. Keys are
# written only inside <workdir> (the caller removes it) and into the Secrets.
# Sourced by install-kafka.sh (after vars.sh, 03-databases/lib.sh, kafka-lib.sh).
# =============================================================================

ensure_kafka_tls() {
    local d=$1 want have state san n
    if kk get secret kafka-ca >/dev/null 2>&1; then
        echo "    secret/kafka-ca exists (kept)"
    else
        openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$d/ca.key" 2>/dev/null
        openssl req -x509 -new -key "$d/ca.key" -sha256 -days 3650 -subj "/CN=BorgCloud Kafka CA" \
            -addext "basicConstraints=critical,CA:TRUE" \
            -addext "keyUsage=critical,keyCertSign,cRLSign" -out "$d/ca.crt"
        kk create secret generic kafka-ca --from-file="$d/ca.crt" --from-file="$d/ca.key" \
            --dry-run=client -o yaml | kubectl apply -f - >/dev/null
        echo "    secret/kafka-ca created"
    fi

    want=$(tr ' ' '\n' <<<"$(kafka_names)" | sort)
    have=""
    state=created
    if kk get secret kafka-tls >/dev/null 2>&1; then
        kk get secret kafka-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > "$d/current.crt"
        have=$(cert_sans "$d/current.crt")
        state=reissued
    fi
    if [ -n "$have" ] && [ "$have" = "$want" ]; then
        echo "    secret/kafka-tls exists (kept)"
        return 0
    fi

    kafka_ca_pem > "$d/ca.crt"
    kk get secret kafka-ca -o jsonpath='{.data.ca\.key}' | base64 -d > "$d/ca.key"
    san=""
    for n in $(kafka_names); do san="${san:+$san,}DNS:$n"; done
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$d/tls.key" 2>/dev/null
    openssl req -new -key "$d/tls.key" -subj "/CN=$KAFKA_DOMAIN" -out "$d/tls.csr"
    printf 'subjectAltName=%s\nextendedKeyUsage=serverAuth\nbasicConstraints=CA:FALSE\n' "$san" > "$d/leaf.ext"
    openssl x509 -req -in "$d/tls.csr" -CA "$d/ca.crt" -CAkey "$d/ca.key" \
        -CAserial "$d/ca.srl" -CAcreateserial -days 1825 -sha256 -extfile "$d/leaf.ext" \
        -out "$d/leaf.crt" 2>/dev/null
    cat "$d/leaf.crt" "$d/ca.crt" > "$d/tls.crt"
    kk create secret generic kafka-tls --from-file="$d/tls.crt" --from-file="$d/tls.key" \
        --from-file="$d/ca.crt" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    echo "    secret/kafka-tls $state"
}
