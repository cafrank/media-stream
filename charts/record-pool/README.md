# record-pool Helm chart

Deploys the RecordPool web app: the Expo static export (`npx expo export --platform web`)
served by unprivileged nginx on port 8080 (`record-pool/Dockerfile`, `record-pool/nginx.conf`).
Only the web target runs in a cluster; the iOS and Android builds are not deployed.

```bash
# From the repo root
helm upgrade --install record-pool charts/record-pool -n record-pool --create-namespace \
  --set image.tag=<tag>

# BorgCloud: use `make deploy-record-pool` in borg-cloud/ (build, push, upgrade)
helm upgrade --install record-pool charts/record-pool -n record-pool \
  -f charts/record-pool/values-borg.yaml --set image.tag=<tag>

helm test record-pool -n record-pool
```

`record-pool/build.sh` builds the image, pushes `<image>:<git-sha>` and `<image>:<appVersion>`,
and runs `helm upgrade --install` with the git-sha tag.

## Key values

| Value | Default | Notes |
|---|---|---|
| `image.repository` / `image.tag` | `docker.io/cafrank/record-pool` / `appVersion` | Pin a tag; avoid `latest` |
| `replicaCount` | `1` | `values-borg.yaml`: `2` |
| `podAntiAffinity` | `""` | `soft` or `hard` spreads replicas across nodes. Ignored when `affinity` is set |
| `containerPort` | `8080` | Must match `listen` in `record-pool/nginx.conf` |
| `service.type` / `service.port` | `ClusterIP` / `80` | |
| `probes.path` | `/healthz` | Served by nginx, independent of the app |
| `podSecurityContext` / `securityContext` | uid 101, read-only root FS | `/tmp` is an in-memory `emptyDir` |
| `ingress.*` | disabled | networking.k8s.io/v1 Ingress. `values-borg.yaml`: `haproxy`, path `/` on the VIP |

## API base URL

The app calls the MediaStream API at `EXPO_PUBLIC_API_URL`, which Expo inlines into the
bundle at **build time** (`docker build --build-arg EXPO_PUBLIC_API_URL=...`, or the
same variable for `build.sh`). It is not a chart value. Empty (the default) means the
same origin as the page, so on BorgCloud `/api/media` on the VIP reaches media-service,
whose Ingress has the longer, more specific prefix.

## Routes

`nginx.conf` serves each exported route as its page (`/RecordPoolApp` →
`RecordPoolApp.html`) and falls back to `index.html` for anything else, so deep links
never return 404. `/_expo/static/` holds content-hashed files and is cached for a year;
everything else is `no-cache`.
