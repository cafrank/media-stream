# BorgCloud: Kafka over TLS/SNI through HAProxy on the VIP (#12, part 2)

- **Issue:** #12, part 2 of 2 (part of epic #1; builds on #11 and #12 part 1)
- **Date:** 2026-09-25
- **Status:** Design approved, awaiting spec review

## Goal

Host clients reach Kafka only through HAProxy on the floating VIP, over TLS:
bootstrap `kafka.borg.test:443`, and each broker by its own name
`kafka-N.kafka.borg.test:443`. HAProxy routes by the TLS SNI name without decrypting
(passthrough). The per-node `node:9094` access (hostPort) is removed. In-cluster access
(`kafka-bootstrap.kafka.svc.cluster.local:9092`, plaintext) is unchanged.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Names | `KAFKA_DOMAIN="kafka.borg.test"`: `kafka.borg.test` (bootstrap), `kafka-{0,1,2}.kafka.borg.test`, all → `192.168.56.120` | `.test` is a reserved TLD. Chosen over sslip.io (DNS-rebind protection often blocks private IPs) and over scripts editing `/etc/hosts`. |
| Host name resolution | The user adds 4 `/etc/hosts` lines once; `make kafka-hosts` prints them. Scripts never edit host files. Tests pass the names to their container with `--add-host`. | Nothing changes on the host without the user; tests don't depend on it. |
| Certificates | openssl in `06-kafka/kafka-tls.sh`: a BorgCloud CA plus one broker certificate with SANs for all 4 names, stored only as Secrets (`kafka-ca`, `kafka-tls`) | No extra pods (nodes at 62–70% memory). Chosen over cert-manager. |
| TLS scope | EXTERNAL listener only (server TLS, no client certs). INTERNAL and CONTROLLER stay plaintext. | Encryption and SNI routing for host clients; in-cluster apps are unchanged. |
| Routing | HAProxy SSL passthrough (`haproxy.org/ssl-passthrough: "true"`) on 4 Ingresses (class `haproxy`), one per name, to per-broker Services | Layer-4 by SNI; Kafka presents its own certificate. |
| node:9094 | Removed (no hostPort; nothing listens on node IPs) | As #12 decided. |

## Layout

```
borg-cloud/06-kafka/
  kafka-tls.sh        # CA + broker cert, created once, stored as Secrets (sourced by install-kafka.sh)
  kafka.yaml          # EXTERNAL listener -> SSL on 9094 (no hostPort); TLS volume;
                      #   Services kafka-external, kafka-N-external; 4 passthrough Ingresses
  install-kafka.sh    # + edge preflight, TLS Secrets, then apply (brokers roll)
  kafka-lib.sh        # + helpers (kafka_names, CA fetch)
  kafka-test.sh       # host checks over TLS via the VIP; node:9094 closed
borg-cloud/vars.sh    # + KAFKA_DOMAIN
borg-cloud/Makefile   # + kafka-ca, kafka-hosts; help updated
borg-cloud/.gitignore # + .kafka-ca.crt
```

## Makefile targets

| Target | Does |
|---|---|
| `make kafka-hosts` | Prints the 4 `/etc/hosts` lines (`192.168.56.120 kafka.borg.test`, …) |
| `make kafka-ca` | Writes the CA certificate (public only) from Secret `kafka-ca` to `borg-cloud/.kafka-ca.crt` |
| `make provision-kafka` | As in #11, plus: requires the edge (IngressClass `haproxy`, VIP answering), creates the TLS Secrets if missing, applies Services and Ingresses |
| `make kafka-test` | Checks below |

The help text notes that `kafka-uninstall` deletes the CA: after a reinstall, clients
must run `make kafka-ca` again.

## Components

### Certificates (`kafka-tls.sh`)

