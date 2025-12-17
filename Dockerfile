FROM eclipse-temurin:17-jre
WORKDIR /app
EXPOSE 8082
COPY target/timesheet-devops-1.0.jar app.jar
ENTRYPOINT ["java","-jar","app.jar"]