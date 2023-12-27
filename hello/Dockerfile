# Dockerfile
FROM openjdk:8
VOLUME /tmp
RUN mkdir /opt/application
COPY . /opt/application
WORKDIR /opt/application
# RUN /application/mvnw install
# RUN mv /application/target/*.jar /application/app.jar

ADD target/hello-0.0.1-SNAPSHOT.jar /opt/application/app.jar
RUN ls -l  /opt/application
ENTRYPOINT ["java","-Djava.security.egd=file:/dev/./urandom","-jar","/opt/application/app.jar"]

