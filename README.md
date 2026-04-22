# ms-aws-eks-demo

A minimal Spring Boot 4 (Java 25) REST service exposing a CRUD API for `Todo` backed by an in-memory H2 database. Built to later be deployed on AWS EKS.

## Stack

- Java 25
- Maven
- Spring Boot 4.0.5 (`spring-boot-starter-web`, `spring-boot-starter-data-jpa`, `spring-boot-starter-validation`)
- H2 in-memory database

## Prerequisites

- JDK 25 installed and on `PATH` (`java -version` should print `25`)
- Maven 3.9+ (or use the Maven distribution your IDE ships with)

## Run

```bash
mvn spring-boot:run
```

The app starts on http://localhost:8080.

The H2 console is available at http://localhost:8080/h2-console
(JDBC URL: `jdbc:h2:mem:tododb`, user: `sa`, no password).

## API

Base path: `/api/todos`

| Method | Path              | Description       |
| ------ | ----------------- | ----------------- |
| GET    | `/api/todos`      | List all todos    |
| GET    | `/api/todos/{id}` | Get one todo      |
| POST   | `/api/todos`      | Create a todo     |
| PUT    | `/api/todos/{id}` | Update a todo     |
| DELETE | `/api/todos/{id}` | Delete a todo     |

### Example

```bash
# Create
curl -X POST http://localhost:8080/api/todos \
  -H "Content-Type: application/json" \
  -d '{"title":"Buy milk","description":"2L whole","completed":false}'

# List
curl http://localhost:8080/api/todos

# Update
curl -X PUT http://localhost:8080/api/todos/1 \
  -H "Content-Type: application/json" \
  -d '{"title":"Buy milk","description":"2L whole","completed":true}'

# Delete
curl -X DELETE http://localhost:8080/api/todos/1
```

## Build

```bash
mvn clean package
java -jar target/ms-aws-eks-demo-0.0.1-SNAPSHOT.jar
```

## Test

```bash
mvn test
```

## Deploy to AWS EKS

See [`docs/EKS_DEPLOYMENT_GUIDE.md`](docs/EKS_DEPLOYMENT_GUIDE.md) for the full step-by-step guide.

**High-level flow:**

```
push to main
  └─ GitHub Actions
       ├─ mvn test
       ├─ docker build → push to Amazon ECR
       └─ kubectl apply → Amazon EKS
                              ├─ Deployment (2–10 replicas, rolling update)
                              ├─ Service (ClusterIP)
                              ├─ Ingress (AWS ALB, /api/* + /actuator/health/*)
                              └─ HPA (CPU 70% / Memory 80%)
```

**Required GitHub secrets/variables:** `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `ECR_REPOSITORY`, `EKS_CLUSTER`.
