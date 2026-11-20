output "resource_group_name" {
  description = "Resource group for the AKS cluster (rg-aks)."
  value       = azurerm_resource_group.aks.name
}

output "control_plane_identity_id" {
  description = "Resource ID for identity { type = \"UserAssigned\" } in the cluster."
  value       = azurerm_user_assigned_identity.this["aks-control-plane"].id
}

output "kubelet_identity" {
  description = "Values for the kubelet_identity block in the cluster."
  value = {
    user_assigned_identity_id = azurerm_user_assigned_identity.this["aks-kubelet"].id
    client_id                 = azurerm_user_assigned_identity.this["aks-kubelet"].client_id
    object_id                 = azurerm_user_assigned_identity.this["aks-kubelet"].principal_id
  }
}

# The cluster module adds federated credentials to these (parent_id = id) and
# the Helm charts annotate their service accounts with client_id.
output "workload_identities" {
  description = "Workload identities for in-cluster components."
  value = {
    for name in ["cert-manager", "external-dns"] : name => {
      id        = azurerm_user_assigned_identity.this[name].id
      name      = azurerm_user_assigned_identity.this[name].name
      client_id = azurerm_user_assigned_identity.this[name].client_id
    }
  }
}
