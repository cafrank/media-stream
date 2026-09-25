# Kafka over TLS/SNI through HAProxy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Host clients reach Kafka only through HAProxy on `192.168.56.120:443` over TLS: bootstrap `kafka.borg.test`, and brokers as `kafka-N.kafka.borg.test`, routed by SNI passthrough. `node:9094` is removed. In-cluster plaintext `:9092` is unchanged.

**Architecture:** `06-kafka/kafka-tls.sh` creates a BorgCloud CA and one broker certificate (SANs: the 4 names) with openssl on the host, once, and stores them only as Secrets. Each broker's EXTERNAL listener becomes `SSL` on container port 9094 (PEM keystore built by `start.sh` from the Secret), advertising `kafka-N.kafka.borg.test:443`. Per-broker Services plus 4 Ingresses with `haproxy.org/ssl-passthrough: "true"` let HAProxy route each SNI name to its broker without decrypting. Tests run on the host: `openssl s_client` and a throwaway `apache/kafka` container with `--add-host`.

**Tech Stack:** bash, GNU make, openssl 3.0.13, kubectl 1.36, Kafka 4.3.1 (console tools take `--command-config`), HAProxy Kubernetes Ingress (chart 1.54.2, HAProxy 3.2.15), Docker.

**Spec:** `docs/superpowers/specs/2026-09-25-borg-cloud-kafka-tls-sni-design.md`

## Global Constraints

