variable "kubelogin_login" {
  description = <<-EOT
    kubelogin login mode. azurecli locally (after az login). workloadidentity in
    the pipeline: it reads a fresh GitHub OIDC token from AZURE_FEDERATED_TOKEN_FILE,
    because the token behind azure/login has expired by the time the cluster is up.
  EOT
  type        = string
  default     = "azurecli"

  validation {
    condition     = contains(["azurecli", "workloadidentity"], var.kubelogin_login)
    error_message = "kubelogin_login must be azurecli or workloadidentity."
  }
}

variable "argocd_chart_version" {
  description = "Version of the argo-cd Helm chart (argoproj/argo-helm)."
  type        = string
  default     = "10.18.2" # ArgoCD v3.6.2
}

variable "argocd_apps_chart_version" {
  description = "Version of the argocd-apps Helm chart, which creates the root Application."
  type        = string
  default     = "2.0.8"
}

variable "gitops_repo_url" {
  description = "Git repository ArgoCD syncs from. Public, so no repository credentials."
  type        = string
  default     = "https://github.com/yasin-96/clusteryard.git"
}

variable "gitops_revision" {
  description = "Branch, tag or commit the root Application tracks."
  type        = string
  default     = "main"
}

variable "gitops_apps_path" {
  description = "Directory with the child Applications (app-of-apps)."
  type        = string
  default     = "gitops/apps"
}
