FROM openjdk:16-jdk-alpine
#FROM openjdk:18 as my-app
#FROM adoptopenjdk/openjdk11:jdk-11.0.2.9-slim
# mvn package -DskipTests

WORKDIR /opt

ARG JAR_FILE=target/*.jar
COPY ${JAR_FILE} /opt/app.jar
ENTRYPOINT ["java","-jar","/opt/app.jar"]

# docker build --build-arg JAR_FILE=build/libs/\*.jar -t localhost:32000/adapter
