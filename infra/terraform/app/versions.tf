terraform {
  required_version = ">= 1.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.14"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
  # bucket comes from the bootstrap output:
  #   terraform init -backend-config="bucket=<tfstate_bucket>"
  backend "gcs" {
    prefix = "trebol/app"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
