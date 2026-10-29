variable "project_id" {
  type    = string
  default = "itp-agentspace"
}

variable "region" {
  type    = string
  default = "asia-south1"
}

variable "image" {
  description = "Initial image; later deploys come from CI and are ignored by Terraform"
  type        = string
}

# ---- Cloud Run ----
variable "min_instances" {
  type    = number
  default = 2
}

variable "max_instances" {
  type    = number
  default = 50
}

variable "concurrency" {
  type    = number
  default = 80
}

variable "cors_allowed_origins" {
  type    = string
  default = "http://localhost:4200"
}

variable "db_seed_mode" {
  description = "always on the first deploy to load demo data, then never"
  type        = string
  default     = "always"
}

# ---- Cloud SQL ----
variable "db_tier" {
  type    = string
  default = "db-custom-2-7680"
}

variable "db_availability_type" {
  description = "REGIONAL for HA, ZONAL to save cost"
  type        = string
  default     = "REGIONAL"
}

variable "db_max_connections" {
  description = "Must cover max_instances * db_pool_size"
  type        = number
  default     = 1000
}

variable "db_pool_size" {
  type    = number
  default = 15
}

variable "deletion_protection" {
  type    = bool
  default = false
}