- Branch `kafka-tls-sni`. Paths in **Files:** are relative to the repository root. `Run:` commands say where they run. `git` commands run from the repository root. Stage by explicit path only. Never stage the user's uncommitted files (`.gitignore`, `.idea/workspace.xml`, `README`, `media-service/src/main/java/com/sparkle/mediaservice/service/GcsSignUrl.java`, `media-service/src/main/resources/application.properties`).
- Live cluster: `~/.kube/config-borg`. **Never run `make vagrant-destroy`.** Scripts never edit the host's `/etc/hosts`.
- `KAFKA_DOMAIN="kafka.borg.test"`. The 4 names are `kafka.borg.test`, `kafka-0.kafka.borg.test`, `kafka-1.kafka.borg.test`, `kafka-2.kafka.borg.test`, all → `VIP_ADDRESS` (`192.168.56.120`), port 443.
- Secrets in namespace `kafka`: `kafka-ca` (keys `ca.crt`, `ca.key`) and `kafka-tls` (keys `tls.crt` = leaf + CA, `tls.key` = PKCS#8 unencrypted, `ca.crt`). Created only if absent. `kafka-tls` is also reissued when its SANs differ from the 4 names.
- CA: EC P-256, `CN=BorgCloud Kafka CA`, 3650 days, `basicConstraints=critical,CA:TRUE`, `keyUsage=critical,keyCertSign,cRLSign`. Broker certificate: EC P-256, 1825 days, SANs = the 4 DNS names, `extendedKeyUsage=serverAuth`.
- Private keys never leave `mktemp -d` directories (removed by trap) except into Secrets. `make kafka-ca` writes only the CA certificate, to `borg-cloud/.kafka-ca.crt` (git-ignored).
- Broker: `advertised EXTERNAL://kafka-$N.${KAFKA_DOMAIN}:443`, `EXTERNAL:SSL`, `ssl.keystore.type=PEM`, `ssl.keystore.location=/tmp/keystore.pem`, `ssl.client.auth=none`. No `hostPort`, no `HOST_IP`. Secret `kafka-tls` is mounted read-only at `/etc/kafka/tls-src`. The pod template carries `borg/kafka-tls-sha` (hash of `tls.crt`), so a reissued certificate rolls the brokers.
- Routing: Services `kafka-external` (all brokers) and `kafka-{0,1,2}-external` (selector `statefulset.kubernetes.io/pod-name`), port 9094. Ingresses (class `haproxy`, `haproxy.org/ssl-passthrough: "true"`), one host rule each, path `/`, `Prefix`. These Services must not be used by any non-passthrough Ingress (HAProxy gives a backend a single mode).
- No `cmd | grep -q` pipelines under `pipefail`: capture, then match.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Review Focus

1. **Re-running `provision-kafka`.** Same CA and broker certificate (content hashes) and no broker roll. Pinned in Task 3, Step 2.
2. **A changed `KAFKA_DOMAIN`.** The broker certificate is reissued by the same CA with the new SANs, and its hash changes. Pinned in Task 1, Step 6.
3. **A host without the `/etc/hosts` entries.** Tests still pass (`--add-host`), and `make kafka-hosts` prints exactly the 4 lines to add. Pinned in Task 1, Step 5 and Task 2's host test.
4. **A client that connects to `VIP:443` without an SNI name, or with an unknown one.** It must not reach a broker: HAProxy's default certificate answers, and it does not verify against the Kafka CA. Pinned in Task 2, Step 2 (`tls` checks).
5. **media-service HTTP on port 80 after the passthrough Ingresses are added.** It must keep working. Pinned in Task 2, Step 7.

---

## File Structure

| File | Responsibility |
|---|---|
| `borg-cloud/vars.sh` (modify) | `KAFKA_DOMAIN` |
| `borg-cloud/.gitignore` (modify) | `.kafka-ca.crt` |
| `borg-cloud/06-kafka/kafka-lib.sh` (modify) | `kafka_names`, `kafka_ca_pem`, `cert_sans`; `KAFKA_DOMAIN`, `KAFKA_TLS_SHA` substitution |
| `borg-cloud/06-kafka/kafka-tls.sh` (create) | `ensure_kafka_tls <workdir>` |
| `borg-cloud/06-kafka/install-kafka.sh` (modify) | Edge preflight, TLS Secrets, TLS hash |
| `borg-cloud/06-kafka/kafka.yaml` (modify) | TLS listener, no hostPort, TLS volume, Services, Ingresses |
| `borg-cloud/06-kafka/kafka-test.sh` (modify) | Sections `cluster`, `certs`, `tls`, `host` |
| `borg-cloud/Makefile` (modify) | `kafka-ca`, `kafka-hosts`, help |

---

### Task 1: Certificates

**Files:**
- Modify: `borg-cloud/vars.sh`, `borg-cloud/.gitignore`, `borg-cloud/06-kafka/kafka-lib.sh`, `borg-cloud/06-kafka/install-kafka.sh`, `borg-cloud/06-kafka/kafka-test.sh`, `borg-cloud/Makefile`
- Create: `borg-cloud/06-kafka/kafka-tls.sh`

**Interfaces:**
- Consumes: `kk`, `kbin`, `kafka_pods_ready`, `topic_isr_full` (from #11's kafka-lib); `die`, `retry` (03 lib).
- Produces (kafka-lib, used by Tasks 2–3):
  - `kafka_names`: prints the 4 names on one line, space-separated
  - `kafka_ca_pem`: prints the CA certificate from Secret `kafka-ca`
  - `cert_sans <pem-file>`: prints the certificate's DNS SANs, sorted, one per line
- Produces (kafka-tls.sh): `ensure_kafka_tls <workdir>`: creates or keeps Secrets `kafka-ca` and `kafka-tls`, printing `secret/<name> created|exists (kept)|reissued`.
- Produces: `kafka-test.sh [all|cluster|certs|tls|host]`; Make targets `kafka-ca`, `kafka-hosts`.

- [ ] **Step 1: Settings, ignore file, helpers**

Insert into `borg-cloud/vars.sh` directly after the line `KAFKA_EXTERNAL_PORT="9094"                 # hostPort on each node: <node IP>:9094`, replacing that line with:

```bash
KAFKA_EXTERNAL_PORT="9094"                 # broker's TLS listener (container port; reached via HAProxy)
KAFKA_DOMAIN="kafka.borg.test"             # host clients: kafka.<domain>, kafka-N.<domain> -> VIP:443 (TLS/SNI)
```

Append to `borg-cloud/.gitignore`:

```
.kafka-ca.crt
```

In `borg-cloud/06-kafka/kafka-lib.sh`:
- in the `export` line, change `KAFKA_MEMORY_LIMIT KAFKA_EXTERNAL_PORT KAFKA_SCRIPTS_SHA` to `KAFKA_MEMORY_LIMIT KAFKA_EXTERNAL_PORT KAFKA_SCRIPTS_SHA KAFKA_DOMAIN KAFKA_TLS_SHA`
- in `KAFKA_VARS`, change `${KAFKA_EXTERNAL_PORT} ${KAFKA_SCRIPTS_SHA}'` to `${KAFKA_EXTERNAL_PORT} ${KAFKA_SCRIPTS_SHA} ${KAFKA_DOMAIN} ${KAFKA_TLS_SHA}'`
- append:

```bash

# kafka_names: the 4 host-facing names (bootstrap first), space-separated
kafka_names() { echo "$KAFKA_DOMAIN kafka-0.$KAFKA_DOMAIN kafka-1.$KAFKA_DOMAIN kafka-2.$KAFKA_DOMAIN"; }

# kafka_ca_pem: the BorgCloud Kafka CA certificate (public) from Secret kafka-ca
kafka_ca_pem() { kk get secret kafka-ca -o jsonpath='{.data.ca\.crt}' | base64 -d; }

# cert_sans <pem-file>: the certificate's DNS subjectAltNames, sorted, one per line
cert_sans() {
    local ext
    ext=$(openssl x509 -in "$1" -noout -ext subjectAltName 2>/dev/null) || return 0
    tr ',' '\n' <<<"$ext" | sed -n 's/^ *DNS://p' | sort
}
```

- [ ] **Step 2: Write the failing test: sections in `kafka-test.sh`, plus `certs`**

Replace `borg-cloud/06-kafka/kafka-test.sh` with:

```bash
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
```

Run: `cd borg-cloud && bash 06-kafka/kafka-test.sh certs; echo "exit=$?"`
Expected: `FAIL  broker certificate missing or not signed by the CA`, `FAIL  SANs '' (want 'kafka-0.kafka.borg.test kafka-1... kafka.borg.test ')`, `FAIL  private key missing ...`, `kafka-test: FAILED`, `exit=1`.

Run: `cd borg-cloud && bash 06-kafka/kafka-test.sh cluster | tail -1 && bash 06-kafka/kafka-test.sh host | tail -1`
Expected: both `kafka-test: all checks passed` (the restructure didn't change the existing checks).

- [ ] **Step 3: Create `borg-cloud/06-kafka/kafka-tls.sh`**

```bash
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
```

- [ ] **Step 4: Call it from `install-kafka.sh`, then run it**

In `borg-cloud/06-kafka/install-kafka.sh`:
- after `source 06-kafka/kafka-lib.sh`, add `source 06-kafka/kafka-tls.sh`
- after the `fi` that ends the `kafka-cluster-id` block, add:

```bash

tls_work=$(mktemp -d)
trap 'rm -rf "$tls_work"' EXIT
echo ">>> Kafka TLS (CA + broker certificate for $(kafka_names))"
ensure_kafka_tls "$tls_work"
```

Run: `cd borg-cloud && shellcheck -S warning -e SC1091 06-kafka/*.sh && make provision-kafka | grep -E 'secret/|ready'`
Expected: shellcheck silent; `secret/kafka-cluster-id exists (kept)`, `secret/kafka-ca created`, `secret/kafka-tls created`, both waits `ready`. No broker roll (the pod template is unchanged in this task).

Run: `cd borg-cloud && bash 06-kafka/kafka-test.sh certs`
Expected: `PASS  broker certificate verifies ...`, `PASS  SANs are exactly: kafka-0.kafka.borg.test kafka-1.kafka.borg.test kafka-2.kafka.borg.test kafka.borg.test`, `PASS  private key matches the certificate`, `kafka-test: all checks passed`.

- [ ] **Step 5: `kafka-ca` and `kafka-hosts` targets (Review Focus 3)**

In `borg-cloud/Makefile`, add `KAFKA_DOMAIN := $(call var,KAFKA_DOMAIN)` after `VIP_ADDRESS := $(call var,VIP_ADDRESS)`, and after the `kafka-status` target add:

```make

.PHONY: kafka-ca
kafka-ca:
	@source ./vars.sh && source 03-databases/lib.sh && source 06-kafka/kafka-lib.sh && \
		kafka_ca_pem > .kafka-ca.crt 2>/dev/null; \
		[ -s .kafka-ca.crt ] || { rm -f .kafka-ca.crt; echo "No Kafka CA found (run: make provision-kafka)" >&2; exit 1; }
	@echo "Wrote $(CURDIR)/.kafka-ca.crt (BorgCloud Kafka CA certificate; trust it in Kafka clients)"

.PHONY: kafka-hosts
kafka-hosts:
	@echo "# BorgCloud Kafka via HAProxy on the VIP: add these lines to /etc/hosts"
	@for n in $(KAFKA_DOMAIN) kafka-0.$(KAFKA_DOMAIN) kafka-1.$(KAFKA_DOMAIN) kafka-2.$(KAFKA_DOMAIN); do \
		echo "$(VIP_ADDRESS) $$n"; done
```

Run: `cd borg-cloud && make kafka-hosts && make kafka-ca && openssl x509 -in .kafka-ca.crt -noout -subject && git check-ignore -q .kafka-ca.crt && echo IGNORED`
Expected: the comment line and exactly `192.168.56.120 kafka.borg.test`, `192.168.56.120 kafka-0.kafka.borg.test`, `…kafka-1…`, `…kafka-2…`; `Wrote …/.kafka-ca.crt`; `subject=CN = BorgCloud Kafka CA`; `IGNORED`.

- [ ] **Step 6: A changed domain reissues the certificate (Review Focus 2)**

Run:
```bash
cd borg-cloud && source ./vars.sh && source 03-databases/lib.sh && source 06-kafka/kafka-lib.sh && source 06-kafka/kafka-tls.sh
h() { kk get secret "$1" -o jsonpath='{.data}' | sha256sum | cut -c1-12; }
ca0=$(h kafka-ca); tls0=$(h kafka-tls)
d=$(mktemp -d); KAFKA_DOMAIN=kafka.other.test ensure_kafka_tls "$d"; rm -rf "$d"
kk get secret kafka-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/claude-sans.crt; cert_sans /tmp/claude-sans.crt | tr '\n' ' '; echo
echo "CA unchanged: $([ "$(h kafka-ca)" = "$ca0" ] && echo yes || echo NO)"
d=$(mktemp -d); ensure_kafka_tls "$d"; rm -rf "$d" /tmp/claude-sans.crt
echo "back: $(bash 06-kafka/kafka-test.sh certs | tail -1); tls changed from original: $([ "$(h kafka-tls)" != "$tls0" ] && echo yes || echo no)"
```
Expected: `secret/kafka-ca exists (kept)`, `secret/kafka-tls reissued`; SANs `kafka-0.kafka.other.test kafka-1.kafka.other.test kafka-2.kafka.other.test kafka.other.test`; `CA unchanged: yes`; then `secret/kafka-tls reissued` again; `back: >>> kafka-test: all checks passed; tls changed from original: yes`.

- [ ] **Step 7: Commit**

```bash
git add borg-cloud/vars.sh borg-cloud/.gitignore borg-cloud/Makefile borg-cloud/06-kafka/kafka-lib.sh borg-cloud/06-kafka/kafka-tls.sh borg-cloud/06-kafka/install-kafka.sh borg-cloud/06-kafka/kafka-test.sh
git commit -m "borg-cloud kafka: BorgCloud CA + broker certificate (Secrets); kafka-ca, kafka-hosts

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: TLS listener and SNI passthrough through HAProxy

**Files:**
- Modify: `borg-cloud/06-kafka/kafka.yaml`, `borg-cloud/06-kafka/install-kafka.sh`, `borg-cloud/06-kafka/kafka-test.sh`

**Interfaces:**
- Consumes: `kafka_names`, `kafka_ca_pem`, `ensure_kafka_tls` (Task 1); `http_code` from `07-edge/edge-lib.sh`; `VIP_ADDRESS`.
- Produces: `kafka-test.sh tls` and a TLS `host` section; the 4 passthrough routes.

- [ ] **Step 1: Write the failing test: `tls` and TLS `host` sections**

In `borg-cloud/06-kafka/kafka-test.sh`:
- after `source 06-kafka/kafka-lib.sh`, add `source 07-edge/edge-lib.sh`
- update the header lines for `tls` and `host`:

```bash
#   tls:     each of the 4 names gets a TLS handshake on VIP:443 that verifies
#            against the CA; no SNI / an unknown name does not reach a broker
#   host:    produce/consume over TLS through kafka.<domain>:443 (every broker's
#            name must route to it); node:9094 no longer answers
```

- replace the whole `test_host() { ... }` function (including its comment line) with:

```bash
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
    echo ">>> From the host over TLS (kafka.$KAFKA_DOMAIN -> $VIP_ADDRESS:443)"
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
```

- replace the `case` block with:

```bash
case "$target" in
    all)     test_cluster; test_certs; test_tls; test_host ;;
    cluster) test_cluster ;;
    certs)   test_certs ;;
    tls)     test_tls ;;
    host)    test_host ;;
    *) die "usage: $0 [all|cluster|certs|tls|host]" ;;
