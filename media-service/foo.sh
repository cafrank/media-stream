curl -i "http://10.1.113.70:9180/apisix/admin/routes" -X PUT -d '
{
  "id": "getting-started-ip",
  "uri": "/api/media",
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "10.1.113.184:8084": 1
    }
  }
}'


kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
