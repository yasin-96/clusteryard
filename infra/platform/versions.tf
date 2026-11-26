terraform {
  required_version = ">= 1.5.0"

  # On demand (ON_DEMAND_MODULES): validated on pull requests, never planned
  # there (ADR 0005). Applied after infra/cluster and destroyed before it by
  # the cluster up/down workflow.
  backend "azurerm" {
    resource_group_name  = "rg-tfstatenew"
    storage_account_name = "sttfstate60kc1m"
    container_name       = "tfstate"
    key                  = "platform/terraform.tfstate"
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

# azurerm v4 needs a subscription ID: set ARM_SUBSCRIPTION_ID in the environment.
provider "azurerm" {
  features {}
}

# Entra ID only, the cluster has no local accounts (ADR 0004). kubelogin gets a
# token for the AKS API; Azure RBAC grants Cluster Admin on rg-aks (ADR 0006).
provider "helm" {
  kubernetes = {
    host                   = data.azurerm_kubernetes_cluster.this.kube_config[0].host
    cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "kubelogin"
      args = [
        "get-token",
        "--login", var.kubelogin_login,
        "--server-id", local.aks_server_app_id,
      ]
    }
  }
}
