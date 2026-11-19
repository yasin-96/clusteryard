variable "github_owner" {
  description = "GitHub user or organization that owns the repository."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without owner)."
  type        = string
}

variable "github_oidc_repo" {
  description = "Repository as presented in the OIDC subject, including immutable IDs, e.g. owner@123/repo@456"
  type        = string
}

variable "github_apply_environment" {
  description = "GitHub Environment (with required reviewers) that gates apply jobs."
  type        = string
  default     = "prod"
}

variable "state_resource_group_name" {
  description = "Resource group of the Terraform state storage account (created in infra/bootstrap)."
  type        = string
  default     = "rg-tfstatenew"
}

variable "state_storage_account_name" {
  description = "Terraform state storage account (created in infra/bootstrap)."
  type        = string
  default     = "sttfstate60kc1m"
}

variable "state_container_name" {
  description = "Blob container holding the Terraform state files."
  type        = string
  default     = "tfstate"
}
