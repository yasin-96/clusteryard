# Outputs of the other long-lived modules, read from their state files.
locals {
  state_backend = {
    resource_group_name  = "rg-tfstatenew"
    storage_account_name = "sttfstate60kc1m"
    container_name       = "tfstate"
  }
}

data "terraform_remote_state" "identity" {
  backend = "azurerm"
  config  = merge(local.state_backend, { key = "identity/terraform.tfstate" })
}

data "terraform_remote_state" "dns" {
  backend = "azurerm"
  config  = merge(local.state_backend, { key = "dns/terraform.tfstate" })
}

data "terraform_remote_state" "network" {
  backend = "azurerm"
  config  = merge(local.state_backend, { key = "network/terraform.tfstate" })
}

# Pipeline apply identity, looked up by its (stable) client ID.
data "azuread_service_principal" "apply" {
  client_id = data.terraform_remote_state.identity.outputs.apply_client_id
}
