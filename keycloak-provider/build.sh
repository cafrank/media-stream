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
mvn clean package -DskipTests=true   && \
docker build -t kclatest .  && \
docker tag kclatest cafrank/kclatest && \
docker push cafrank/kclatest && \
kubectl -n djmz delete -f k8s-keycloak.yaml && \
kubectl -n djmz apply  -f k8s-keycloak.yaml && \
kubectl -n djmz get pod
