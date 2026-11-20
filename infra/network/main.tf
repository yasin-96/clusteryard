locals {
  location = "germanywestcentral"

  # Kubernetes address ranges for the cluster module (Azure CNI Overlay).
  # They must not overlap the VNet (10.0.0.0/16) or each other. The AKS default
  # service CIDR is 10.0.0.0/16, which would collide, so always pass these.
  pod_cidr       = "192.168.0.0/16"
  service_cidr   = "172.16.0.0/16"
  dns_service_ip = "172.16.0.10" # must be inside service_cidr

  tags = {
    project    = "clusteryard"
    managed_by = "terraform"
    env        = "shared"
  }
}

# Own resource group: survives tearing down the cluster.
resource "azurerm_resource_group" "network" {
  name     = "rg-network"
  location = local.location
  tags     = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-clusteryard"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  address_space       = ["10.0.0.0/16"]
  tags                = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

# AKS node subnet. With Azure CNI Overlay, pods get IPs from a separate
# overlay CIDR, not from this subnet, so a /24 (251 usable IPs) is plenty.
resource "azurerm_subnet" "aks_nodes" {
  name                 = "snet-aks-nodes"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.0.0/24"]

  # No implicit "default outbound access": AKS provides explicit outbound
  # through its load balancer (outbound_type = "loadBalancer").
  default_outbound_access_enabled = false
}
