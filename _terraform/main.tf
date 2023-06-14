## Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.61.0"
    }
  }

  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {}
  subscription_id = "3f8210db-d6ea-450e-8841-df355ea44e97"
}

## Generate an admin password

resource "random_password" "vojta_password" {
  length           = 20
  special          = true
  override_special = "!@#$%^&*()_+{}[]<>?"
}

## Create a resource group

resource "azurerm_resource_group" "rg-hub" {
  location = var.azure_region
  name     = "rg-pki-hub"
}

### Define the Hub environment

resource "azurerm_virtual_network" "vnet-hub" {
  resource_group_name = azurerm_resource_group.rg-hub.name
  location            = var.azure_region
  name                = "vnet-hub"

  address_space = [var.hub_ip_subnet]
}

resource "azurerm_subnet" "vnet-hub-default" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.rg-hub.name
  virtual_network_name = azurerm_virtual_network.vnet-hub.name
  address_prefixes     = azurerm_virtual_network.vnet-hub.address_space
}

resource "azurerm_public_ip" "pip-Ansible" {
  name                = "pip-Ansible"
  resource_group_name = azurerm_resource_group.rg-hub.name
  location            = var.azure_region
  allocation_method   = "Static"
}

resource "azurerm_dns_a_record" "pip-Ansible" {
  resource_group_name = azurerm_resource_group.rg-prod-dns-alefsec-com.name
  zone_name           = azurerm_dns_zone.alefsec-com.name
  name                = "ansible"
  ttl                 = "300"
  target_resource_id  = azurerm_public_ip.pip-Ansible.id
}

resource "azurerm_network_security_group" "nsg-Ansible" {
  resource_group_name = azurerm_resource_group.rg-hub.name
  location            = var.azure_region
  name                = "nsg-Ansible"

  security_rule {
    name                       = "SSH-IN"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "nic-Ansible" {
  resource_group_name = azurerm_resource_group.rg-hub.name
  name                = "nic-Ansible"
  location            = var.azure_region

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vnet-hub-default.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip-Ansible.id
  }
}

resource "azurerm_network_interface_security_group_association" "nsg-Ansible" {
  network_interface_id      = azurerm_network_interface.nic-Ansible.id
  network_security_group_id = azurerm_network_security_group.nsg-Ansible.id
}

resource "azurerm_linux_virtual_machine" "vm-Ansible" {
  resource_group_name             = azurerm_resource_group.rg-hub.name
  name                            = "Ansible"
  location                        = var.azure_region
  size                            = "Standard_B2s"
  disable_password_authentication = "false"
  admin_username                  = "vojta"
  admin_password                  = random_password.vojta_password.result
  network_interface_ids           = [azurerm_network_interface.nic-Ansible.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "erockyenterprisesoftwarefoundationinc1653071250513"
    offer     = "rockylinux-9"
    sku       = "rockylinux-9"
    version   = "latest"
  }

  plan {
    name      = "rockylinux-9"
    product   = "rockylinux-9"
    publisher = "erockyenterprisesoftwarefoundationinc1653071250513"
  }
}

module "alef-pki-pod" {
  source = "./modules/alef-pki-pod"

  azure_region                        = var.azure_region
  pod_name                            = "magenta"
  pod_ip_subnet                       = "10.21.0.0/24"
  hub_resource_group_name             = azurerm_resource_group.rg-hub.name
  hub_vnet_name                       = azurerm_virtual_network.vnet-hub.name
  hub_vnet_id                         = azurerm_virtual_network.vnet-hub.id
  public_dns_zone_resource_group_name = azurerm_resource_group.rg-prod-dns-alefsec-com.name
  public_dns_zone_name                = azurerm_dns_zone.alefsec-com.name
}