# syntax=docker/dockerfile:1

# --- Build stage: compile the Spring Boot fat jar ---
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /build
COPY pom.xml .
# Pre-fetch dependencies for better layer caching
RUN mvn -q -B dependency:go-offline
COPY src ./src
RUN mvn -q -B clean package -DskipTests

# --- Runtime stage: run the jar with the Drill4J agent attached ---
FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=build /build/target/drill4j-sample-app.jar /app/app.jar
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# The Drill4J native agent (libdrill_agent.so) is provided at runtime via the
# shared "agent-files" volume mounted at /data (see docker-compose.yml). The
# entrypoint attaches it only when DRILL_AGENT_ENABLED=true.
EXPOSE 8080
ENTRYPOINT ["/app/entrypoint.sh"]