esac
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `cd borg-cloud && bash 06-kafka/kafka-test.sh tls; bash 06-kafka/kafka-test.sh host; echo "exit=$?"`
Expected (`tls`): 4 × `FAIL  <name>: no verified handshake` (HAProxy has no passthrough routes yet and presents its default certificate), and `PASS` for the no-SNI and unknown-name checks. (`host`): `FAIL  produce over TLS ...`, `FAIL  consume over TLS ...`, and 3 × `FAIL  192.168.56.12N:9094 still answers`; non-zero exit.

- [ ] **Step 3: TLS listener, routing and hash in `kafka.yaml`**

In `borg-cloud/06-kafka/kafka.yaml`:
- header line 3: replace `#   host:       <any node IP>:${KAFKA_EXTERNAL_PORT} (hostPort; each broker advertises its node IP)` with `#   host:       kafka.${KAFKA_DOMAIN}:443 over TLS via HAProxy on the VIP (SNI: kafka-N.${KAFKA_DOMAIN})`
- in `start.sh`, directly before the line `    cat > /tmp/server.properties <<EOF`, insert:

```bash
    # Kafka's PEM keystore wants the private key and the certificate chain in one file
    cat /etc/kafka/tls-src/tls.key /etc/kafka/tls-src/tls.crt > /tmp/keystore.pem
```

