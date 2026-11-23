# ---------------------------------------------------------------------------
# Resource groups the pipeline may write to
#
# The apply identity gets Contributor only on these groups (plus rg-aks, which
# lives in infra/cluster-identity), not on the subscription. A role assignment
# needs its scope to exist, so the groups are created here, next to the
# assignment, and the pipeline modules only reference them via data sources.
# ---------------------------------------------------------------------------

locals {
  location = "germanywestcentral"

  tags = {
    project    = "clusteryard"
    managed_by = "terraform"
    env        = "shared"
  }

  pipeline_resource_groups = {
    dns     = "rg-dns"
    network = "rg-network"
  }
}

# One-time adoption of the groups the dns and network modules created before.
# Harmless once imported; can be deleted afterwards.
import {
  for_each = local.pipeline_resource_groups
  to       = azurerm_resource_group.pipeline[each.key]
  id       = "${data.azurerm_subscription.current.id}/resourceGroups/${each.value}"
}

resource "azurerm_resource_group" "pipeline" {
  for_each = local.pipeline_resource_groups

  name     = each.value
  location = local.location
  tags     = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_role_assignment" "apply_resource_group" {
  for_each = azurerm_resource_group.pipeline

  scope                = each.value.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github["apply"].object_id
  principal_type       = "ServicePrincipal"
}
