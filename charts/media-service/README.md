# media-service Helm chart

Deploys the Spring Boot `media-service` and, by default, a single-node MongoDB.

```bash
# From the repo root
helm upgrade --install media-service charts/media-service -n media --create-namespace \
  --set image.tag=<tag>

# Legacy djmz deployment (media-svc name, apisix ingress on api.djmz.com)
helm upgrade --install media-service charts/media-service -n djmz \
  -f charts/media-service/values-djmz.yaml --set image.tag=<tag>

helm test media-service -n media
```

`media-service/build.sh` builds the jar and image, pushes `docker.io/cafrank/media3:<git-sha>`,
and runs `helm upgrade --install` with that tag.

## Key values

| Value | Default | Notes |
|---|---|---|
| `image.repository` / `image.tag` | `docker.io/cafrank/media3` / `appVersion` | Pin a tag; avoid `latest` |
| `containerPort` | `8080` | Exported as `SERVER_PORT` so the app matches the Service |
| `service.name` | fullname | `values-djmz.yaml` sets `media-svc` |
| `service.type` / `service.nodePort` | `ClusterIP` / – | |
| `config` | see values | Non-secret env vars (ConfigMap, `envFrom`). Eureka and Zipkin are disabled |
| `extraEnv` | `[]` | Extra `EnvVar` entries |
| `mongodb.enabled` | `true` | In-chart MongoDB StatefulSet (`docker.io/library/mongo:7.0`) |
| `mongodb.auth.enabled` / `rootPassword` | `false` / – | Root user; the URI is built with credentials |
| `mongodb.persistence.*` | 8Gi, default StorageClass | `enabled: false` uses `emptyDir` |
| `externalMongodb.uri` / `existingSecret` | – | Used when `mongodb.enabled=false` |
| `rbac.create` | `true` | Read-only Role for spring-cloud-kubernetes (configmaps, pods, services, endpoints) |
| `ingress.*` | disabled | networking.k8s.io/v1 Ingress |
| `httpRoute.*` | disabled | Gateway API HTTPRoute; `parentRefs` required |
| `apisixRoute.*` | disabled | APISIX `ApisixRoute` (CRD must be installed) |

The app is configured through `SPRING_DATA_MONGODB_URI`, which always comes from
a Secret. `probes.path` (`/`) is `RootController`, which returns `OK`.
