#FROM --platform=linux/arm64/v8 arm64v8/openjdk:20-slim-buster
#FROM openjdk:20-slim-buster
FROM ubuntu:22.04
RUN apt-get update \
    && apt-get install -y --no-install-recommends openjdk-21-jdk-headless

ARG DEBIAN_FRONTEND=noninteractive
EXPOSE 8080

# RUN apt update \
#    && apt upgrade -y \
#    && apt install -y openjdk-18-jre git \
#    && apt clean

RUN mkdir -pv /opt/djmz/media
ADD target/media-service-0.0.1-SNAPSHOT.jar /opt/djmz/media/app.jar

WORKDIR /opt/djmz/media

ENTRYPOINT [ "java", "-jar", "app.jar" ]
