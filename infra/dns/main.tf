locals {
  zone_name = "k8s.clusteryard.dev"

  tags = {
    project    = "clusteryard"
    managed_by = "terraform"
    env        = "shared"
  }
}

# Own resource group: survives tearing down the cluster. It is created in
# infra/identity, which also grants the pipeline Contributor on it.
data "azurerm_resource_group" "dns" {
  name = "rg-dns"
}

# Ownership moved to infra/identity: forget it here, do not delete it.
removed {
  from = azurerm_resource_group.dns

  lifecycle {
    destroy = false
  }
}

# Delegated from Cloudflare (clusteryard.dev) via NS records for "k8s".
resource "azurerm_dns_zone" "k8s" {
  name                = local.zone_name
  resource_group_name = data.azurerm_resource_group.dns.name
  tags                = local.tags

  # Recreating the zone can assign different name servers and would silently
  # break the delegation in Cloudflare.
  lifecycle {
    prevent_destroy = true
  }
}
