# Everything long-lived comes from other modules' state: the cluster only
# references it, so it can be destroyed and recreated freely.
locals {
  state_backend = {
    resource_group_name  = "rg-tfstatenew"
    storage_account_name = "sttfstate60kc1m"
    container_name       = "tfstate"
  }

  network          = data.terraform_remote_state.network.outputs
  cluster_identity = data.terraform_remote_state.cluster_identity.outputs
}

data "terraform_remote_state" "network" {
  backend = "azurerm"
  config  = merge(local.state_backend, { key = "network/terraform.tfstate" })
}

data "terraform_remote_state" "cluster_identity" {
  backend = "azurerm"
  config  = merge(local.state_backend, { key = "cluster-identity/terraform.tfstate" })
}

data "azurerm_client_config" "current" {}
