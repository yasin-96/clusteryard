terraform {
  required_version = ">= 1.5.0"

  backend "azurerm" {
    resource_group_name  = "rg-tfstatenew"
    storage_account_name = "sttfstate60kc1m"
    container_name       = "tfstate"
    key                  = "dns/terraform.tfstate"
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# azurerm v4 needs a subscription ID: set ARM_SUBSCRIPTION_ID in the environment
# (the pipeline sets it from the AZURE_SUBSCRIPTION_ID variable).
provider "azurerm" {
  features {}
}
