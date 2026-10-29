output "tfstate_bucket" {
  value = google_storage_bucket.tfstate.name
}

output "registry" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.trebol.repository_id}"
}

output "runtime_service_account" {
  value = google_service_account.runtime.email
}

output "ci_service_account" {
  value = google_service_account.ci.email
}

output "wif_provider" {
  description = "GitHub variable GCP_WIF_PROVIDER"
  value       = google_iam_workload_identity_pool_provider.github.name
}
