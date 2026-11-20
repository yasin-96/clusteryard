terraform {
  required_version = ">= 1.5.0"

  # Local-only (LOCAL_ONLY_MODULES): creates role assignments, which the
  # pipeline is not allowed to do. Apply after infra/dns and infra/network.
  backend "azurerm" {
    resource_group_name  = "rg-tfstatenew"
    storage_account_name = "sttfstate60kc1m"
    container_name       = "tfstate"
    key                  = "cluster-identity/terraform.tfstate"
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}

# azurerm v4 needs a subscription ID: set ARM_SUBSCRIPTION_ID in the environment.
provider "azurerm" {
  features {}
}

provider "azuread" {}