- replace `    advertised.listeners=INTERNAL://kafka-$N.$H:9092,EXTERNAL://$HOST_IP:${KAFKA_EXTERNAL_PORT}` with `    advertised.listeners=INTERNAL://kafka-$N.$H:9092,EXTERNAL://kafka-$N.${KAFKA_DOMAIN}:443`
- replace `    listener.security.protocol.map=INTERNAL:PLAINTEXT,CONTROLLER:PLAINTEXT,EXTERNAL:PLAINTEXT` with:

```
    listener.security.protocol.map=INTERNAL:PLAINTEXT,CONTROLLER:PLAINTEXT,EXTERNAL:SSL
    ssl.keystore.type=PEM
    ssl.keystore.location=/tmp/keystore.pem
    ssl.client.auth=none
```

- replace the `echo "start: ..."` line with `    echo "start: node.id=$N advertised INTERNAL kafka-$N.$H:9092 EXTERNAL kafka-$N.${KAFKA_DOMAIN}:443 (TLS)"`
- remove the `HOST_IP` env entry (the 4 lines `- name: HOST_IP` … `fieldPath: status.hostIP`)
- remove the line `              hostPort: ${KAFKA_EXTERNAL_PORT}`
- after `        borg/kafka-scripts-sha: "${KAFKA_SCRIPTS_SHA}"   # set by install-kafka.sh`, add `        borg/kafka-tls-sha: "${KAFKA_TLS_SHA}"           # set by install-kafka.sh`
- in the container's `volumeMounts`, after the `scripts` mount, add:

