output "resource_group_name" {
  description = "Resource group holding the network."
  value       = data.azurerm_resource_group.network.name
}

output "vnet_id" {
  description = "Resource ID of the virtual network."
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the virtual network."
  value       = azurerm_virtual_network.main.name
}

output "aks_nodes_subnet_id" {
  description = "Subnet ID for the AKS node pool (vnet_subnet_id)."
  value       = azurerm_subnet.aks_nodes.id
}

output "pod_cidr" {
  description = "Overlay pod CIDR for the AKS network_profile (outside the VNet)."
  value       = local.pod_cidr
}

output "service_cidr" {
  description = "Kubernetes service CIDR for the AKS network_profile (outside the VNet)."
  value       = local.service_cidr
}

output "dns_service_ip" {
  description = "CoreDNS service IP for the AKS network_profile (inside service_cidr)."
  value       = local.dns_service_ip
}
