mvn clean package -DskipTests=true  && \
docker build -t hello . && \
docker tag hello cafrank/hello && \
docker push cafrank/hello && \
kubectl -n djmz run hello --image cafrank/hello --port 80 && \
kubectl -n djmz expose pod hello --port 80 

# kubectl -n djmz run hello-shell --rm -i --tty --image cafrank/hello -- bash

