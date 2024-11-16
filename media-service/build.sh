# docker build --build-arg JAR_FILE=target/\*.jar -t media .  && \
#mvn clean package -DskipTests=true   && \
#docker build -t media .  && \
#docker tag media localhost:32000/media   && \
#docker push localhost:32000/media   && \
#microk8s ctr image pull --plain-http localhost:32000/media:latest && \
#kubectl -n djmz delete -f k8s-media.yaml && \
#kubectl -n djmz apply -f k8s-media.yaml  && \
#kubectl -n djmz get pod | grep -v spin


#==================================================
# hub.docker.com: docker login --username=cafrank
#==================================================
mvn clean package -DskipTests=true   && \
docker build --no-cache -t media .  && \
docker tag media cafrank/media3 && \
docker push cafrank/media3 && \
kubectl -n djmz delete -f k8s-media.yaml && \
kubectl -n djmz apply  -f k8s-media.yaml && \
kubectl -n djmz get pod

