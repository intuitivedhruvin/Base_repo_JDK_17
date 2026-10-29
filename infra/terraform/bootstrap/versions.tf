terraform {
  required_version = ">= 1.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.14"
    }
  }
  # Local state: this stack is applied once by a project Owner
}

provider "google" {
  project = var.project_id
  region  = var.region
}
