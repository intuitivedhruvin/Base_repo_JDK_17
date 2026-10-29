# Infrastructure — Trebol on GCP

Project `itp-agentspace`, region `asia-south1`. Two Terraform stacks, split by who can apply them:

| Stack | Who runs it | Needs | Creates |
|---|---|---|---|
| `terraform/bootstrap` | Teammate with **Owner**, once | Owner | APIs, Terraform state bucket, Artifact Registry, service accounts `trebol-run` and `trebol-ci`, their IAM roles, Workload Identity Federation for GitHub Actions |
| `terraform/app` | Developer | **Editor** | Secrets, Cloud SQL MySQL 8, Cloud Run service `trebol-api` |

Every IAM grant is in the bootstrap stack, so the app stack never needs more than Editor:
- The runtime SA reads secrets through a project-level `secretAccessor` role, not per-secret bindings.
- Cloud Run is public through `invoker_iam_disabled`, not an `allUsers` binding.

## 1. Bootstrap (Owner, once)

```bash
gcloud auth login
gcloud auth application-default login
cd infra/terraform/bootstrap
terraform init
terraform apply
terraform output        # share these values with the developer
```

The state for this stack stays local. Keep `terraform.tfstate` safe; don't commit it.

## 2. First image (Editor)

There's no local Docker yet, so build on Cloud Build. Run from the repo root:

```bash
gcloud config set project itp-agentspace
gcloud builds submit trebol-backend-monolith \
  --config trebol-backend-monolith/cloudbuild.yaml \
  --service-account=projects/itp-agentspace/serviceAccounts/trebol-ci@itp-agentspace.iam.gserviceaccount.com
```

## 3. App stack (Editor)

```bash
gcloud auth application-default login
cd infra/terraform/app
cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config="bucket=itp-agentspace-trebol-tfstate"
terraform apply         # Cloud SQL takes ~10 min
curl "$(terraform output -raw url)/actuator/health"
```

After the first successful start, set `db_seed_mode = "never"` in `terraform.tfvars` and apply again.

## 4. GitHub repo settings (for Day 3 CI/CD)

Repository **variables** (not secrets, since none of these are sensitive):

| Name | Value |
|---|---|
| `GCP_PROJECT_ID` | `itp-agentspace` |
| `GCP_REGION` | `asia-south1` |
| `GCP_WIF_PROVIDER` | bootstrap output `wif_provider` |
| `GCP_CI_SA` | bootstrap output `ci_service_account` |

## Design notes
- **Database connection:** a Cloud SQL Auth Proxy sidecar runs in each Cloud Run instance. The app connects to `127.0.0.1:3306` with the existing MariaDB driver. The proxy authenticates with the runtime SA's IAM identity, and the instance has no authorized networks, so its public IP is closed to everything else. Private IP needs VPC peering and was left out to keep the POC simple.
- **Connection budget:** `max_instances × db_pool_size` = 50 × 15 = 750, which stays under `max_connections` = 1000.
- **Image ownership:** Terraform sets the image only on the first apply. After that, CI deploys new revisions, and Terraform ignores image changes.
- **Secrets in state:** the generated passwords live in Terraform state, which sits in a private, versioned GCS bucket. That's acceptable for a POC.

## Teardown
```bash
cd infra/terraform/app && terraform destroy
cd ../bootstrap && terraform destroy     # Owner
```
