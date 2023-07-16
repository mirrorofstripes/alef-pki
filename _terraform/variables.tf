variable "azure_region" {
  type        = string
  description = "The Azure region to deploy the hub resources to."
  default     = "westeurope"
}

variable "hub_ip_subnet" {
  type        = string
  description = "The subnet to deploy the hub resources to. Minimum /27."
  default     = "192.168.21.0/24"
}

variable "pod_ip_subnet" {
  type        = string
  description = "The subnet to deploy the pod resources to. Minimum /16."
  default     = "10.0.0.0/16"
}

variable "number_of_pods" {
  type        = number
  description = "How many training pods should the script deploy. Defaults to 2"
  default     = "2"
}