```yaml
            - name: tls
              mountPath: /etc/kafka/tls-src
              readOnly: true
```

- in `volumes`, after the `scripts` volume, add:

```yaml
        - name: tls
          secret:
            secretName: kafka-tls
```

- append to the end of the file:

```yaml
---
# External (TLS) listener, reached only through HAProxy SSL passthrough on the VIP
apiVersion: v1
kind: Service
metadata:
  name: kafka-external
  namespace: ${KAFKA_NAMESPACE}
spec:
  selector:
    app.kubernetes.io/name: kafka
  ports:
    - name: external
      port: 9094
      targetPort: external
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-0-external
  namespace: ${KAFKA_NAMESPACE}
spec:
  selector:
    statefulset.kubernetes.io/pod-name: kafka-0
  ports:
    - name: external
      port: 9094
      targetPort: external
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-1-external
  namespace: ${KAFKA_NAMESPACE}
spec:
  selector:
    statefulset.kubernetes.io/pod-name: kafka-1
  ports:
    - name: external
      port: 9094
      targetPort: external
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-2-external
  namespace: ${KAFKA_NAMESPACE}
spec:
  selector:
    statefulset.kubernetes.io/pod-name: kafka-2
  ports:
    - name: external
      port: 9094
      targetPort: external
---
# SNI passthrough: HAProxy forwards the raw TLS stream by server name (no decryption).
# These Services must not be used by any non-passthrough Ingress (one mode per backend).
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kafka-bootstrap-tls
  namespace: ${KAFKA_NAMESPACE}
  annotations:
    haproxy.org/ssl-passthrough: "true"
spec:
  ingressClassName: haproxy
  rules:
    - host: ${KAFKA_DOMAIN}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: kafka-external
                port:
                  number: 9094
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kafka-0-tls
  namespace: ${KAFKA_NAMESPACE}
  annotations:
    haproxy.org/ssl-passthrough: "true"
spec:
  ingressClassName: haproxy
  rules:
    - host: kafka-0.${KAFKA_DOMAIN}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: kafka-0-external
                port:
                  number: 9094
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kafka-1-tls
  namespace: ${KAFKA_NAMESPACE}
  annotations:
    haproxy.org/ssl-passthrough: "true"
spec:
  ingressClassName: haproxy
  rules:
    - host: kafka-1.${KAFKA_DOMAIN}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: kafka-1-external
                port:
                  number: 9094
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kafka-2-tls
  namespace: ${KAFKA_NAMESPACE}
  annotations:
    haproxy.org/ssl-passthrough: "true"
spec:
  ingressClassName: haproxy
  rules:
    - host: kafka-2.${KAFKA_DOMAIN}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: kafka-2-external
                port:
                  number: 9094
```

