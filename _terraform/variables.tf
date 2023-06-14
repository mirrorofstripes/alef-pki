variable "azure_region" {
  type        = string
  description = "The Azure region to deploy the hub resources to."
  default     = "northeurope"
}

variable "hub_ip_subnet" {
  type        = string
  description = "The subnet to deploy the hub resources to. Minimum /27."
  default     = "192.168.21.0/24"
}