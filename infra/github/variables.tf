variable "github_owner" {
  description = "GitHub user or organization that owns the repository."
  type        = string
  default     = "yasin-96"
}

variable "github_repo" {
  description = "Repository name."
  type        = string
  default     = "clusteryard"
}

variable "prod_reviewer_ids" {
  description = "Numeric GitHub user IDs that must approve deployments to the prod environment."
  type        = list(number)
  default     = [62212311] # yasin-96
}
