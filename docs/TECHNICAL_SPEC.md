# Technical Specification — ms-aws-eks-demo

- **Version:** 0.0.1-SNAPSHOT
- **Status:** Draft
- **Owner:** TBD
- **Last updated:** 2026-04-22

---

## 1. Overview

`ms-aws-eks-demo` is a minimal Java microservice that exposes a CRUD REST API for a `Todo` resource. It is intentionally small and self-contained so it can be used as a reference workload to exercise build, packaging, containerization, and deployment to Amazon EKS.

### 1.1 Goals

- Provide a working Spring Boot service with a complete CRUD surface for one resource.
- Use an in-memory database (H2) so the service is runnable with no external dependencies.
- Establish the build baseline (JDK 25 + Maven + Spring Boot 4) that later iterations (container image, Helm chart, EKS deployment) will build on.

### 1.2 Non-goals (current phase)

- Authentication, authorization, or multi-tenancy.
- Persistence that survives process restart (H2 is in-memory only).
- Horizontal scaling correctness — the current storage is per-pod and **not shared**.
- Observability beyond Spring Boot defaults (no Actuator, metrics, tracing yet).
- CI/CD, container image, Helm chart, or EKS manifests (planned for later phases).

---

## 2. Technology Stack

| Concern          | Choice                                                                 |
| ---------------- | ---------------------------------------------------------------------- |
| Language         | Java 25 (LTS, JEP-preview-free subset)                                 |
| Build            | Maven 3.9+                                                             |
| Framework        | Spring Boot 4.0.5 (Spring Framework 7)                                 |
| Web              | `spring-boot-starter-web` (embedded Tomcat, Spring MVC)                |
| Persistence      | `spring-boot-starter-data-jpa` (Hibernate 7.x)                         |
| Validation       | `spring-boot-starter-validation` (Jakarta Bean Validation)             |
| Database         | H2 2.x, in-memory, `MODE=LEGACY`                                       |
| JSON             | Jackson 3 (shipped by Spring Boot 4)                                   |
| Testing          | `spring-boot-starter-test` (JUnit 5, Mockito, AssertJ)                 |
| Packaging        | Executable Spring Boot JAR                                             |
| Target runtime   | OpenJDK 25 on Linux (future: container on EKS)                         |

### 2.1 Version rationale

- **JDK 25**: current LTS; Spring Boot 4 officially supports Java 25.
- **Spring Boot 4.0.5**: latest GA at time of writing (Mar 26, 2026); first 4.x line to baseline on Spring Framework 7 and Jackson 3.
- **H2**: zero-ops dependency appropriate for a demo; `MODE=LEGACY` keeps behavior compatible with examples written against older H2.

---

## 3. Architecture

### 3.1 Component diagram

```
                 ┌──────────────────────────────────────────┐
                 │            Spring Boot Process           │
                 │                                          │
  HTTP ──► 8080 ─┤ Embedded Tomcat                          │
                 │   └─ DispatcherServlet                   │
                 │        └─ TodoController (REST)          │
                 │             └─ TodoService (@Service)    │
                 │                  └─ TodoRepository (JPA) │
                 │                       └─ Hibernate       │
                 │                            └─ HikariCP   │
                 │                                 └─ H2 (mem) │
                 └──────────────────────────────────────────┘
```

### 3.2 Layering

- **Controller (`com.example.todo.controller`)** — HTTP adapter. Validates input (`@Valid`), translates domain exceptions to HTTP responses via `@ExceptionHandler`.
- **Service (`com.example.todo.service`)** — Business logic: ID assignment on create, timestamp stamping, existence checks.
- **Repository (`com.example.todo.repository`)** — Spring Data JPA repository interface. No custom queries.
- **Model (`com.example.todo.model`)** — JPA `@Entity` also used as the HTTP request/response body for simplicity.

### 3.3 Package layout

```
com.example.todo
├── TodoApplication            # @SpringBootApplication entry point
├── controller.TodoController  # REST endpoints at /api/todos
├── service.TodoService        # Business logic
├── service.TodoNotFoundException
├── repository.TodoRepository  # extends JpaRepository<Todo, Long>
└── model.Todo                 # JPA entity
```

### 3.4 Key design decisions

- **Entity as DTO.** For a demo-sized API, the JPA entity doubles as the request/response payload. This will not scale to richer domains — the agreed evolution is to introduce dedicated `TodoRequest` / `TodoResponse` records once any field needs to diverge (e.g. hiding `updatedAt`, adding computed fields).
- **Constructor injection.** All collaborators are injected via constructors (no field injection). This keeps classes testable and avoids `@Autowired` on fields.
- **Local exception handler.** `@ExceptionHandler(TodoNotFoundException.class)` is declared on the controller rather than in a global `@ControllerAdvice` because the domain currently has a single resource. Promote to advice when a second controller appears.
- **`spring.jpa.open-in-view=false`.** Open-session-in-view is disabled so lazy-loading cannot silently trigger database calls during response serialization — important for predictable latency.

