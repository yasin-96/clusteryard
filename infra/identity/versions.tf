terraform {
  required_version = ">= 1.5.0"

  # Separate state from bootstrap: this module outlives the cluster and is
  # applied locally with `az login`, never by the pipeline itself.
  backend "azurerm" {
    resource_group_name  = "rg-tfstatenew"
    storage_account_name = "sttfstate60kc1m"
    container_name       = "tfstate"
    key                  = "identity/terraform.tfstate"
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
