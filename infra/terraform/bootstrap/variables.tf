variable "project_id" {
  type    = string
  default = "itp-agentspace"
}

variable "region" {
  type    = string
  default = "asia-south1"
}

variable "github_repo" {
  description = "owner/name of the GitHub repo allowed to deploy"
  type        = string
  default     = "intuitivedhruvin/Base_repo_JDK_17"
}
