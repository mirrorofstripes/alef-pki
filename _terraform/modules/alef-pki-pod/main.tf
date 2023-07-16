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

## Generate an admin password

resource "random_password" "maestro_password" {
  length           = 20
  special          = true
  override_special = "!@#$%^&*()_+{}[]<>?"
}

## Create a resource group

resource "azurerm_resource_group" "rg-pod" {
  location = var.azure_region
  name     = "rg-trn-pki-${var.pod_name}"
}

## Define Root CA environments

resource "azurerm_virtual_network" "vnet-RootCA" {
  resource_group_name = azurerm_resource_group.rg-pod.name
  name                = "vnet-${var.pod_name}-RootCA"
  location            = var.azure_region
  address_space       = [cidrsubnet(var.pod_ip_subnet, 1, 1)]
}

resource "azurerm_subnet" "vnet-RootCA-default" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.rg-pod.name
  virtual_network_name = azurerm_virtual_network.vnet-RootCA.name
  address_prefixes     = azurerm_virtual_network.vnet-RootCA.address_space
}

resource "azurerm_public_ip" "pip-RootCA" {
  name                = "pip-${var.pod_name}-RootCA"
  resource_group_name = azurerm_resource_group.rg-pod.name
  location            = var.azure_region
  sku                 = "Basic"
  allocation_method   = "Static"
}

resource "azurerm_dns_a_record" "pip-RootCA" {
  resource_group_name = azurerm_resource_group.rg-pod.name
  zone_name           = azurerm_dns_zone.pod-alefsec-com.name
  name                = "rca"
  ttl                 = "300"
  target_resource_id  = azurerm_public_ip.pip-RootCA.id
}

resource "azurerm_network_interface" "nic-RootCA" {
  resource_group_name = azurerm_resource_group.rg-pod.name
  name                = "nic-${var.pod_name}-RootCA"
  location            = var.azure_region

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vnet-RootCA-default.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip-RootCA.id
  }
}

