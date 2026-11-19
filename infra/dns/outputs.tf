output "zone_id" {
  description = "Resource ID of the DNS zone (e.g. for external-dns / cert-manager role assignments)."
  value       = azurerm_dns_zone.k8s.id
}

output "zone_name" {
  description = "Name of the DNS zone."
  value       = azurerm_dns_zone.k8s.name
}

output "name_servers" {
  description = "Azure name servers; create one NS record for k8s in Cloudflare per entry (DNS only)."
  value       = sort(tolist(azurerm_dns_zone.k8s.name_servers))
}
