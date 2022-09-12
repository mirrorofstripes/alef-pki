### Define Resource Groups

resource "azurerm_resource_group" "rg-pki-lab-Ansible" {
  name     = "rg-pki-lab-Ansible"
  location = "westeurope"
}

### Define Root CA environments

resource "azurerm_virtual_network" "vnet-pki-Ansible" {
  resource_group_name = azurerm_resource_group.rg-pki-lab-Ansible.name
  name                = "vnet-pki-Ansible"
  location            = "westeurope"
  address_space       = ["10.59.0.0/24"]
}

resource "azurerm_subnet" "vnet-pki-Ansible-default" {

  name                 = "default"
  resource_group_name  = azurerm_resource_group.rg-pki-lab-Ansible.name
  virtual_network_name = azurerm_virtual_network.vnet-pki-Ansible.name
  address_prefixes     = ["10.59.0.0/24"]
}

resource "azurerm_public_ip" "pip-pki-Ansible" {
  name                = "pip-pki-Ansible"
  resource_group_name = azurerm_resource_group.rg-pki-lab-Ansible.name
  location            = "westeurope"
  allocation_method   = "Static"
}

resource "azurerm_network_security_group" "nsg-pki-Ansible" {
  resource_group_name = azurerm_resource_group.rg-pki-lab-Ansible.name
  location            = "westeurope"
  name                = "nsg-pki-Ansible"

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

resource "azurerm_network_interface" "nic-pki-Ansible" {
  resource_group_name = azurerm_resource_group.rg-pki-lab-Ansible.name
  name                = "Ansible"
  location            = "westeurope"

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vnet-pki-Ansible-default.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.59.0.4"
    public_ip_address_id          = azurerm_public_ip.pip-pki-Ansible.id
  }
}

resource "azurerm_network_interface_security_group_association" "nsg-ass-pki-Ansible" {
  network_interface_id      = azurerm_network_interface.nic-pki-Ansible.id
  network_security_group_id = azurerm_network_security_group.nsg-pki-Ansible.id
}

resource "azurerm_linux_virtual_machine" "vm-pki-Ansible" {
  resource_group_name             = azurerm_resource_group.rg-pki-lab-Ansible.name
  name                            = "Ansible"
  location                        = "westeurope"
  size                            = "Standard_B2s"
  disable_password_authentication = "false"
  admin_username                  = "vojta"
  admin_password                  = "iinfC8eo4t0Bn3GR336n"
  network_interface_ids           = [azurerm_network_interface.nic-pki-Ansible.id]

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

  custom_data = filebase64("ad-web01.sh")
}