# ─── Stage 1: build ──────────────────────────────────────────────────────────
FROM maven:3.9-eclipse-temurin-25 AS build

WORKDIR /workspace

# Cache Maven dependencies before copying full source (speeds up rebuilds)
COPY pom.xml .
RUN mvn -B -ntp dependency:go-offline

COPY src src
RUN mvn -B -ntp clean package -DskipTests

# Unpack the Spring Boot layered JAR for optimal image layering
RUN java -Djarmode=tools -jar target/*.jar extract --layers --launcher --destination target/extracted

# ─── Stage 2: runtime ────────────────────────────────────────────────────────
FROM eclipse-temurin:25-jre-noble AS runtime

WORKDIR /app

# Run as a non-root user
RUN groupadd --system appgroup && useradd --system --gid appgroup appuser
USER appuser

# Copy layers in dependency order (least-to-most-volatile for best caching)
COPY --from=build /workspace/target/extracted/dependencies/          ./
COPY --from=build /workspace/target/extracted/spring-boot-loader/    ./
COPY --from=build /workspace/target/extracted/snapshot-dependencies/ ./
COPY --from=build /workspace/target/extracted/application/           ./

EXPOSE 8080

# Kubernetes liveness probe: GET /actuator/health/liveness
# Kubernetes readiness probe: GET /actuator/health/readiness
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD wget -qO- http://localhost:8080/actuator/health/liveness || exit 1

ENTRYPOINT ["java", \
    "-XX:+UseContainerSupport", \
    "-XX:MaxRAMPercentage=75.0", \
    "-Dspring.profiles.active=k8s", \
    "org.springframework.boot.loader.launch.JarLauncher"]