- [ ] **Step 4: Edge preflight and TLS hash in `install-kafka.sh`**

In `borg-cloud/06-kafka/install-kafka.sh`:
- after `source 06-kafka/kafka-tls.sh`, add `source 07-edge/edge-lib.sh`
- directly after the line `preflight`, add:

```bash
# External access goes through HAProxy on the VIP (make provision-edge)
if ! kubectl get ingressclass haproxy >/dev/null 2>&1 || [ "$(http_code "http://$VIP_ADDRESS/")" = 000 ]; then
    die "the edge (HAProxy on $VIP_ADDRESS) is not installed (run: make provision-edge)"
fi
```

- directly before `KAFKA_SCRIPTS_SHA=$(kafka_scripts_sha 06-kafka/kafka.yaml)`, add:

```bash
# A reissued broker certificate changes the pod template, so the brokers roll
KAFKA_TLS_SHA=$(kk get secret kafka-tls -o jsonpath='{.data.tls\.crt}' | sha256sum | cut -c1-16)
```

Run: `cd borg-cloud && shellcheck -S warning -e SC1091 06-kafka/*.sh && source ./vars.sh && source 03-databases/lib.sh && source 06-kafka/kafka-lib.sh && render_kafka 06-kafka/kafka.yaml | kubectl apply --dry-run=server -f - | tail -9`
Expected: shellcheck silent; the server dry-run accepts `statefulset.apps/kafka`, the 4 `kafka-*external` Services and the 4 `kafka-*-tls` Ingresses.

- [ ] **Step 5: Roll the brokers to TLS**

Run: `cd borg-cloud && make provision-kafka 2>&1 | grep -E 'secret/|rolled out|ready|ERROR'`
Expected: Secrets `exists (kept)`; `statefulset rolling update complete` / `partitioned roll out complete`; both waits `ready`. About 3–5 minutes (one broker at a time, with 20s pauses).

Run: `KUBECONFIG=~/.kube/config-borg kubectl -n kafka logs kafka-1 | grep '^start:' && KUBECONFIG=~/.kube/config-borg kubectl -n kafka get ingress`
Expected: `start: node.id=1 ... EXTERNAL kafka-1.kafka.borg.test:443 (TLS)`; 4 Ingresses with class `haproxy`, hosts `kafka.borg.test` and `kafka-N.kafka.borg.test`, address `192.168.56.120`.

- [ ] **Step 6: Run the test to confirm it passes**

Run: `cd borg-cloud && make kafka-test`
Expected: every check `PASS`, including the 4 verified handshakes, `no SNI name: not routed to Kafka`, `unknown name: not routed to Kafka`, `produce over TLS via kafka.borg.test:443`, `consume over TLS from all 3 partitions ...`, and 3 × `192.168.56.12N:9094 closed`; `kafka-test: all checks passed`.

If the handshakes fail after the roll, check the controller's view: `KUBECONFIG=~/.kube/config-borg kubectl -n haproxy-controller logs deploy/haproxy-kubernetes-ingress --tail=50 | grep -i -E 'passthrough|kafka'`. The controller refuses passthrough on a backend shared with a non-passthrough Ingress and on default backends. Fix the manifest, not the test.

- [ ] **Step 7: HTTP on port 80 still works (Review Focus 5)**

