# Deploy media-service to BorgCloud (with an in-cluster image registry)

- **Issue:** #4 (part of epic #1; builds on #2, #3 and #6)
- **Date:** 2026-09-25
- **Status:** Design approved, awaiting spec review

## Goal

`make deploy-media` builds media-service from the current checkout, pushes the image to a
registry running inside BorgCloud, and deploys it with the Helm chart. media-service
uses the cluster's MongoDB replica set (#6) and is reachable from the host at
`http://<any node IP>/api/media`. Deploying a new version is that one command.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Image source | A `registry:3.1.2` registry inside k3s | Chosen over importing tarballs into each node or pushing to Docker Hub: nothing is published, and after the first push only changed layers move. |
| Push path | `kubectl port-forward` to `localhost:5000` during the push | Docker allows plain-HTTP pushes to `localhost` without configuration, so **nothing on the host changes** (no `insecure-registries`, no Docker restart). |
| Pull path | k3s `registries.yaml` on each node mirrors `localhost:5000` → `http://<node IP>:30500` (NodePort) | The same image name works for the push and for the pods. The node's own host-only IP avoids depending on how k3s routes localhost NodePorts. |
| Exposure | Traefik Ingress (k3s built-in), no host rule, path `/api/media` | Reachable on port 80 of any node IP, with no `/etc/hosts` edits. |
| Database | The #6 MongoDB (`mongo` in namespace `databases`), database `media`, user `app` | The chart's own MongoDB is disabled. |
| Base image | `eclipse-temurin:17-jre` | `openjdk:20-slim-buster` no longer exists on Docker Hub, so builds fail. Java 17 is LTS, matches the host JDK and is supported by Spring Boot 2.7. |
| Build | Reuse `media-service/build.sh` | It already takes `IMAGE`, `TAG`, `NAMESPACE`, `VALUES` and `SKIP_BUILD`. |
| `make up` | Includes `provision-registry`, but not `deploy-media` | Deploying an app is not part of building the cluster. |

## Layout

```
borg-cloud/
  04-registry/
    install-registry.sh    # registry + node mirror config (rolling k3s restart)
    registry.yaml          # Deployment, PVC, Services
    registries.yaml        # template for /etc/rancher/k3s/registries.yaml
    registry-test.sh       # push a test image, pull it on every node
  05-media/
    deploy-media.sh        # Secret, port-forward, build.sh, URL check
    media-test.sh          # HTTP checks through Traefik on every node
  vars.sh                  # + registry and media settings
  Makefile                 # + targets below; `up` includes provision-registry
charts/media-service/values-borg.yaml
media-service/Dockerfile   # FROM eclipse-temurin:17-jre
```

New `vars.sh` settings: `REGISTRY_NAMESPACE="registry"`, `REGISTRY_IMAGE="registry:3.1.2"`,
`REGISTRY_NODEPORT="30500"`, `REGISTRY_STORAGE_SIZE="10Gi"`, `MEDIA_NAMESPACE="media"`,
`MEDIA_RELEASE="media-service"`.

## Makefile targets

| Target | Does |
|---|---|
| `make provision-registry` | Step 04: the registry, then node mirror config with a rolling k3s restart where the config changed |
| `make registry-test` | Push a test image; pull it by `localhost:5000/...` on each of the 3 nodes |
| `make deploy-media` | Build, push `localhost:5000/media3:<git-sha>`, `helm upgrade --install` into `media` |
| `make deploy-media TAG=<tag> SKIP_BUILD=1` | Redeploy an image already in the registry |
| `make media-status` | Pods, Ingress, image tag and URL |
| `make media-test` | The HTTP checks below |

`make up` becomes `vagrant-up cluster provision-databases provision-registry`.

## Components

### Registry (`04-registry`)

- Namespace `registry`. A `registry:3.1.2` Deployment with 1 replica, a 10Gi `local-path`
  PVC mounted at `/var/lib/registry`, and the strategy `Recreate` (the volume is
  ReadWriteOnce). Readiness: `GET /v2/` on port 5000.
- Services: ClusterIP `registry` on port 5000 (the port-forward target), and NodePort
  `registry-nodeport` on port 5000 → nodePort `30500` (the node pull path).
- The registry pod is tied to one node by its local-path volume. If that node is down,
  pushes and pulls of new images wait until it is back. Images already on nodes keep running.
