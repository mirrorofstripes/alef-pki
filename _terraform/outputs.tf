output "ansible_password" {
  value       = random_password.ansible_password.result
  sensitive   = true
  description = "Admin password for remote access to the Ansible VM."
}

output "ansible_dns_name" {
  value       = azurerm_dns_a_record.pip-ansible.fqdn
  description = "Internet FQDN for remote access to the Ansible VM."
}

output "maestro_password" {
  value       = module.alef-pki-pod[*].maestro_password
  sensitive   = true
  description = "Admin password for remote access to the pod computers."
}

output "rootca_dns_name" {
  value       = module.alef-pki-pod[*].rootca_dns_name
  description = "Internet FQDN for RDPing to the Root CA VM."
}

output "hop_dns_name" {
  value       = module.alef-pki-pod[*].hop_dns_name
  description = "Internet FQDN for RDPing to the Hop VM."
}

output "cdp_dns_name" {
  value       = module.alef-pki-pod[*].cdp_dns_name
  description = "Internet FQDN for HTTPing to the CDP VM."
}