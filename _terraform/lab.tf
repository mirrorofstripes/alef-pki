
### Define variables

variable "instances" {
  type        = list(string)
  description = "List of instances"
  default     = (["100", "110", "120", "130", "140", "150", "160", "170", "180", "190"])
}

### Define Resource Groups

resource "azurerm_resource_group" "rg-pki-lab" {
  for_each = toset(var.instances)
  name     = "rg-pki-lab-${each.key}"
  location = "westeurope"
}

### Define Root CA environments

resource "azurerm_virtual_network" "vnet-pki-RootCA" {
  for_each            = toset(var.instances)
  resource_group_name = azurerm_resource_group.rg-pki-lab["${each.key}"].name
  name                = "vnet-pki-RootCA"
  location            = "westeurope"
  address_space       = ["10.${each.key}.1.0/24"]
}

resource "azurerm_subnet" "vnet-pki-RootCA-default" {
  for_each             = toset(var.instances)
  name                 = "default"
  resource_group_name  = azurerm_resource_group.rg-pki-lab["${each.key}"].name
  virtual_network_name = azurerm_virtual_network.vnet-pki-RootCA["${each.key}"].name
  address_prefixes     = ["10.${each.key}.1.0/24"]
}

resource "azurerm_public_ip" "pip-pki-RootCA" {
  for_each            = toset(var.instances)
  name                = "pip-pki-RootCA"
  resource_group_name = azurerm_resource_group.rg-pki-lab["${each.key}"].name
  location            = "westeurope"
  allocation_method   = "Static"
}

resource "azurerm_network_security_group" "nsg-pki-RootCA" {
  for_each            = toset(var.instances)
  resource_group_name = azurerm_resource_group.rg-pki-lab["${each.key}"].name
  location            = "westeurope"
  name                = "nsg-pki-RootCA"

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

resource "azurerm_network_interface" "nic-pki-RootCA" {
  for_each            = toset(var.instances)
  resource_group_name = azurerm_resource_group.rg-pki-lab["${each.key}"].name
  name                = "RootCA"
  location            = "westeurope"

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vnet-pki-RootCA-default["${each.key}"].id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.${each.key}.1.4"
    public_ip_address_id          = azurerm_public_ip.pip-pki-RootCA["${each.key}"].id
  }
}

resource "azurerm_network_interface_security_group_association" "nsg-ass-pki-RootCA" {
  for_each                  = toset(var.instances)
  network_interface_id      = azurerm_network_interface.nic-pki-RootCA["${each.key}"].id
  network_security_group_id = azurerm_network_security_group.nsg-pki-RootCA["${each.key}"].id
}

resource "azurerm_windows_virtual_machine" "vm-pki-RootCA" {
  for_each              = toset(var.instances)
  resource_group_name   = azurerm_resource_group.rg-pki-lab["${each.key}"].name
  name                  = "RootCA"
  location              = "westeurope"
  size                  = "Standard_B2s"
  admin_username        = "maestro"
  admin_password        = "8CNRA8QTnQ7EExD9MU24g"
  network_interface_ids = [azurerm_network_interface.nic-pki-RootCA["${each.key}"].id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-datacenter"
    version   = "latest"
  }
}

### Define Lab environments

resource "azurerm_virtual_network" "vnet-pki-Lab" {
  for_each            = toset(var.instances)
  resource_group_name = azurerm_resource_group.rg-pki-lab["${each.key}"].name
  name                = "vnet-pki-Lab"
  location            = "westeurope"
  address_space       = ["10.${each.key}.2.0/24"]
}

resource "azurerm_virtual_network_dns_servers" "vnet-dns-pki-Lab" {
  for_each = toset(var.instances)
  depends_on = [
    azurerm_windows_virtual_machine.vm-pki-hop01,
    azurerm_windows_virtual_machine.vm-pki-dc01,
    azurerm_windows_virtual_machine.vm-pki-ica01,
    azurerm_windows_virtual_machine.vm-pki-cdp01,
    azurerm_linux_virtual_machine.vm-pki-web01
  ]
  virtual_network_id = azurerm_virtual_network.vnet-pki-Lab["${each.key}"].id
  dns_servers        = ["10.${each.key}.2.5"]
}

resource "azurerm_virtual_network_peering" "vnet-peering-pki-Lab-to-pki-Ansible" {
  for_each                  = toset(var.instances)
  name                      = "pki-Lab-to-pki-Ansible-${each.key}"
  resource_group_name       = azurerm_resource_group.rg-pki-lab["${each.key}"].name
  virtual_network_name      = azurerm_virtual_network.vnet-pki-Lab["${each.key}"].name
  remote_virtual_network_id = azurerm_virtual_network.vnet-pki-Ansible.id
}

