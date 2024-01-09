#FROM quay.io/keycloak/keycloak:latest as builder
# 23.0.1 internal error on POST https://key.lxci.net:8443/realms/Services/protocol/openid-connect/token
# FROM quay.io/keycloak/keycloak:21.1.2 as builder
# FROM quay.io/keycloak/keycloak:20.0.1 as builder
FROM quay.io/keycloak/keycloak:23.0.3 as builder

# https://jbjerksetmyr.medium.com/how-to-setup-a-keycloak-server-with-external-mysql-database-on-aws-ecs-fargate-in-clustered-mode-edf664a765bf
# Enable health and metrics support
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true
ENV KC_DB=postgres
ENV KC_CACHE=ispn
ENV KC_CACHE_STACK=kubernetes

ENV KC_DB_URL=jdbc:postgresql://34.82.33.112:5432/postgres
ENV KC_DB_USERNAME=postgres
ENV KC_DB_PASSWORD=spock
ENV KC_HOSTNAME=0.0.0.0
#ENV KC_HOSTNAME=34.82.33.112

WORKDIR /opt/keycloak
# for demonstration purposes only, please make sure to use proper certificates in production instead
#RUN keytool -genkeypair -storepass password -storetype PKCS12 -keyalg RSA -keysize 2048 -dname "CN=server" -alias server -ext "SAN:c=DNS:localhost,IP:127.0.0.1" -keystore conf/server.keystore
#RUN curl -k -sL https://www.my12inch.com/org.sparkle-auth.jar -o /opt/keycloak/providers/cf-provider.jar
# openssl pkcs12 -export -in key_lxci_net.pem -inkey my12ss.key.pem -name ‘keycloak’ -out key.lxci.net.p12
#  Passwd: password
ADD key.lxci.net.p12            conf/server.keystore
ADD target/org.sparkle-auth.jar providers/cf-provider.jar

FROM quay.io/keycloak/keycloak:23.0.3
COPY --from=builder /opt/keycloak/ /opt/keycloak/

RUN /opt/keycloak/bin/kc.sh build --db=postgres --features=preview --health-enabled=true --metrics-enabled=true
# RUN /opt/keycloak/bin/kc.sh show-config
# RUN cat /opt/keycloak/conf/keycloak.conf

ENV KEYCLOAK_ADMIN=admin
ENV KEYCLOAK_ADMIN_PASSWORD=admin

ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "start", "--optimized"]
#ENTRYPOINT ["sleep", "5000"]
#ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "start"]
#ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "start",  "--db=postgres", "--db-url=jdbc:postgresql://34.82.33.112:5432/postgres", "--db-username=postgres", "--db-password=spock"]
#ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "start",  "--db=postgres", "--db-url=jdbc:postgresql://34.82.33.112:5432/postgres"]
#ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "start-dev"]
# /opt/keycloak/bin/kc.sh start --db=postgres --db-url=jdbc:postgresql://34.82.33.112:5432/postgres --db-username=postgres --db-password=spock