---

## 4. Data Model

### 4.1 Entity: `Todo`

| Field         | Java type   | Column           | Constraints                        | Notes                               |
| ------------- | ----------- | ---------------- | ---------------------------------- | ----------------------------------- |
| `id`          | `Long`      | `id` (PK)        | `GenerationType.IDENTITY`          | Assigned by DB on insert.           |
| `title`       | `String`    | `title`          | `@NotBlank`, `@Size(max=200)`      | Required on create and update.      |
| `description` | `String`    | `description`    | `@Size(max=2000)`, nullable        | Optional.                           |
| `completed`   | `boolean`   | `completed`      | not null (primitive)               | Defaults to `false`.                |
| `createdAt`   | `Instant`   | `created_at`     | set by service on create           | UTC.                                |
| `updatedAt`   | `Instant`   | `updated_at`     | set by service on create & update  | UTC.                                |

### 4.2 DDL (generated by Hibernate)

```sql
CREATE TABLE todo (
    id          BIGINT GENERATED BY DEFAULT AS IDENTITY,
    completed   BOOLEAN NOT NULL,
    created_at  TIMESTAMP(6) WITH TIME ZONE,
    description VARCHAR(2000),
    title       VARCHAR(200) NOT NULL,
    updated_at  TIMESTAMP(6) WITH TIME ZONE,
    PRIMARY KEY (id)
);
```

### 4.3 Database configuration

- URL: `jdbc:h2:mem:tododb;DB_CLOSE_DELAY=-1;MODE=LEGACY`
- `DB_CLOSE_DELAY=-1` keeps the in-memory DB alive for the JVM lifetime (would otherwise be dropped when the last connection closes).
- Schema is managed by `spring.jpa.hibernate.ddl-auto=update`. This is acceptable for an in-memory demo; a real deployment must switch to `validate` and manage schema via Flyway or Liquibase.

---

## 5. HTTP API

All endpoints live under `/api/todos`. Content type is `application/json;charset=UTF-8`.

### 5.1 Endpoints

| # | Method | Path                | Success      | Failure codes          | Description               |
| - | ------ | ------------------- | ------------ | ---------------------- | ------------------------- |
| 1 | GET    | `/api/todos`        | 200 OK       | —                      | List all todos.           |
| 2 | GET    | `/api/todos/{id}`   | 200 OK       | 404                    | Get one todo.             |
| 3 | POST   | `/api/todos`        | 201 Created  | 400                    | Create a todo.            |
| 4 | PUT    | `/api/todos/{id}`   | 200 OK       | 400, 404               | Full update of a todo.    |
| 5 | DELETE | `/api/todos/{id}`   | 204 No Content | 404                  | Delete a todo.            |

### 5.2 Request / response shape

```json
{
  "id": 1,
  "title": "Buy milk",
  "description": "2L whole",
  "completed": false,
  "createdAt": "2026-04-22T14:20:11.064Z",
  "updatedAt": "2026-04-22T14:20:11.064Z"
}
```

- `POST` accepts the same shape without `id`, `createdAt`, `updatedAt` (they are ignored server-side; the service always stamps them).
- `PUT` is a full replacement of mutable fields (`title`, `description`, `completed`). Timestamps and id are never accepted from the client.

### 5.3 Validation rules

- `title`: required, 1–200 chars (non-blank).
- `description`: optional, ≤ 2000 chars.
- `completed`: boolean.
- Validation failures produce Spring's default `400 Bad Request` with a problem-detail body.

### 5.4 Error envelope for `TodoNotFoundException`

```json
{
  "status": 404,
  "error": "Not Found",
  "message": "Todo with id 42 not found"
}
```

### 5.5 Example — create / read / update / delete

```bash
# Create
curl -X POST http://localhost:8080/api/todos \
  -H "Content-Type: application/json" \
  -d '{"title":"Buy milk","description":"2L whole","completed":false}'

# Read
curl http://localhost:8080/api/todos/1

# Update
curl -X PUT http://localhost:8080/api/todos/1 \
  -H "Content-Type: application/json" \
  -d '{"title":"Buy milk","description":"2L whole","completed":true}'

# Delete
curl -X DELETE http://localhost:8080/api/todos/1
```

---

## 6. Configuration

