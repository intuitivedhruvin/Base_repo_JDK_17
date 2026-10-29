# Learning Guide — How This POC Works

Simple explanations of what we built, why, and how each problem was solved.

## The big picture

The Java app already exists. Our job is to build the **factory and delivery system** around it:

```
You push code
   ↓
GitHub Actions (robot): build → test → scan → make Docker image
   ↓
Artifact Registry (image storage)
   ↓
Cloud Run runs the new version → smoke test → OK? keep it : roll back
   ↓
Cloud Monitoring watches it → email alert if something breaks
```

## Key terms

| Term | Simple meaning |
|---|---|
| Container / Docker image | A box with your app plus everything it needs. It runs the same on any machine |
| Dockerfile | The recipe for building that box |
| Cloud Run | Google runs your box, gives it a URL, and adds copies when traffic grows |
| Cloud SQL | A database managed by Google (backups, failover) |
| Terraform | You write *what* should exist in GCP, and Terraform creates it. Repeatable, and you can delete it all in one command |
| IAM role | A permission badge ("can deploy", "can read secrets") |
| Service account | An account for a *program*, not a person |
| Secret Manager | A safe for passwords, so they never sit in code |
| CI | A robot that builds and tests every change |
| CD | A robot that deploys every approved change |
| Workload Identity Federation | GitHub proves who it is to Google without a password file |
| Smoke test | A quick check of the main features after a deploy ("is there smoke?") |
| Rollback | Going back to the last working version |

## How to solve any problem: 5 questions

1. **What is the goal?** Make it concrete.
2. **What is actually happening?** Read the real error. Don't guess.
3. **Why?** Find the root cause, not just the symptom.
4. **What are the options?** Usually 2 or 3.
5. **Which option fits our limits?** Time, permissions, cost, safety.

## Day 1: Make the app ready for the cloud

**What we did:** added a Dockerfile, docker-compose (app + MySQL), a MySQL settings profile, and health-check URLs.

**Why each one:**
- **Dockerfile:** Cloud Run only runs containers. It has two stages: stage 1 builds the jar with Maven, and stage 2 copies only the jar into a small Java runtime. A smaller image starts faster and has fewer security holes.
- **MySQL profile:** by default the app uses H2, a database that lives *in memory*. With 10 copies of the app, each copy would have its own separate data. A shared MySQL database lets every copy see the same data, which makes the app "stateless".
- **Health checks** (`/actuator/health/liveness` and `/readiness`): Cloud Run asks "are you alive?" and "are you ready for traffic?". If the answer is no, it restarts the copy or sends traffic elsewhere.
- **Settings from environment variables:** the same image works everywhere. Only the settings change (local, test, production).

## Day 2: Infrastructure as code (Terraform)

**Problem:** you'll only have **Editor**, and Editor can't grant roles.

**How we solved it:** split the Terraform into two folders, by *who* can run them.

| Folder | Who runs it | What it creates |
|---|---|---|
| `infra/terraform/bootstrap` | A teammate with Owner, once | Service accounts, role grants, GitHub login, image storage |
| `infra/terraform/app` | You (Editor) | Database, secrets, Cloud Run |

**Tricks to avoid needing Owner later:**
- The app's service account can read *all* secrets in the project, so no per-secret permission is needed.
- Cloud Run's "who may call me" check is switched off (`invoker_iam_disabled`), so making the URL public needs no permission change.
- The database is reached through a small helper container (the **Cloud SQL Auth Proxy**) running next to the app. The proxy uses the app's service account to connect securely, so no private network setup is needed.

**Lesson:** design around your limits from the start.

## Day 3: CI/CD with GitHub Actions

### CI (`.github/workflows/ci.yml`): runs on every push or pull request
1. Build and run 363 tests (`mvn verify`)
2. Build the Docker image
3. Scan it with **Trivy** and fail if there are CRITICAL vulnerabilities
4. Start the container and run `test-endpoints.sh` (30+ API checks)

### CD (`.github/workflows/deploy.yml`): runs on merge to `main`
1. Log in to GCP (no password file, using Workload Identity Federation)
2. Build and push the image to Artifact Registry, then scan it
3. Deploy a new version **with 0% traffic**, so users don't see it yet
4. Smoke test that hidden version through its own private URL
5. Pass → move 100% of traffic to it. Fail → users never saw it
6. Smoke test again on the live URL. Fail → **automatic rollback** to the previous version

**Why deploy with 0% traffic first?** Users only ever reach a version that already passed the tests. This is called a **blue/green** or **canary** style deploy.

## Real problems we hit, and how we solved them

| Problem | What we saw | Root cause | Fix | Lesson |
|---|---|---|---|---|
| Installers need admin | Admin prompt | Normal installers write to `C:\Program Files` | Portable zip versions in the user folder, added to PATH | Look for another door you're allowed to use |
| Do I need Owner? | — | Listed every task and the permission it needs | Editor + a one-time setup by a teammate | Least privilege: ask only for what you need |
| Tests failed locally | "Tests run: 0", "forked VM terminated" | `(` and `)` in the Windows username break `cmd.exe` | Run tests inside Maven's own JVM (`-DforkCount=0`) | "0 tests ran" means an environment problem, not a code problem |
| 2 payment tests failed locally | "Expected BEGIN_OBJECT but was STRING" | They call a real payment test server, and the company network blocked it | They pass on GitHub, so no change needed | Tests that call outside services are "flaky" |
| Push rejected | HTTP 403 | Logged in, but no write access to Mahesh's repo | Forked the repo to our own account | 401 = "who are you?", 403 = "not allowed" |
| Terraform error | "account_id must be 6–30 characters" | `gh-ci` is too short | Renamed it to `trebol-ci` | Validate early (`terraform validate`), before touching the cloud |
| CI job didn't start | "unable to find version 0.28.0" | The Trivy action's tags start with `v` | Changed it to `v0.36.0` | Check the real tag list (`gh api .../tags`) instead of guessing |

## Languages used (no Java coding needed)

| File type | Used for |
|---|---|
| Dockerfile | Packaging the app |
| Terraform (`.tf`) | Creating cloud resources |
| YAML (`.yml`) | CI/CD pipelines |
| Bash (`.sh`) | Smoke tests and helper scripts |
| JavaScript (k6) | Load tests (Day 4) |
