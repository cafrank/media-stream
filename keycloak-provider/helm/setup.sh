
cd ~/git/media-stream/keycloak-provider
kubectl -n keycloak create secret tls  auth-tls-secret  --key="lxci.key.pem" --cert="lxci.crt.pem"
kubectl -n keycloak apply  -f keycloak.yaml

