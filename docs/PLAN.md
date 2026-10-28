# POC Plan — Trebol Backend on GCP

Owner: intuitivedhruvin · Cloud: GCP · Timeline: 1 work week (5 days)

## 1. Application summary
| Item | Value |
|---|---|
| Framework | Spring Boot 3.2.9, Java 17, Maven |
| Entry point | `org.trebol.BackendApp` (fat jar via `spring-boot-maven-plugin`) |
| Port | 8080 |
| Persistence | JPA + QueryDSL; H2 in-memory by default, MariaDB driver + `schema-mariadb.sql` present |
| Auth | JWT (jjwt 0.11.5) |
| Optional integrations | Mailgun (profile `mailgun`) |
| Tests | 117 test classes (`mvn verify`) |
| Smoke test | `test-endpoints.sh` (already in repo) |

**Key constraint:** H2 in-memory makes each instance hold its own data → not stateless. Production uses Cloud SQL (MySQL 8, compatible with the MariaDB driver/schema).

## 2. Target architecture
```
 Developer ──PR──▶ GitHub ──▶ GitHub Actions
                               │  build · test · Sonar/Checkstyle · docker build · Trivy · push
                               ▼
                       Artifact Registry
                               │ (merge to main) deploy via Workload Identity Federation
                               ▼
 Users ─HTTPS─▶ Cloud Run service "trebol-api"  (min 2, max N instances, managed TLS, built-in LB)
                    │  Serverless VPC / Cloud SQL connector       │ secrets
                    ▼                                             ▼
              Cloud SQL MySQL 8 (HA, private IP)           Secret Manager (DB pwd, JWT key)
                    │
 Cloud Logging + Cloud Monitoring (dashboard, alert policies → email)
```

## 3. Tool choices (and why)
| Need | Choice | Why |
|---|---|---|
| Container platform | **Cloud Run** | Managed HTTPS URL, built-in LB, autoscaling on concurrency, revision-based rolling/canary deploys and instant rollback — fits a 1-week timeline. GKE Autopilot considered; rejected for setup time. |
| Database | Cloud SQL MySQL 8 (regional HA) | Makes app stateless; existing MariaDB driver works against MySQL. |
| Registry | Artifact Registry | Native to Cloud Run, vulnerability scanning available. |
| CI/CD | GitHub Actions | Repo already on GitHub with an existing workflow. |
| Cloud auth from CI | Workload Identity Federation | No long-lived JSON keys in GitHub secrets. |
| Secrets | Secret Manager | Mounted as env vars on Cloud Run; per-secret IAM. |
| Image scan | Trivy | Fails pipeline on CRITICAL CVEs. |
| Code quality | SonarCloud (existing) / Checkstyle fallback | Already wired in repo. |
| IaC | Terraform | Bonus criteria; reproducible env. |
| Load test | k6 | Scriptable, handles 10k VUs, outputs P95/error rate. |
| Monitoring | Cloud Logging/Monitoring + Spring Actuator | Zero extra infra; built-in Cloud Run metrics cover CPU, memory, requests, errors, latency. |

## 4. Identities (least privilege)
| Identity | Roles |
|---|---|
| `gh-ci` SA (via WIF) | `artifactregistry.writer`, `run.developer`, `iam.serviceAccountUser` on runtime SA only |
| `trebol-run` runtime SA | `cloudsql.client`, `secretmanager.secretAccessor` on its 2 secrets, `logging.logWriter`, `monitoring.metricWriter` |

## 5. Scaling & HA design
- Cloud Run: min 2 / max 50 instances, 2 vCPU / 2 GiB, concurrency ~80, CPU always allocated.
- Startup probe + liveness probe on `/actuator/health/{liveness,readiness}`.
- Rolling: new revision gets traffic only after startup probe passes; canary via `--no-traffic` + tag, then shift.
- Automated rollback: smoke test fails → route traffic back to previous revision.
- JVM: `-XX:MaxRAMPercentage=75`, Hikari pool sized to Cloud SQL `max_connections / max_instances`.
- 10k concurrency target: ~125+ instances' worth of concurrency at peak is unrealistic for DB — mitigate with read-heavy endpoint caching (Caffeine) and Cloud SQL tier sizing; tune after first test.

## 6. Monitoring & alerts
Dashboard: CPU, memory, request count, 5xx rate, P95 latency, instance count, Cloud SQL CPU/connections.
Alerts: 5xx rate > 1% (5 min), P95 > 500 ms, CPU > 80%, uptime check failure. Test alert fired during load test.

## 7. Five-day schedule
| Day | Work | Output |
|---|---|---|
| 1 | Analysis doc, Actuator, MySQL profile, Dockerfile, compose (app + MySQL), Trivy local | `docs/ANALYSIS.md`, `Dockerfile`, `docker-compose.yml` |
| 2 | Terraform: AR, Cloud SQL, Secret Manager, SAs, WIF, Cloud Run | `infra/terraform/` |
| 3 | GitHub Actions PR + main pipelines, smoke test, rollback | `.github/workflows/` , live HTTPS URL |
| 4 | Monitoring dashboard + alerts; k6 scripts; first load test + tuning | `loadtest/`, dashboard JSON |
| 5 | Retest, docs (architecture, deploy guide, scaling, test report, alerts, cost), demo dry run | `docs/` complete |

## 8. Assumptions & risks
- A GCP project with billing and Owner/Editor access is provided.
- Push access to this repo (or a fork) + ability to add GitHub secrets/variables.
- **Risk:** 10k concurrent at P95 < 500 ms depends on DB-bound endpoints; caching and Cloud SQL tier are the levers. Budget for a larger Cloud SQL tier during the test window.
- Mailgun not configured (out of scope); mail features disabled.
- Single region (us-central1 / asia-south1); multi-region left as a documented extension.
