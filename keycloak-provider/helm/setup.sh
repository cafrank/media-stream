# https://www.youtube.com/watch?v=g8LVIr8KKSA&t=308s

kubectl create ns keycloak
helm install -n keycloak keycloak-db bitnami/postgresql-ha

cd ~/git/media-stream/keycloak-provider
kubectl -n keycloak create secret tls  auth-tls-secret  --key="lxci.key.pem" --cert="lxci.crt.pem"
kubectl -n keycloak apply  -f keycloak.yaml

# kubectl create ns foo
# helm install -n foo keycloak-db bitnami/postgresql-ha

kubectl -n keycloak get svc keycloak
kubectl -n keycloak port-forward service/keycloak --address=0.0.0.0 9443:443 &

