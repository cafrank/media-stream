#!/bin/bash
# =============================================================================
# 06-kafka/kafka-lib.sh
# Kafka helpers. Source after vars.sh and 03-databases/lib.sh.
# =============================================================================

export KAFKA_NAMESPACE KAFKA_IMAGE KAFKA_STORAGE_SIZE KAFKA_HEAP KAFKA_MEMORY_REQUEST \
       KAFKA_MEMORY_LIMIT KAFKA_EXTERNAL_PORT KAFKA_SCRIPTS_SHA

# Only these variables are substituted into kafka.yaml; start.sh's own shell
# variables ($NS, $N, $HOST_IP, ...) are left alone.
# shellcheck disable=SC2016
KAFKA_VARS='${KAFKA_NAMESPACE} ${KAFKA_IMAGE} ${KAFKA_STORAGE_SIZE} ${KAFKA_HEAP} ${KAFKA_MEMORY_REQUEST} ${KAFKA_MEMORY_LIMIT} ${KAFKA_EXTERNAL_PORT} ${KAFKA_SCRIPTS_SHA}'

kk() { kubectl -n "$KAFKA_NAMESPACE" "$@"; }

render_kafka() { envsubst "$KAFKA_VARS" < "$1"; }

# kafka_scripts_sha <manifest>: hash of the rendered kafka-scripts ConfigMap. It is
# stamped on the pod template, so changing start.sh rolls the brokers (a ConfigMap
# change alone would not restart them).
kafka_scripts_sha() {
    render_kafka "$1" | awk '/^kind: ConfigMap$/ {f = 1} /^---$/ {f = 0} f' | sha256sum | cut -c1-16
}

# kbin <pod> <script> <args...>: run a Kafka CLI tool inside a broker pod
kbin() {
    local pod=$1 script=$2; shift 2
    kk exec "$pod" -c kafka -- "/opt/kafka/bin/$script" "$@"
}

kafka_pods_ready() {
    [ "$(kk get statefulset kafka -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = 3 ]
}

# kafka_quorum_ok: kafka-0 reports a leader and 3 current voters
kafka_quorum_ok() {
    local out
    out=$(kbin kafka-0 kafka-metadata-quorum.sh --bootstrap-server localhost:9092 describe --status 2>/dev/null) \
        || return 1
    echo "$out" | awk '
        /^LeaderId:/      { if ($2 + 0 >= 0) leader = 1 }
        /^CurrentVoters:/ { voters = gsub(/"id"/, "") }
        END { exit !(leader && voters == 3) }'
}

# topic_isr_full <topic>: every partition has 3 in-sync replicas
topic_isr_full() {
    kbin kafka-0 kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic "$1" 2>/dev/null |
        awk '/Partition:/ {
                 n++
                 for (i = 1; i <= NF; i++) if ($i == "Isr:" && split($(i + 1), a, ",") != 3) bad = 1
             }
             END { exit !(n > 0 && !bad) }'
}
