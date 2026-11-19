locals {
  location  = "germanywestcentral"
  zone_name = "k8s.clusteryard.dev"

  tags = {
    project    = "clusteryard"
    managed_by = "terraform"
    env        = "shared"
  }
}

# Own resource group: survives tearing down the cluster.
resource "azurerm_resource_group" "dns" {
  name     = "rg-dns"
  location = local.location
  tags     = local.tags
}

# Delegated from Cloudflare (clusteryard.dev) via NS records for "k8s".
resource "azurerm_dns_zone" "k8s" {
  name                = local.zone_name
  resource_group_name = azurerm_resource_group.dns.name
  tags                = local.tags

  # Recreating the zone can assign different name servers and would silently
  # break the delegation in Cloudflare.
  lifecycle {
    prevent_destroy = true
  }
}