resource "azurerm_virtual_network_peering" "vnet-peering-pki-Ansible-to-pki-Lab" {
  for_each                  = toset(var.instances)
  name                      = "pki-Ansible-to-pki-Lab-${each.key}"
  resource_group_name       = azurerm_resource_group.rg-pki-lab-Ansible.name
  virtual_network_name      = azurerm_virtual_network.vnet-pki-Ansible.name
  remote_virtual_network_id = azurerm_virtual_network.vnet-pki-Lab["${each.key}"].id
}

resource "azurerm_subnet" "vnet-pki-Lab-default" {
  for_each             = toset(var.instances)
  name                 = "default"
  resource_group_name  = azurerm_resource_group.rg-pki-lab["${each.key}"].name
  virtual_network_name = azurerm_virtual_network.vnet-pki-Lab["${each.key}"].name
  address_prefixes     = ["10.${each.key}.2.0/24"]
}

## Define hops

resource "azurerm_public_ip" "pip-pki-hop01" {
  for_each            = toset(var.instances)
  name                = "pip-pki-hop01"
  resource_group_name = azurerm_resource_group.rg-pki-lab["${each.key}"].name
  location            = "westeurope"
  allocation_method   = "Static"
}

resource "azurerm_network_security_group" "nsg-pki-hop01" {
  for_each            = toset(var.instances)
  resource_group_name = azurerm_resource_group.rg-pki-lab["${each.key}"].name
  location            = "westeurope"
  name                = "nsg-pki-hop01"

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

resource "azurerm_network_interface" "nic-pki-hop01" {
  for_each            = toset(var.instances)
  resource_group_name = azurerm_resource_group.rg-pki-lab["${each.key}"].name
  name                = "ad-hop01"
  location            = "westeurope"

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vnet-pki-Lab-default["${each.key}"].id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.${each.key}.2.4"
    public_ip_address_id          = azurerm_public_ip.pip-pki-hop01["${each.key}"].id
  }
}

resource "azurerm_network_interface_security_group_association" "nsg-ass-pki-hop01" {
  for_each                  = toset(var.instances)
  network_interface_id      = azurerm_network_interface.nic-pki-hop01["${each.key}"].id
  network_security_group_id = azurerm_network_security_group.nsg-pki-hop01["${each.key}"].id
}

resource "azurerm_windows_virtual_machine" "vm-pki-hop01" {
  for_each              = toset(var.instances)
  resource_group_name   = azurerm_resource_group.rg-pki-lab["${each.key}"].name
  name                  = "ad-hop01"
  location              = "westeurope"
  size                  = "Standard_B2s"
  admin_username        = "maestro"
  admin_password        = "8CNRA8QTnQ7EExD9MU24g"
  network_interface_ids = [azurerm_network_interface.nic-pki-hop01["${each.key}"].id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-datacenter"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "vm-init-pki-hop01" {
  for_each             = toset(var.instances)
  virtual_machine_id   = azurerm_windows_virtual_machine.vm-pki-hop01["${each.key}"].id
  name                 = "Initialize-WinRM-for-Ansible"
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  # NOTE 1: Script is executed from a cmd-shell, therefore escape " as \".
  #         Second, since value is json-encoded, escape \" as \\\".
  settings = <<SETTINGS
    {
      "commandToExecute": "powershell -ExecutionPolicy Bypass -Command \"Invoke-WebRequest -UseBasicParsing -Uri https://raw.githubusercontent.com/ansible/ansible/devel/examples/scripts/ConfigureRemotingForAnsible.ps1 | Invoke-Expression\""
    }
SETTINGS
}

### Define DCs

resource "azurerm_network_interface" "nic-pki-dc01" {
  for_each            = toset(var.instances)
  resource_group_name = azurerm_resource_group.rg-pki-lab["${each.key}"].name
  name                = "ad-dc01"
  location            = "westeurope"

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vnet-pki-Lab-default["${each.key}"].id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.${each.key}.2.5"
  }
}

resource "azurerm_windows_virtual_machine" "vm-pki-dc01" {
  for_each              = toset(var.instances)
  resource_group_name   = azurerm_resource_group.rg-pki-lab["${each.key}"].name
  name                  = "ad-dc01"
  location              = "westeurope"
  size                  = "Standard_B2s"
  admin_username        = "maestro"
  admin_password        = "8CNRA8QTnQ7EExD9MU24g"
  network_interface_ids = [azurerm_network_interface.nic-pki-dc01["${each.key}"].id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-datacenter"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "vm-init-pki-dc01" {
  for_each             = toset(var.instances)
  virtual_machine_id   = azurerm_windows_virtual_machine.vm-pki-dc01["${each.key}"].id
  name                 = "Initialize-WinRM-for-Ansible"
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  # NOTE 1: Script is executed from a cmd-shell, therefore escape " as \".
  #         Second, since value is json-encoded, escape \" as \\\".
  settings = <<SETTINGS
    {
      "commandToExecute": "powershell -ExecutionPolicy Bypass -Command \"Invoke-WebRequest -UseBasicParsing -Uri https://raw.githubusercontent.com/ansible/ansible/devel/examples/scripts/ConfigureRemotingForAnsible.ps1 | Invoke-Expression\""
    }
SETTINGS
}

### Define ICAs

resource "azurerm_network_interface" "nic-pki-ica01" {
  for_each            = toset(var.instances)
  resource_group_name = azurerm_resource_group.rg-pki-lab["${each.key}"].name
  name                = "ad-ica01"
  location            = "westeurope"

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vnet-pki-Lab-default["${each.key}"].id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.${each.key}.2.6"
  }
}

