# Legacy manifests (archived)

Superseded by the Helm chart in [`charts/media-service`](../../charts/media-service).
Kept for reference only; `build.sh` no longer applies them.

| File | Replaced by |
|---|---|
| `k8s-media.yaml` | chart `deployment.yaml` / `service.yaml` (`values-djmz.yaml` keeps the `media-svc` name and GKE NEG annotation) |
| `k8s-ingress.yaml` (media route) | `ingress.*` values (`values-djmz.yaml` reproduces `api.djmz.com/api/media` via apisix) |
| `k8s-apisix-route.yaml` | `apisixRoute.*` values |
| `k8s-gw-api.yaml` | `httpRoute.*` values (the Gateway itself is cluster infrastructure) |
| `k8s-secret.yaml` | chart `secret.yaml` (`SPRING_DATA_MONGODB_URI`) / `externalMongodb.existingSecret` |
| `k8s-mysql*.yaml`, `k8s-pgsql.yaml`, `k8s-db-storage-volume.yaml` | not used by media-service (it only uses MongoDB); optional in-chart MongoDB via `mongodb.*` |
| `k8s-egress.yaml` | not carried over (its selector matched no pods) |
| `ApisixRoute.yaml` | APISIX CRD — install with the APISIX ingress controller chart, not per-app |

The keycloak (`keycloak-svc`) and auth adapter (`adapter-svc`) routes in
`k8s-ingress.yaml`, `k8s-apisix-route.yaml` and `k8s-gw-api.yaml` belong to
other services and are not part of this chart.

## Migrating a live djmz deployment

See the header of [`values-djmz.yaml`](../../charts/media-service/values-djmz.yaml):
delete `deploy/media` and `svc/media-svc` and drop the `/api/media` path from
`ingress/djmz-ingress-http` before the first `helm upgrade --install`, since
Helm refuses to adopt resources created by `kubectl apply`.
