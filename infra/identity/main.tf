data "azuread_client_config" "current" {}

data "azurerm_subscription" "current" {}

data "azurerm_storage_account" "tfstate" {
  name                = var.state_storage_account_name
  resource_group_name = var.state_resource_group_name
}

locals {
  repo = var.github_oidc_repo

  # ARM scope of the state container (data plane roles are assigned here,
  # not on the whole storage account).
  state_container_scope = "${data.azurerm_storage_account.tfstate.id}/blobServices/default/containers/${var.state_container_name}"

  identities = {
    plan = {
      display_name      = "gh-${var.github_repo}-plan"
      subject           = "repo:${local.repo}:pull_request"
      subscription_role = "Reader"
      state_role        = "Storage Blob Data Reader"
    }
    apply = {
      display_name      = "gh-${var.github_repo}-apply"
      subject           = "repo:${local.repo}:environment:${var.github_apply_environment}"
      subscription_role = "Contributor"
      state_role        = "Storage Blob Data Contributor"
    }
  }
}

# ---------------------------------------------------------------------------
# Entra ID: app registration + service principal per identity
# ---------------------------------------------------------------------------

resource "azuread_application" "github" {
  for_each = local.identities

  display_name = each.value.display_name
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "github" {
  for_each = local.identities

  client_id = azuread_application.github[each.key].client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# OIDC trust: GitHub-issued tokens with exactly this subject may log in.
# No client secret exists for these apps.
resource "azuread_application_federated_identity_credential" "github" {
  for_each = local.identities

  application_id = azuread_application.github[each.key].id
  display_name   = "github-${each.key}"
  description    = "GitHub Actions OIDC for ${local.repo} (${each.key})"
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = each.value.subject
  audiences      = ["api://AzureADTokenExchange"]
}

# ---------------------------------------------------------------------------
# Azure RBAC
# ---------------------------------------------------------------------------

# Plan: Reader, Apply: Contributor on the whole subscription (see ADR 0001).
resource "azurerm_role_assignment" "subscription" {
  for_each = local.identities

  scope                = data.azurerm_subscription.current.id
  role_definition_name = each.value.subscription_role
  principal_id         = azuread_service_principal.github[each.key].object_id
  principal_type       = "ServicePrincipal"
}

# Both need to write the state lock (blob lease), hence Contributor on data plane.
resource "azurerm_role_assignment" "state" {
  for_each = local.identities

  scope                = local.state_container_scope
  role_definition_name = each.value.state_role
  principal_id         = azuread_service_principal.github[each.key].object_id
  principal_type       = "ServicePrincipal"
}
