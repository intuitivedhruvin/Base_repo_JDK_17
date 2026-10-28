# Application Analysis — Trebol Backend

## Overview
Trebol is an open-source e-commerce REST backend (products, categories, customers, orders, checkout, receipts, users/roles). Source lives in `trebol-backend-monolith/`.

| Item | Value |
|---|---|
| Language / runtime | Java 17 |
| Framework | Spring Boot 3.2.9 (Web, Data JPA, Security, Validation, Actuator) |
| Build tool | Maven (`pom.xml`), produces an executable fat jar |
| Entry point | `org.trebol.BackendApp` |
| Port | 8080 (`SERVER_PORT`) |
| Auth | Stateless JWT (jjwt 0.11.5); login at `POST /public/login` |
| API docs | springdoc OpenAPI UI |
| Health | `/actuator/health`, `/actuator/health/liveness`, `/actuator/health/readiness` |

## Build & run

### Without Docker (JDK 17 + Maven 3.9)
```bash
cd trebol-backend-monolith
mvn verify                 # compile + 117 unit/integration tests
java -jar target/*.jar     # default profile: in-memory H2, seeded from data.sql
```

### With Docker (recommended)
```bash
cd trebol-backend-monolith
cp .env.example .env       # set passwords and JWT key
docker compose up --build  # app + MySQL 8 on http://localhost:8080
bash ../test-endpoints.sh http://localhost:8080
```

### Image only
```bash
docker build -t trebol-api:local trebol-backend-monolith
docker run -p 8080:8080 trebol-api:local    # H2 mode, no external deps
```

## Key dependencies
| Dependency | Purpose |
|---|---|
| spring-boot-starter-web / validation | REST API |
| spring-boot-starter-data-jpa + QueryDSL | Persistence and dynamic filtering |
| h2 (runtime) | Default in-memory DB for preview/tests |
| mariadb-java-client | Production DB driver (works with MySQL 8 / Cloud SQL) |
| spring-boot-starter-security + jjwt | JWT authentication, method-level authorization |
| spring-boot-starter-actuator | Health/readiness probes (added for this POC) |
| transbank-sdk-java | WebPay Plus payment integration (sandbox by default) |
| unirest-java | HTTP client for Mailgun |
| lombok | Boilerplate reduction (compile-time) |

## Profiles
| Profile | Use |
|---|---|
| *(default)* | H2 in-memory, seeded with demo data. Local preview and tests only. |
| `mysql` | MySQL/MariaDB via env vars. Used by docker-compose and Cloud Run. |
| `mailgun` | Enables Mailgun mail service (not used in this POC). |

## Environment variables (`mysql` profile)
| Variable | Required | Default | Notes |
|---|---|---|---|
| `SPRING_PROFILES_ACTIVE` | yes | — | Set to `mysql` |
| `DB_URL` | yes | `jdbc:mariadb://localhost:3306/trebol` | JDBC URL |
| `DB_USER` | yes | `trebol` | |
| `DB_PASSWORD` | yes | — | Secret (Secret Manager in GCP) |
| `JWT_SECRET_KEY` | yes | — | Secret, ≥ 64 characters |
| `DB_POOL_SIZE` | no | 20 | Hikari max pool per instance |
| `DB_POOL_MIN_IDLE` | no | 5 | |
| `DB_CONNECTION_TIMEOUT_MS` | no | 5000 | |
| `DDL_AUTO` | no | `update` | Hibernate schema management |
| `DB_SEED_MODE` | no | `never` | `always` loads `data.sql` demo data; duplicates ignored |
| `CORS_ALLOWED_ORIGINS` | no | `http://localhost:4200` | `;`-separated |
| `JAVA_TOOL_OPTIONS` | no | `-XX:MaxRAMPercentage=75 ...` | Set in image |

Any other property in `application.properties` can be overridden with Spring's relaxed binding (e.g. `TREBOL_API_ITEMS_PER_PAGE=20`).

## External configuration
- `src/main/resources/application.properties` — base config (contains a placeholder JWT key; never use it in production).
- `src/main/resources/application-mysql.properties` — production DB profile, fully env-driven.
- `src/main/resources/data.sql` — demo seed data (MySQL-compatible syntax).
- `src/main/resources/schema-mariadb.sql` — reference schema dump (drops tables; do not run automatically).

## Changes made for the POC
- Added `spring-boot-starter-actuator` with liveness/readiness probe groups and graceful shutdown.
- Added the `mysql` profile.
- Added `Dockerfile`, `.dockerignore`, `docker-compose.yml`, `.env.example`.

## Assumptions
- The app is stateless apart from the database: JWT sessions mean no sticky sessions are needed.
- Images are stored as URLs only, so no shared file storage is required.
- MySQL 8 (Cloud SQL) is an acceptable replacement for MariaDB, since the MariaDB driver supports it.
- Payment (WebPay Plus) stays in sandbox mode, and mail (Mailgun) is disabled.

## Limitations
- Hibernate `ddl-auto=update` manages the schema. That's fine for a POC; production should use Flyway or Liquibase.
- The seed relies on `continue-on-error`, so real SQL errors during seeding are logged, not fatal.
- `PUT`/`DELETE` on some endpoints affect shared demo data, so load tests should focus on read and checkout paths.
- There's no caching layer yet. One will be added if load tests require it.
