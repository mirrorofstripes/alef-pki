output "maestro_password" {
  value       = random_password.maestro_password.result
  description = "Admin password for remote access to the pod computers."
}

output "rootca_dns_name" {
  value       = azurerm_dns_a_record.pip-RootCA.fqdn
  description = "Internet FQDN for RDPing to the Root CA VM."
}

output "hop_dns_name" {
  value       = azurerm_dns_a_record.pip-hop01.fqdn
  description = "Internet FQDN for RDPing to the Hop VM."
}