# docker build --build-arg JAR_FILE=target/\*.jar -t adapter .  && \
mvn clean package -DskipTests=true   && \
docker build -t adapter .  && \
docker tag adapter localhost:32000/adapter   && \
docker push localhost:32000/adapter   && \
microk8s ctr image pull --plain-http localhost:32000/adapter:latest && \
kubectl -n djmz delete -f k8s-atapter.yaml && \
kubectl -n djmz apply -f k8s-atapter.yaml  && \
kubectl -n djmz get pod
k logs adapter-644d8b8d97-gbpwq

# THis services depends on:
#   - mysql
#   - zipkin