Run: `cd borg-cloud && make media-test | tail -1 && make edge-test | tail -1`
Expected: both `all checks passed`.

- [ ] **Step 8: Commit**

```bash
git add borg-cloud/06-kafka/kafka.yaml borg-cloud/06-kafka/install-kafka.sh borg-cloud/06-kafka/kafka-test.sh
git commit -m "borg-cloud kafka: TLS listener behind HAProxy SNI passthrough; remove node:9094

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Idempotency, uninstall/reinstall, help, acceptance

**Files:**
- Modify: `borg-cloud/Makefile` (help)

- [ ] **Step 1: Write the failing check: help mentions the new targets and TLS address**

Run: `cd borg-cloud && make help | grep -c -E 'kafka-ca|kafka-hosts|kafka.borg.test:443'`
Expected: `0`.

Then update `help` in `borg-cloud/Makefile`:
- replace `	@echo "  make provision-kafka     3 brokers, one per node (KRaft, plaintext)"` with `	@echo "  make provision-kafka     3 brokers, one per node (KRaft); TLS for host clients"`
- after the line `	@echo "  make kafka-uninstall     Delete Kafka and its data"`, add:

```make
	@echo "  make kafka-ca            Write the Kafka CA cert to .kafka-ca.crt (again after a reinstall)"
	@echo "  make kafka-hosts         Print the /etc/hosts lines for the Kafka names"
```

- replace `	@echo "    host:       $(NODE1_IP):9094 (any node IP)"` with `	@echo "    host (TLS): $(KAFKA_DOMAIN):443 via $(VIP_ADDRESS); trust .kafka-ca.crt"`

Run: `cd borg-cloud && make help | grep -c -E 'kafka-ca|kafka-hosts|kafka.borg.test:443'`
Expected: `3`.

- [ ] **Step 2: Re-running changes nothing (Review Focus 1)**

Run:
```bash
cd borg-cloud && export KUBECONFIG=~/.kube/config-borg
snap() {
    for s in kafka-ca kafka-tls kafka-cluster-id; do
        echo "$s=$(kubectl -n kafka get secret $s -o jsonpath='{.data}' | sha256sum | cut -c1-12)"
    done
    kubectl -n kafka get pods -o jsonpath='{range .items[*]}{.metadata.name}={.metadata.uid}{"\n"}{end}' | sort
}
before=$(snap); make provision-kafka 2>&1 | grep -E 'secret/'; after=$(snap)
[ "$before" = "$after" ] && echo "IDEMPOTENT" || diff <(echo "$before") <(echo "$after")
```
Expected: all `exists (kept)`, and `IDEMPOTENT`.

- [ ] **Step 3: Uninstall and reinstall (new CA)**

Run:
```bash
cd borg-cloud
old=$(openssl x509 -in .kafka-ca.crt -noout -fingerprint -sha256)
make kafka-uninstall && make provision-kafka 2>&1 | grep -E 'secret/|ready'
make kafka-ca && new=$(openssl x509 -in .kafka-ca.crt -noout -fingerprint -sha256)
[ "$old" != "$new" ] && echo "NEW CA"
make kafka-test | tail -1
```
Expected: `secret/kafka-cluster-id created`, `secret/kafka-ca created`, `secret/kafka-tls created`, both waits `ready`; `NEW CA`; `kafka-test: all checks passed`.

- [ ] **Step 4: Full acceptance**

Run:
```bash
cd borg-cloud && export KUBECONFIG=~/.kube/config-borg
make kafka-failover-test 2>&1 | tail -1
make edge-failover-test 2>&1 | tail -1
for t in kafka-test edge-test db-test media-test registry-test; do make $t 2>&1 | grep -E 'test: '; done
kubectl top nodes
kubectl -n kafka get pods -o jsonpath='{range .items[*]}{.metadata.name} restarts={.status.containerStatuses[0].restartCount} last={.status.containerStatuses[0].lastState.terminated.reason}{"\n"}{end}'
```
Expected: `kafka-failover-test: passed`, `edge-failover-test: passed`, every suite `passed`; memory below about 85% on every node (otherwise **stop and ask the user**); brokers without `OOMKilled`.

- [ ] **Step 5: Commit**

```bash
git add borg-cloud/Makefile
git commit -m "borg-cloud: document Kafka TLS access (kafka-ca, kafka-hosts) in help

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

The branch is finished with superpowers:finishing-a-development-branch (the user chooses merge, PR or keep). This part closes #12.
