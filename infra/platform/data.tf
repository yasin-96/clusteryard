locals {
  state_backend = {
    resource_group_name  = "rg-tfstatenew"
    storage_account_name = "sttfstate60kc1m"
    container_name       = "tfstate"
  }

  cluster = data.terraform_remote_state.cluster.outputs

  # Fixed application ID of the AKS Entra ID server, the same in every tenant.
  aks_server_app_id = "6dae42f8-4368-4678-94ff-3960e28e3630"
}

# Name and resource group from the cluster state; endpoint and CA from Azure,
# so a rebuilt cluster is always read fresh.
data "terraform_remote_state" "cluster" {
  backend = "azurerm"
  config  = merge(local.state_backend, { key = "cluster/terraform.tfstate" })
}

data "azurerm_kubernetes_cluster" "this" {
  name                = local.cluster.cluster_name
  resource_group_name = local.cluster.resource_group_name
}
