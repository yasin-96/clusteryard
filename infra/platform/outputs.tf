output "argocd_namespace" {
  value = helm_release.argocd.namespace
}

output "argocd_version" {
  description = "ArgoCD version installed by the chart."
  value       = helm_release.argocd.metadata.app_version
}
