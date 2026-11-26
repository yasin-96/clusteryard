locals {
  location = "germanywestcentral"

  tags = {
    project    = "clusteryard"
    managed_by = "terraform"
    env        = "shared"
  }

  # Every identity that needs a role assignment is user-assigned and long-lived.
  # The cluster (infra/cluster) only references them, so tearing it down and
  # recreating it never requires new role assignments.
  identities = toset([
    "aks-control-plane",
    "aks-kubelet",
    "cert-manager",
    "external-dns",
  ])

  role_assignments = {
    # AKS manages load balancer / NIC attachments in the node subnet.
    control_plane_subnet = {
      principal_id   = azurerm_user_assigned_identity.this["aks-control-plane"].principal_id
      principal_type = "ServicePrincipal"
      role           = "Network Contributor"
      scope          = data.terraform_remote_state.network.outputs.aks_nodes_subnet_id
    }
    # Required when the cluster uses its own kubelet identity.
    control_plane_kubelet = {
      principal_id   = azurerm_user_assigned_identity.this["aks-control-plane"].principal_id
      principal_type = "ServicePrincipal"
      role           = "Managed Identity Operator"
      scope          = azurerm_user_assigned_identity.this["aks-kubelet"].id
    }
    # DNS-01 challenges.
    cert_manager_zone = {
      principal_id   = azurerm_user_assigned_identity.this["cert-manager"].principal_id
      principal_type = "ServicePrincipal"
      role           = "DNS Zone Contributor"
      scope          = data.terraform_remote_state.dns.outputs.zone_id
    }
    # Records for ingresses / services.
    external_dns_zone = {
      principal_id   = azurerm_user_assigned_identity.this["external-dns"].principal_id
      principal_type = "ServicePrincipal"
      role           = "DNS Zone Contributor"
      scope          = data.terraform_remote_state.dns.outputs.zone_id
    }
    # The pipeline creates the cluster here; no write access elsewhere.
    apply_contributor = {
      principal_id   = data.azuread_service_principal.apply.object_id
      principal_type = "ServicePrincipal"
      role           = "Contributor"
      scope          = azurerm_resource_group.aks.id
    }
    # Kubernetes API access (Helm provider in infra/platform). Owner/Contributor
    # do not include Kubernetes data actions, so both need this explicitly.
    apply_cluster_admin = {
      principal_id   = data.azuread_service_principal.apply.object_id
      principal_type = "ServicePrincipal"
      role           = "Azure Kubernetes Service RBAC Cluster Admin"
      scope          = azurerm_resource_group.aks.id
    }
    # Pull request plans refresh the running cluster, and azurerm reads its
    # kubeconfig (listClusterUserCredential). Reader does not include that.
    # With local accounts disabled the kubeconfig holds no secret, and the
    # plan identity has no Kubernetes RBAC role, so it cannot act in the cluster.
    plan_cluster_user = {
      principal_id   = data.azuread_service_principal.plan.object_id
      principal_type = "ServicePrincipal"
      role           = "Azure Kubernetes Service Cluster User Role"
      scope          = azurerm_resource_group.aks.id
    }
    admin_cluster_admin = {
      principal_id   = var.admin_object_id
      principal_type = "User"
      role           = "Azure Kubernetes Service RBAC Cluster Admin"
      scope          = azurerm_resource_group.aks.id
    }
  }
}

# Long-lived home of the cluster and its identities. The cluster comes and goes,
# the group and the role assignments on it stay.
resource "azurerm_resource_group" "aks" {
  name     = "rg-aks"
  location = local.location
  tags     = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_user_assigned_identity" "this" {
  for_each = local.identities

  name                = "id-${each.key}"
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  tags                = local.tags
}

resource "azurerm_role_assignment" "this" {
  for_each = local.role_assignments

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type
}
