FROM quay.io/keycloak/keycloak:latest as builder
# 23.0.1 internal error on POST https://key.lxci.net:8443/realms/Services/protocol/openid-connect/token
# FROM quay.io/keycloak/keycloak:20.0.1 as builder
# FROM quay.io/keycloak/keycloak:23.0.0 as builder

# https://jbjerksetmyr.medium.com/how-to-setup-a-keycloak-server-with-external-mysql-database-on-aws-ecs-fargate-in-clustered-mode-edf664a765bf
# Enable health and metrics support
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true

# Configure a database vendor
# ENV KC_DB=mysql
# ENV KC_DB=dev-file
ENV KC_DB=postgres

WORKDIR /opt/keycloak
# for demonstration purposes only, please make sure to use proper certificates in production instead
#RUN keytool -genkeypair -storepass password -storetype PKCS12 -keyalg RSA -keysize 2048 -dname "CN=server" -alias server -ext "SAN:c=DNS:localhost,IP:127.0.0.1" -keystore conf/server.keystore
#RUN curl -k -sL https://www.my12inch.com/org.sparkle-auth.jar -o /opt/keycloak/providers/cf-provider.jar
# openssl pkcs12 -export -in key_lxci_net.pem -inkey my12ss.key.pem -name ‘keycloak’ -out key.lxci.net.p12
#  Passwd: password
ADD key.lxci.net.p12            conf/server.keystore
ADD target/org.sparkle-auth.jar providers/cf-provider.jar


# The database vendor.
#db=postgres

# The username of the database user.
#db-username=keycloak

# The password of the database user.
#db-password=password

# The full database JDBC URL. If not provided, a default URL is set based on the selected database vendor.
#db-url=jdbc:postgresql://localhost/keycloak

RUN /opt/keycloak/bin/kc.sh build --db=postgres

FROM ubuntu:latest
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && apt-get install -y apt-utils
RUN apt-get install -y iputils-ping
RUN apt-get update && apt-get -qq -y install curl
RUN apt-get install net-tools

FROM quay.io/keycloak/keycloak:latest
COPY --from=builder /opt/keycloak/ /opt/keycloak/
RUN echo "db=postgres"                      >> /opt/keycloak/conf/keycloak.conf
RUN echo "db-username=postgres"             >> /opt/keycloak/conf/keycloak.conf
RUN echo "db-username=spock"                >> /opt/keycloak/conf/keycloak.conf
RUN echo "db-url=jdbc:postgresql://34.82.33.112:5432/postgres" >> /opt/keycloak/conf/keycloak.conf

ENV KEYCLOAK_ADMIN=admin
ENV KEYCLOAK_ADMIN_PASSWORD=admin

ENV KC_HTTP_ENABLED=true
ENV KC_HOSTNAME_STRICT=false
ENV KC_HOSTNAME_STRICT_HTTPS=false
#ENV KC_HTTP_PORT=8380

# change these values to point to a running postgres instance
# ENV KC_DB_URL=jdbc:mysql://mysql:3306/my12
# ENV KC_DB_USERNAME=my12
# ENV KC_DB_PASSWORD=mysql
# ENV KC_HOSTNAME=localhost

ENV KC_DB_VENDOR=postgres
ENV KC_DB_URL=jdbc:postgresql://34.82.33.112:5432/postgres
ENV KC_DB_USERNAME=postgres
ENV KC_DB_PASSWORD=spock
ENV KC_HOSTNAME=34.82.33.112

#ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "start"]
ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "start",  "--db=postgres", "--db-url=jdbc:postgresql://34.82.33.112:5432/postgres"]
#ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "start-dev"]
#/opt/keycloak/bin/kc.sh start --db=postgres --db-url=jdbc:postgresql://34.82.33.112:5432/postgres --db-username=postgres --db-password=spock
