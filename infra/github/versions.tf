terraform {
  required_version = ">= 1.5.0"

  backend "azurerm" {
    resource_group_name  = "rg-tfstatenew"
    storage_account_name = "sttfstate60kc1m"
    container_name       = "tfstate"
    key                  = "github/terraform.tfstate"
  }

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

# Authenticates with GITHUB_TOKEN (locally: export GITHUB_TOKEN=$(gh auth token)).
# Local-only module: the pipeline must never be able to change its own guard rails.
provider "github" {
  owner = var.github_owner
}