- There is no authentication and no TLS. It is reachable only on the host-only network.
- Node config: `/etc/rancher/k3s/registries.yaml` on each node:
  ```yaml
  mirrors:
    "localhost:5000":
      endpoint:
        - "http://<node IP>:30500"
  ```
  `install-registry.sh` renders the file per node, compares it with the node's current
  file, and only if different, installs it and restarts `k3s` on that node. Nodes are
  handled one at a time. After each restart it waits (up to 5 minutes) for the node to be
  Ready before the next. A node that does not come back stops the rollout with an error
  naming it.

### Deploy (`05-media/deploy-media.sh`)

1. Preflight: `kubectl`, `helm`, `docker`, `mvn` on PATH; 3 Ready nodes; the MongoDB
   Secret `mongo-media-app` exists in `databases` (else: "run make provision-databases");
   the registry Deployment is Available (else: "run make provision-registry").
2. Secret `media-service-mongodb` in namespace `media` (created with the namespace if
   needed), key `SPRING_DATA_MONGODB_URI`, set to the app URI (`.../media?authSource=admin&replicaSet=mongo...`,
   as `make db-info` prints it). It is applied on every deploy (`kubectl apply` of a
   client-side dry-run), so a reinstalled database's new password is picked up. The URI
   is passed through stdin, never as a command-line argument.
3. Start `kubectl -n registry port-forward svc/registry 5000:5000` in the background and
   wait until `http://localhost:5000/v2/` answers. A `trap` stops it on any exit.
4. Run `media-service/build.sh` with `IMAGE=localhost:5000/media3`,
   `NAMESPACE=media`, `RELEASE=media-service`, `VALUES=<repo>/charts/media-service/values-borg.yaml`,
   and `KUBECONFIG` pointing at BorgCloud. `TAG` and `SKIP_BUILD` pass through.
   `build.sh` builds, pushes and runs `helm upgrade --install ... --wait --timeout 5m`.
5. Print the deployed tag and `http://192.168.56.121/api/media`.

`build.sh` tags a build of a working tree with uncommitted changes under `media-service/` as
`<sha>-dirty`. Those builds are deployable. The tag makes their origin visible.

### Chart values (`charts/media-service/values-borg.yaml`)

```yaml
image:
  repository: localhost:5000/media3
mongodb:
  enabled: false
externalMongodb:
  existingSecret: media-service-mongodb
ingress:
  enabled: true
  className: traefik
  hosts:
    - host: ""
      paths:
        - path: /api/media
          pathType: Prefix
```

Everything else stays at chart defaults (ClusterIP Service, RBAC, probes on `/`,
384Mi/768Mi memory).

## Error handling

- Scripts use `set -euo pipefail` and the step-03 conventions (`vars.sh`, `die`, `wait_for`
  with `DB_WAIT_TIMEOUT`, pods and events printed on timeout).
- Missing prerequisites fail before any change, with the make target to run.
- A failed push or rollout exits non-zero; the port-forward is always stopped. With
  `helm --wait`, the previous release keeps serving if new pods never become Ready.

## Verification

`make registry-test`: build a one-layer test image (`FROM busybox` + a file), push it as
`localhost:5000/borg-registry-test:<timestamp>`, then for each node run a pod pinned to
that node (`nodeName`) with that image and `imagePullPolicy: Always`, check that it
succeeds, and delete it.

`make media-test`, from the host:
1. For each node IP: `GET http://<ip>/api/media` returns 200 with a JSON array.
2. `POST /api/media` a record with a unique title → 201; `GET /api/media/<title>`
   returns it (on a different node IP than the POST).
3. Cleanup: delete that one record in MongoDB (`media.media`, `{title: <token>}`) via
   `mongosh` in a mongo pod. **Never** `DELETE /api/media`: it deletes every record.

### Acceptance run (live cluster, before the PR)

1. `make provision-registry`, then again (no k3s restarts the second time).
2. `make registry-test`.
3. `make deploy-media`, then `make media-test`.
4. A trivial change under `media-service/`, then `make deploy-media`: the new tag rolls
   out and `media-test` passes.
5. `helm -n media uninstall media-service`, then `make deploy-media` from nothing.

## Out of scope

Registry garbage collection and auth, TLS, a hostname-based Ingress, media-service code
changes (including the GCS streaming endpoint's credentials), and removing the chart's
built-in MongoDB option.
