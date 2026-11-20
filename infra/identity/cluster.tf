# ---------------------------------------------------------------------------
# Long-lived AKS control plane identity (see ADR 0002, decision 6)
#
# Created here (local-only) so the pipeline never needs rights to create role
# assignments. It survives cluster teardown, so the role assignment is made once.
# Requires infra/network to be applied first (the subnet must exist).
# ---------------------------------------------------------------------------

locals {
  location = "germanywestcentral"

  tags = {
    project    = "clusteryard"
    managed_by = "terraform"
    env        = "shared"
  }
}

data "azurerm_subnet" "aks_nodes" {
  name                 = var.aks_nodes_subnet_name
  virtual_network_name = var.vnet_name
  resource_group_name  = var.network_resource_group_name
}

resource "azurerm_resource_group" "identity" {
  name     = "rg-identity"
  location = local.location
  tags     = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_user_assigned_identity" "aks" {
  name                = "id-aks-clusteryard"
  location            = azurerm_resource_group.identity.location
  resource_group_name = azurerm_resource_group.identity.name
  tags                = local.tags
}

# Only on the node subnet, not on the network resource group.
resource "azurerm_role_assignment" "aks_subnet" {
  scope                = data.azurerm_subnet.aks_nodes.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
  principal_type       = "ServicePrincipal"
}
