output "cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "resource_group_name" {
  value = azurerm_kubernetes_cluster.main.resource_group_name
}

output "cluster_id" {
  value = azurerm_kubernetes_cluster.main.id
}

output "oidc_issuer_url" {
  description = "Changes with every rebuild."
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "node_resource_group" {
  value = azurerm_kubernetes_cluster.main.node_resource_group
}

# For the Helm charts (service account annotation azure.workload.identity/client-id).
output "workload_identity_client_ids" {
  value = { for k, v in local.cluster_identity.workload_identities : k => v.client_id }
}