- `ensure_kafka_tls`, run by `install-kafka.sh` after the namespace exists:
  - **CA:** if Secret `kafka-ca` (keys `ca.crt`, `ca.key`) is missing, generate an EC
    P-256 key and a self-signed CA certificate (`CN=BorgCloud Kafka CA`, 3650 days,
    `basicConstraints=critical,CA:TRUE`, `keyUsage=critical,keyCertSign,cRLSign`).
  - **Broker certificate:** if Secret `kafka-tls` (keys `tls.crt`, `tls.key`, `ca.crt`)
    is missing, or its certificate's SANs are not exactly the 4 names for the current
    `KAFKA_DOMAIN`, generate an EC P-256 key (PKCS#8, unencrypted), a CSR, and a
    certificate signed by the CA (1825 days, SANs = the 4 DNS names,
    `extendedKeyUsage=serverAuth`). `tls.crt` holds the leaf followed by the CA.
- Everything happens in `mktemp -d`, removed by a trap. Private keys go to the cluster
  only (`kubectl create secret ... --dry-run=client -o yaml | kubectl apply`). The CA key
  is read back from the Secret when a new broker certificate needs signing.
- Output: `secret/kafka-ca exists (kept)` / `created`; the same for `kafka-tls`
  (`reissued` when the SANs changed).

### Brokers (`kafka.yaml`)

- `start.sh` changes (which rolls the brokers through the existing checksum annotation):
  - `cat /etc/kafka/tls-src/tls.key /etc/kafka/tls-src/tls.crt > /tmp/keystore.pem`
  - `advertised.listeners=INTERNAL://kafka-$N.$H:9092,EXTERNAL://kafka-$N.${KAFKA_DOMAIN}:443`
  - `listener.security.protocol.map=INTERNAL:PLAINTEXT,CONTROLLER:PLAINTEXT,EXTERNAL:SSL`
  - `ssl.keystore.type=PEM`, `ssl.keystore.location=/tmp/keystore.pem`
  - `ssl.client.auth=none`
- Container: remove `hostPort` and the `HOST_IP` env var. Mount Secret `kafka-tls`
  read-only at `/etc/kafka/tls-src`. The `external` port stays 9094 (container only).
- `KAFKA_DOMAIN` is added to the variables `render_kafka` substitutes.

### Routing

- Service `kafka-external`: all brokers, port 9094 → `external`.
- Services `kafka-0-external`, `kafka-1-external`, `kafka-2-external`: selector
  `statefulset.kubernetes.io/pod-name: kafka-N`, port 9094.
- Ingresses (class `haproxy`, annotation `haproxy.org/ssl-passthrough: "true"`):
  `kafka.borg.test` → `kafka-external:9094`; `kafka-N.kafka.borg.test` →
  `kafka-N-external:9094`. Each has one rule, path `/`, `pathType: Prefix`.
- Implementation must confirm the annotation against the controller in use
  (haproxytech `kubernetes-ingress` chart 1.54.2, HAProxy 3.2.15), and that passthrough
  routes by SNI on port 443 while HTTP Ingresses keep working on port 80.

## Error handling

- Existing conventions apply: `set -euo pipefail`, shared helpers, no `cmd | grep -q`
  under pipefail.
- `install-kafka.sh` preflight: IngressClass `haproxy` exists and `http://$VIP_ADDRESS/`
  answers; otherwise it stops with "run: make provision-edge".
- Re-running `provision-kafka` changes nothing: same Secrets (content hashes), same pods.
- The rollout waits for `rollout status` and then the quorum, as in #11.

## Verification

`make kafka-test`:
1. **In-cluster:** unchanged from #11 (topic ISR, produce and consume on 9092, auto-create
   defaults).
2. **TLS through the VIP:** for each of the 4 names, `openssl s_client -connect
   $VIP_ADDRESS:443 -servername <name> -CAfile <ca> -verify_return_error -verify_hostname <name>`
   completes (`Verify return code: 0`).
3. **Kafka over TLS from the host:** `docker run --rm --network host --add-host
   <name>:$VIP_ADDRESS` (×4) `-v <ca and client.properties>` with the Kafka image.
   `client.properties`: `security.protocol=SSL`, `ssl.truststore.type=PEM`,
   `ssl.truststore.location=/tls/ca.crt`. It produces a unique token through
   `kafka.borg.test:443`, then consumes `borg-kafka-test` from the beginning through
   `kafka.borg.test:443` and finds the token. The topic's 3 partitions are led by
   different brokers, so this proves every advertised name routes to its broker.
4. **node:9094 closed:** a TCP connect to `$NODE{1,2,3}_IP:9094` fails.

### Acceptance run (live cluster, before the PR)

1. `make provision-kafka` (the brokers roll to TLS), then again (no change).
2. `make kafka-test`; `make kafka-failover-test`.
3. `make kafka-uninstall`, then `make provision-kafka` (new CA), then `make kafka-test`.
4. `make edge-test`, `edge-failover-test`, `db-test`, `media-test`, `registry-test`.
5. `kubectl top nodes`: every node below ~85% memory.

## Out of scope

Client-certificate authentication (mTLS) and SASL, certificate rotation or expiry
monitoring, TLS on the in-cluster listener, DNS beyond `/etc/hosts`, and changes to
media-service.
