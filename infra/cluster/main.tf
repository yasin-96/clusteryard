locals {
  location = "germanywestcentral"

  tags = {
    project    = "clusteryard"
    managed_by = "terraform"
    env        = "shared"
  }

  # Kubernetes service accounts allowed to use the workload identities.
  # Must match the namespaces / service accounts of the Helm charts.
  workload_service_accounts = {
    cert-manager = { namespace = "cert-manager", service_account = "cert-manager" }
    external-dns = { namespace = "external-dns", service_account = "external-dns" }
  }
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-clusteryard"
  location            = local.location
  resource_group_name = local.cluster_identity.resource_group_name
  dns_prefix          = "clusteryard"
  node_resource_group = "rg-aks-nodes"
  tags                = local.tags

  sku_tier           = var.sku_tier
  kubernetes_version = var.kubernetes_version

  # The cluster lives for hours; rebuilding it is the upgrade. Automatic
  # upgrades could restart nodes in the middle of a session.
  node_os_upgrade_channel = "None"

  # System pool: kube-system and AKS add-ons only. The CriticalAddonsOnly taint
  # keeps platform components and services on the apps pool.
  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_pool.vm_size
    node_count                   = var.system_pool.node_count
    zones                        = var.zones
    only_critical_addons_enabled = true
    vnet_subnet_id               = local.network.aks_nodes_subnet_id
    os_disk_type                 = "Managed"
    os_disk_size_gb              = 32 # default is 128 GB Premium (P10)
    temporary_name_for_rotation  = "systemtmp"
    tags                         = local.tags # reaches the VMs in rg-aks-nodes

    upgrade_settings {
      max_surge = "1"
    }
  }

  # Azure CNI Overlay powered by Cilium: eBPF data plane and Kubernetes
  # NetworkPolicy enforcement. Ranges come from infra/network (ADR 0002); never
  # rely on the AKS defaults, the default service CIDR overlaps the VNet.
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = local.network.pod_cidr
    service_cidr        = local.network.service_cidr
    dns_service_ip      = local.network.dns_service_ip
    outbound_type       = "loadBalancer"
    load_balancer_sku   = "standard"
  }

  # Long-lived user-assigned identities from infra/cluster-identity (ADR 0006).
  identity {
    type         = "UserAssigned"
    identity_ids = [local.cluster_identity.control_plane_identity_id]
  }

  kubelet_identity {
    user_assigned_identity_id = local.cluster_identity.kubelet_identity.user_assigned_identity_id
    client_id                 = local.cluster_identity.kubelet_identity.client_id
    object_id                 = local.cluster_identity.kubelet_identity.object_id
  }

  # Entra ID only, permissions via Azure RBAC (ADR 0004).
  local_account_disabled            = true
  role_based_access_control_enabled = true

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true
}

# User pool: everything that is not kube-system (ArgoCD, ingress, cert-manager,
# external-dns, observability, the Go services and the frontend).
resource "azurerm_kubernetes_cluster_node_pool" "apps" {
  name                  = "apps"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  mode                  = "User"
  vm_size               = var.apps_pool.vm_size
  node_count            = var.apps_pool.node_count
  zones                 = var.zones
  vnet_subnet_id        = local.network.aks_nodes_subnet_id
  os_disk_type          = "Managed"
  os_disk_size_gb       = 32
  tags                  = local.tags

  upgrade_settings {
    max_surge = "1"
  }
}

# Recreated on every build: the OIDC issuer URL changes with each cluster.
# Contributor on rg-aks is enough, this is not a role assignment (ADR 0006).
resource "azurerm_federated_identity_credential" "workload" {
  for_each = local.workload_service_accounts

  name                      = "aks-clusteryard-${each.key}"
  user_assigned_identity_id = local.cluster_identity.workload_identities[each.key].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject                   = "system:serviceaccount:${each.value.namespace}:${each.value.service_account}"
}
