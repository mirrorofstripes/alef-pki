variable "azure_region" {
  type        = string
  description = "The region to deploy the resources to."
}

variable "pod_name" {
  type        = string
  description = "Name of the individual pod. Will be used in resource names, tags and in public DNS."
}

variable "pod_ip_subnet" {
  type        = string
  description = "The subnet to deploy the resources to. Minimum /27."
}

variable "hub_resource_group_name" {
  type        = string
  description = "The Hub Resource Group name."
}

variable "hub_vnet_name" {
  type        = string
  description = "The Hub Virtual Network name."
}

variable "hub_vnet_id" {
  type        = string
  description = "The Hub Virtual Network id."
}

variable "public_dns_zone_name" {
  type        = string
  description = "The Public DNS Zone name."
}

variable "public_dns_zone_resource_group_name" {
  type        = string
  description = "The Public DNS Zone Resource Group name."
}