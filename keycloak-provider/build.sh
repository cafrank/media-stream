#==================================================
# microk8s enable registry:size=40Gi
# docker build --build-arg JAR_FILE=target/\*.jar -t adapter .  && \
#==================================================
#mvn clean package -DskipTests=true   && \
#docker build -t kclatest .  && \
#docker tag kclatest localhost:32000/kclatest   && \
#docker push localhost:32000/kclatest   && \
#microk8s ctr image pull --plain-http localhost:32000/kclatest:latest && \
#kubectl -n djmz delete -f k8s-keycloak.yaml && \
#kubectl -n djmz apply  -f k8s-keycloak.yaml && \
#kubectl -n djmz get pod

#==================================================
# hub.docker.com: docker login --username=cafrank
#==================================================
#kubectl create ns djmz
#kubectl -n djmz create secret tls lxci-net-tls --key="lxci.key.pem" --cert="lxci.crt.pem"
#docker build --no-cache -t kclatest .  && \

mvn clean package -DskipTests=true   && \
docker build -t kclatest .  && \
docker tag kclatest cafrank/kclatest && \
docker push cafrank/kclatest && \
kubectl -n djmz delete -f k8s-keycloak.yaml
kubectl -n djmz apply  -f k8s-keycloak.yaml && \
kubectl -n djmz get pod

#==================================================
# Artifact Registry https://cloud.google.com/artifact-registry/docs/docker/pushing-and-pulling
#==================================================
# gcloud artifacts repositories create cfrepo --repository-format=DOCKER --location us-central1
# gcloud auth configure-docker  us-central1-docker.pkg.dev
# https://console.cloud.google.com/iam-admin/iam?_ga=2.267966542.191362536.1704219057-4848244.1701377069&_gac=1.250491252.1703518319.Cj0KCQiA7aSsBhCiARIsALFvovxzXcIETm6n6kwJo_9aeMDWcW-Cp83nZ8iznzdbN82LAh0A3NfZY-waAmr8EALw_wcB&project=my-map-project-186104
#   Grant "Service Account Token Creator" to grhex1@gmail.com
# gcloud auth print-access-token --impersonate-service-account grhex1@gmail.com
# gcloud auth print-access-token | docker login -u oauth2accesstoken --password-stdin https://us-central1-docker.pkg.dev

docker tag kclatest us-central1-docker.pkg.dev/my-map-project-186104/cfrepo/kclatest
docker push         us-central1-docker.pkg.dev/my-map-project-186104/cfrepo/kclatest
