# None of these are secrets. Store them as GitHub Actions *variables*:
#   AZURE_CLIENT_ID_PLAN, AZURE_CLIENT_ID_APPLY, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID

output "plan_client_id" {
  value = azuread_application.github["plan"].client_id
}

output "apply_client_id" {
  value = azuread_application.github["apply"].client_id
}

output "tenant_id" {
  value = data.azuread_client_config.current.tenant_id
}

output "subscription_id" {
  value = data.azurerm_subscription.current.subscription_id
}
