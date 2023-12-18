#FROM --platform=linux/arm64/v8 arm64v8/openjdk:20-slim-buster
FROM openjdk:20-slim-buster

ARG DEBIAN_FRONTEND=noninteractive
EXPOSE 8084

#RUN apt update \
#    && apt upgrade -y \
#    && apt install -y openjdk-18-jre git \
#    && apt clean

RUN mkdir -pv /opt/djmz/media
ADD target/media-service-0.0.1-SNAPSHOT.jar /opt/djmz/media/app.jar

WORKDIR /opt/djmz/media

ENTRYPOINT [ "java", "-jar", "app.jar" ]