resource "azurerm_windows_virtual_machine" "vm-pki-ica01" {
  for_each              = toset(var.instances)
  resource_group_name   = azurerm_resource_group.rg-pki-lab["${each.key}"].name
  name                  = "ad-ica01"
  location              = "westeurope"
  size                  = "Standard_B2s"
  admin_username        = "maestro"
  admin_password        = "8CNRA8QTnQ7EExD9MU24g"
  network_interface_ids = [azurerm_network_interface.nic-pki-ica01["${each.key}"].id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-datacenter"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "vm-init-pki-ica01" {
  for_each             = toset(var.instances)
  virtual_machine_id   = azurerm_windows_virtual_machine.vm-pki-ica01["${each.key}"].id
  name                 = "Initialize-WinRM-for-Ansible"
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  # NOTE 1: Script is executed from a cmd-shell, therefore escape " as \".
  #         Second, since value is json-encoded, escape \" as \\\".
  settings = <<SETTINGS
    {
      "commandToExecute": "powershell -ExecutionPolicy Bypass -Command \"Invoke-WebRequest -UseBasicParsing -Uri https://raw.githubusercontent.com/ansible/ansible/devel/examples/scripts/ConfigureRemotingForAnsible.ps1 | Invoke-Expression\""
    }
SETTINGS
}

### Define CDPs

resource "azurerm_network_interface" "nic-pki-cdp01" {
  for_each            = toset(var.instances)
  resource_group_name = azurerm_resource_group.rg-pki-lab["${each.key}"].name
  name                = "ad-cdp01"
  location            = "westeurope"

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vnet-pki-Lab-default["${each.key}"].id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.${each.key}.2.7"
  }
}

resource "azurerm_windows_virtual_machine" "vm-pki-cdp01" {
  for_each              = toset(var.instances)
  resource_group_name   = azurerm_resource_group.rg-pki-lab["${each.key}"].name
  name                  = "ad-cdp01"
  location              = "westeurope"
  size                  = "Standard_B2s"
  admin_username        = "maestro"
  admin_password        = "8CNRA8QTnQ7EExD9MU24g"
  network_interface_ids = [azurerm_network_interface.nic-pki-cdp01["${each.key}"].id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-datacenter"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "vm-init-pki-cdp01" {
  for_each             = toset(var.instances)
  virtual_machine_id   = azurerm_windows_virtual_machine.vm-pki-cdp01["${each.key}"].id
  name                 = "Initialize-WinRM-for-Ansible"
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  # NOTE 1: Script is executed from a cmd-shell, therefore escape " as \".
  #         Second, since value is json-encoded, escape \" as \\\".
  settings = <<SETTINGS
    {
      "commandToExecute": "powershell -ExecutionPolicy Bypass -Command \"Invoke-WebRequest -UseBasicParsing -Uri https://raw.githubusercontent.com/ansible/ansible/devel/examples/scripts/ConfigureRemotingForAnsible.ps1 | Invoke-Expression\""
    }
SETTINGS
}

### Define WEBs

resource "azurerm_network_interface" "nic-pki-web01" {
  for_each            = toset(var.instances)
  resource_group_name = azurerm_resource_group.rg-pki-lab["${each.key}"].name
  name                = "ad-web"
  location            = "westeurope"

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vnet-pki-Lab-default["${each.key}"].id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.${each.key}.2.8"
  }
}

resource "azurerm_linux_virtual_machine" "vm-pki-web01" {
  for_each                        = toset(var.instances)
  resource_group_name             = azurerm_resource_group.rg-pki-lab["${each.key}"].name
  name                            = "ad-web01"
  location                        = "westeurope"
  size                            = "Standard_B2s"
  disable_password_authentication = "false"
  admin_username                  = "maestro"
  admin_password                  = "8CNRA8QTnQ7EExD9MU24g"
  network_interface_ids           = [azurerm_network_interface.nic-pki-web01["${each.key}"].id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "erockyenterprisesoftwarefoundationinc1653071250513"
    offer     = "rockylinux"
    sku       = "free"
    version   = "8.6.0"
  }

  plan {
    name      = "free"
    product   = "rockylinux"
    publisher = "erockyenterprisesoftwarefoundationinc1653071250513"
  }
}