resource "azurerm_network_security_group" "nsg-RootCA" {
  resource_group_name = azurerm_resource_group.rg-pod.name
  location            = var.azure_region
  name                = "nsg-${var.pod_name}-RootCA"

  security_rule {
    name                       = "RDP-IN"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "nsg-RootCA" {
  network_interface_id      = azurerm_network_interface.nic-RootCA.id
  network_security_group_id = azurerm_network_security_group.nsg-RootCA.id
}

resource "azurerm_windows_virtual_machine" "vm-RootCA" {
  resource_group_name   = azurerm_resource_group.rg-pod.name
  name                  = "RootCA"
  location              = var.azure_region
  size                  = "Standard_A1v2"
  admin_username        = "maestro"
  admin_password        = random_password.maestro_password.result
  network_interface_ids = [azurerm_network_interface.nic-RootCA.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter"
    version   = "latest"
  }
}

## Define AD Domain environments

resource "azurerm_virtual_network" "vnet-AD" {
  resource_group_name = azurerm_resource_group.rg-pod.name
  name                = "vnet-AD"
  location            = var.azure_region
  address_space       = [cidrsubnet(var.pod_ip_subnet, 1, 0)]
}

resource "azurerm_subnet" "vnet-AD-default" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.rg-pod.name
  virtual_network_name = azurerm_virtual_network.vnet-AD.name
  address_prefixes     = azurerm_virtual_network.vnet-AD.address_space
}

resource "azurerm_virtual_network_dns_servers" "vnet-AD" {
  depends_on = [
    azurerm_virtual_machine_extension.vm-hop01,
    azurerm_virtual_machine_extension.vm-dc01,
    azurerm_virtual_machine_extension.vm-ica01,
    azurerm_virtual_machine_extension.vm-cdp01
    #azurerm_virtual_machine_extension.vm-web01
  ]
  virtual_network_id = azurerm_virtual_network.vnet-AD.id
  dns_servers        = [azurerm_network_interface.nic-dc01.private_ip_address]
}

resource "azurerm_virtual_network_peering" "peer-AD-to-Hub" {
  name                      = "peer-AD-${var.pod_name}-to-Hub"
  resource_group_name       = azurerm_resource_group.rg-pod.name
  virtual_network_name      = azurerm_virtual_network.vnet-AD.name
  remote_virtual_network_id = var.hub_vnet_id
}

resource "azurerm_virtual_network_peering" "peer-Hub-to-AD" {
  name                      = "peer-Hub-to-AD-${var.pod_name}"
  resource_group_name       = var.hub_resource_group_name
  virtual_network_name      = var.hub_vnet_name
  remote_virtual_network_id = azurerm_virtual_network.vnet-AD.id
}

resource "azurerm_private_dns_zone" "private-dns-zone" {
  resource_group_name = azurerm_resource_group.rg-pod.name
  name                = "${var.pod_name}.lab"
}

resource "random_id" "private-dns-link-to-AD" {
  byte_length = 8
}

resource "azurerm_private_dns_zone_virtual_network_link" "private-dns-link-to-AD" {
  resource_group_name   = azurerm_resource_group.rg-pod.name
  private_dns_zone_name = azurerm_private_dns_zone.private-dns-zone.name
  virtual_network_id    = azurerm_virtual_network.vnet-AD.id
  name                  = random_id.private-dns-link-to-AD.hex
  registration_enabled  = true
}

resource "random_id" "private-dns-link-to-Hub" {
  byte_length = 8
}

resource "azurerm_private_dns_zone_virtual_network_link" "private-dns-link-to-Hub" {
  resource_group_name   = azurerm_resource_group.rg-pod.name
  private_dns_zone_name = azurerm_private_dns_zone.private-dns-zone.name
  virtual_network_id    = var.hub_vnet_id
  name                  = random_id.private-dns-link-to-Hub.hex
  registration_enabled  = false
}

resource "azurerm_dns_zone" "pod-alefsec-com" {
  resource_group_name = azurerm_resource_group.rg-pod.name
  name                = "${var.pod_name}.alefsec.com"
}

resource "azurerm_dns_ns_record" "pod-alefsec-com" {
  resource_group_name = var.public_dns_zone_resource_group_name
  zone_name           = var.public_dns_zone_name
  name                = var.pod_name
  ttl                 = "300"
  records             = azurerm_dns_zone.pod-alefsec-com.name_servers
}

### Define Hop VMs

resource "azurerm_public_ip" "pip-hop01" {
  resource_group_name = azurerm_resource_group.rg-pod.name
  location            = var.azure_region
  name                = "pip-hop01"
  allocation_method   = "Static"
}

resource "azurerm_dns_a_record" "pip-hop01" {
  resource_group_name = azurerm_resource_group.rg-pod.name
  zone_name           = azurerm_dns_zone.pod-alefsec-com.name
  name                = "hop"
  ttl                 = "300"
  target_resource_id  = azurerm_public_ip.pip-hop01.id
}

resource "azurerm_network_security_group" "nsg-hop01" {
  resource_group_name = azurerm_resource_group.rg-pod.name
  location            = var.azure_region
  name                = "nsg-hop01"

  security_rule {
    name                       = "RDP-IN"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "nic-hop01" {
  resource_group_name = azurerm_resource_group.rg-pod.name
  location            = var.azure_region
  name                = "nic-hop01"
  depends_on          = [azurerm_private_dns_zone_virtual_network_link.private-dns-link-to-AD]

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vnet-AD-default.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip-hop01.id
  }
}

resource "azurerm_network_interface_security_group_association" "nsg-hop01" {
  network_interface_id      = azurerm_network_interface.nic-hop01.id
  network_security_group_id = azurerm_network_security_group.nsg-hop01.id
}

resource "azurerm_windows_virtual_machine" "vm-hop01" {
  resource_group_name   = azurerm_resource_group.rg-pod.name
  location              = var.azure_region
  name                  = "ad-hop01"
  size                  = "Standard_B2s"
  admin_username        = "maestro"
  admin_password        = random_password.maestro_password.result
  network_interface_ids = [azurerm_network_interface.nic-hop01.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "vm-hop01" {
  virtual_machine_id   = azurerm_windows_virtual_machine.vm-hop01.id
  name                 = "Initialize-WinRM-for-Ansible"
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  # NOTE 1: Script is executed from a cmd-shell, therefore escape " as \".
  #         Second, since value is json-encoded, escape \" as \\\".
  settings = <<SETTINGS
    {
      "commandToExecute": "powershell -ExecutionPolicy Bypass -Command \"Invoke-WebRequest -UseBasicParsing -Uri https://raw.githubusercontent.com/ansible/ansible/stable-2.15/examples/scripts/ConfigureRemotingForAnsible.ps1 | Invoke-Expression\""
    }
SETTINGS
}

### Define DC VMs

resource "azurerm_network_interface" "nic-dc01" {
  resource_group_name = azurerm_resource_group.rg-pod.name
  location            = var.azure_region
  name                = "nic-dc01"
  depends_on          = [azurerm_private_dns_zone_virtual_network_link.private-dns-link-to-AD]

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vnet-AD-default.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "vm-dc01" {
  resource_group_name   = azurerm_resource_group.rg-pod.name
  location              = var.azure_region
  name                  = "ad-dc01"
  size                  = "Standard_B2s"
  admin_username        = "maestro"
  admin_password        = random_password.maestro_password.result
  network_interface_ids = [azurerm_network_interface.nic-dc01.id]

  os_disk {
    caching              = "ReadOnly"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "vm-dc01" {
  virtual_machine_id   = azurerm_windows_virtual_machine.vm-dc01.id
  name                 = "Initialize-WinRM-for-Ansible"
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  # NOTE 1: Script is executed from a cmd-shell, therefore escape " as \".
  #         Second, since value is json-encoded, escape \" as \\\".
  settings = <<SETTINGS
    {
      "commandToExecute": "powershell -ExecutionPolicy Bypass -Command \"Invoke-WebRequest -UseBasicParsing -Uri https://raw.githubusercontent.com/ansible/ansible/stable-2.15/examples/scripts/ConfigureRemotingForAnsible.ps1 | Invoke-Expression\""
    }
SETTINGS
}

### Define ICA VMs

resource "azurerm_network_interface" "nic-ica01" {
  resource_group_name = azurerm_resource_group.rg-pod.name
  location            = var.azure_region
  name                = "nic-ica01"
  depends_on          = [azurerm_private_dns_zone_virtual_network_link.private-dns-link-to-AD]

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vnet-AD-default.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "vm-ica01" {
  resource_group_name   = azurerm_resource_group.rg-pod.name
  location              = var.azure_region
  name                  = "ad-ica01"
  size                  = "Standard_B2s"
  admin_username        = "maestro"
  admin_password        = random_password.maestro_password.result
  network_interface_ids = [azurerm_network_interface.nic-ica01.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "vm-ica01" {
  virtual_machine_id   = azurerm_windows_virtual_machine.vm-ica01.id
  name                 = "Initialize-WinRM-for-Ansible"
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  # NOTE 1: Script is executed from a cmd-shell, therefore escape " as \".
  #         Second, since value is json-encoded, escape \" as \\\".
  settings = <<SETTINGS
    {
      "commandToExecute": "powershell -ExecutionPolicy Bypass -Command \"Invoke-WebRequest -UseBasicParsing -Uri https://raw.githubusercontent.com/ansible/ansible/stable-2.15/examples/scripts/ConfigureRemotingForAnsible.ps1 | Invoke-Expression\""
    }
SETTINGS
}

### Define CDP VMs

resource "azurerm_public_ip" "pip-cdp01" {
  resource_group_name = azurerm_resource_group.rg-pod.name
  location            = var.azure_region
  name                = "pip-cdp01"
  allocation_method   = "Static"
}

resource "azurerm_dns_a_record" "pip-cdp01" {
  resource_group_name = azurerm_resource_group.rg-pod.name
  zone_name           = azurerm_dns_zone.pod-alefsec-com.name
  name                = "cdp"
  ttl                 = "300"
  target_resource_id  = azurerm_public_ip.pip-cdp01.id
}

resource "azurerm_network_security_group" "nsg-cdp01" {
  resource_group_name = azurerm_resource_group.rg-pod.name
  location            = var.azure_region
  name                = "nsg-cdp01"

  security_rule {
    name                       = "HTTP-IN"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "nic-cdp01" {
  resource_group_name = azurerm_resource_group.rg-pod.name
  location            = var.azure_region
  name                = "nic-cdp01"
  depends_on          = [azurerm_private_dns_zone_virtual_network_link.private-dns-link-to-AD]

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vnet-AD-default.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip-cdp01.id
  }
}

resource "azurerm_network_interface_security_group_association" "nsg-cdp01" {
  network_interface_id      = azurerm_network_interface.nic-cdp01.id
  network_security_group_id = azurerm_network_security_group.nsg-cdp01.id
}

resource "azurerm_windows_virtual_machine" "vm-cdp01" {
  resource_group_name   = azurerm_resource_group.rg-pod.name
  location              = var.azure_region
  name                  = "ad-cdp01"
  size                  = "Standard_B2s"
  admin_username        = "maestro"
  admin_password        = random_password.maestro_password.result
  network_interface_ids = [azurerm_network_interface.nic-cdp01.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "vm-cdp01" {
  virtual_machine_id   = azurerm_windows_virtual_machine.vm-cdp01.id
  name                 = "Initialize-WinRM-for-Ansible"
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  # NOTE 1: Script is executed from a cmd-shell, therefore escape " as \".
  #         Second, since value is json-encoded, escape \" as \\\".
  settings = <<SETTINGS
    {
      "commandToExecute": "powershell -ExecutionPolicy Bypass -Command \"Invoke-WebRequest -UseBasicParsing -Uri https://raw.githubusercontent.com/ansible/ansible/stable-2.15/examples/scripts/ConfigureRemotingForAnsible.ps1 | Invoke-Expression\""
    }
SETTINGS
}

### Define WEBs

resource "azurerm_network_interface" "nic-web01" {
  resource_group_name = azurerm_resource_group.rg-pod.name
  location            = var.azure_region
  name                = "nic-web01"
  depends_on          = [azurerm_private_dns_zone_virtual_network_link.private-dns-link-to-AD]

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vnet-AD-default.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "vm-web01" {
  resource_group_name             = azurerm_resource_group.rg-pod.name
  location                        = var.azure_region
  name                            = "ad-web01"
  size                            = "Standard_A1v2"
  disable_password_authentication = "false"
  admin_username                  = "maestro"
  admin_password                  = random_password.maestro_password.result
  network_interface_ids           = [azurerm_network_interface.nic-web01.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
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

### Define an inventory file for Ansible

resource "local_file" "file-pod-inventory" {
  filename = "${path.module}/.temp/${var.pod_name}.yml"
  content  = <<EOF
all:
  children:
    windows-servers:
      children:
        ad-hop01:
          hosts:
            ${azurerm_windows_virtual_machine.vm-hop01.name}.${azurerm_private_dns_zone.private-dns-zone.name}:
              ansible_password: '${random_password.maestro_password.result}'
              pod_name: '${var.pod_name}'

        ad-dc01:
          hosts:
            ${azurerm_windows_virtual_machine.vm-dc01.name}.${azurerm_private_dns_zone.private-dns-zone.name}:
              ansible_password: '${random_password.maestro_password.result}'
              pod_name: '${var.pod_name}'
        
        ad-ica01:
          hosts:
            ${azurerm_windows_virtual_machine.vm-ica01.name}.${azurerm_private_dns_zone.private-dns-zone.name}:
              ansible_password: '${random_password.maestro_password.result}'
              pod_name: '${var.pod_name}'
        
        ad-cdp01:
          hosts:
            ${azurerm_windows_virtual_machine.vm-cdp01.name}.${azurerm_private_dns_zone.private-dns-zone.name}:
              ansible_password: '${random_password.maestro_password.result}'
              pod_name: '${var.pod_name}'
    
    linux-servers: 
      children:
        ad-web01:
          hosts:
            ${azurerm_linux_virtual_machine.vm-web01.name}.${azurerm_private_dns_zone.private-dns-zone.name}:
              ansible_password: '${random_password.maestro_password.result}'
              ansible_become_password: '${random_password.maestro_password.result}'
              pod_name: '${var.pod_name}'
EOF
}