| Property                                  | Default                                       | Purpose                                         |
| ----------------------------------------- | --------------------------------------------- | ----------------------------------------------- |
| `spring.application.name`                 | `ms-aws-eks-demo`                             | Used in logs and future service discovery.      |
| `server.port`                             | `8080`                                        | HTTP listener.                                  |
| `spring.datasource.url`                   | `jdbc:h2:mem:tododb;DB_CLOSE_DELAY=-1;...`    | In-memory H2.                                   |
| `spring.jpa.hibernate.ddl-auto`           | `update`                                      | Schema managed by Hibernate for the demo.       |
| `spring.jpa.show-sql`                     | `true`                                        | Log SQL (demo only; disable in prod).           |
| `spring.jpa.open-in-view`                 | `false`                                       | Prevent lazy-loading during rendering.          |
| `spring.h2.console.enabled`               | `true`                                        | Enables `/h2-console` endpoint.                 |
| `spring.h2.console.path`                  | `/h2-console`                                 | Path of the H2 web console.                     |

All properties are plain `application.properties`; no profile-specific files yet. When EKS work begins, a `application-k8s.properties` (or env-var overrides) will be added.

---

## 7. Build & Run

### 7.1 Prerequisites

- JDK 25 (`java -version` → `25.x`).
- Maven 3.9+ (confirmed working on 3.9.6).
- On JDK 25 + Maven 3.9, benign warnings about `sun.misc.Unsafe` and Jansi are emitted by Maven itself; they do not affect the build.

### 7.2 Common commands

```bash
mvn clean compile          # compile only
mvn test                   # run unit + context tests
mvn spring-boot:run        # run the app locally
mvn clean package          # produces target/ms-aws-eks-demo-0.0.1-SNAPSHOT.jar
java -jar target/ms-aws-eks-demo-0.0.1-SNAPSHOT.jar
```

### 7.3 Verified environment

| Tool  | Version                               |
| ----- | ------------------------------------- |
| JDK   | Oracle OpenJDK 25.0.2 LTS (build 25.0.2+10-LTS-69) |
| Maven | Apache Maven 3.9.6                    |
| OS    | Windows 11 (amd64); target Linux/amd64 |

---

## 8. Testing Strategy

### 8.1 Current coverage

- `TodoApplicationTests#contextLoads` — boots the full Spring context, creates the JPA schema on H2, and fails fast on any misconfigured bean.

### 8.2 Planned (next phase)

- `@WebMvcTest(TodoController.class)` — controller-layer tests with `MockMvc`, covering happy paths, validation 400s, and 404 mapping.
- `@DataJpaTest` on `TodoRepository` — CRUD over H2 to guarantee JPA mapping is correct.
- Service tests for `TodoService.update` and `delete` on a missing id.
- `@SpringBootTest(webEnvironment = RANDOM_PORT)` smoke test for end-to-end round trips.

---

## 9. Observability (current state)

- Logging: Spring Boot default (Logback) to stdout.
- Health/metrics/tracing: not wired in yet. The intended next step is to add `spring-boot-starter-actuator`, expose `/actuator/health`, `/actuator/info`, and — for EKS — `readiness` and `liveness` probes.

---

## 10. Security Posture

- No authentication/authorization. The API is fully open.
- H2 console is enabled at `/h2-console` — acceptable while the service only runs locally; **must be disabled** before the service is exposed beyond a developer machine.
- Input validation is enforced by Bean Validation on `@RequestBody` payloads.
- No secrets are stored in the codebase.

---

## 11. Operational Concerns & Limitations

- **Storage is in-memory per process.** Restart loses all data. Horizontal replicas do **not** share state; a single instance only.
- **No pagination** on `GET /api/todos` — acceptable for a demo dataset, unacceptable for production.
- **`PUT` is full replacement only.** There is no `PATCH` today.
- **Error model is ad-hoc.** Spring 4 ships `ProblemDetail` (RFC 9457); a future iteration should switch handlers to return `ProblemDetail` consistently.

---

## 12. Roadmap

1. **Container image** — add a multi-stage `Dockerfile` (eclipse-temurin 25 → distroless) and a `docker-compose.yml` for local runs.
2. **Observability** — add Actuator, Micrometer, structured JSON logging.
3. **Persistent database** — switch H2 for PostgreSQL (Amazon RDS/Aurora) behind Flyway migrations.
4. **Kubernetes manifests / Helm chart** — Deployment, Service, HPA, ConfigMap, Secret, probes mapped to `/actuator/health`.
5. **AWS EKS deployment** — cluster bootstrap (eksctl or Terraform), ALB ingress, IRSA for RDS access, ECR pipeline.
6. **CI/CD** — GitHub Actions (or CodeBuild) building + testing + publishing image to ECR on merge to `main`.
7. **Auth** — introduce Spring Security + OAuth2 resource server with Cognito or Auth0.

---

## 13. Glossary

- **EKS** — Amazon Elastic Kubernetes Service.
- **Spring Data JPA** — Spring module that wraps JPA/Hibernate behind repository interfaces.
- **DDL-auto update** — Hibernate mode where the schema is adjusted to match entities on startup.
- **Open-session-in-view** — Spring pattern that keeps the JPA session open for the whole HTTP request; disabled here.
