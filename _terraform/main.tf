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

resource "random_password" "ansible_password" {
  length           = 20
  special          = false
  override_special = "!@#$%^&*()_+{}[]<>?"
}

## Create a resource group

resource "azurerm_resource_group" "rg-hub" {
  location = var.azure_region
  name     = "rg-trn-pki-hub"
}

### Define the Hub environment

resource "azurerm_virtual_network" "vnet-hub" {
  resource_group_name = azurerm_resource_group.rg-hub.name
  location            = var.azure_region
  name                = "vnet-Hub"

  address_space = [var.hub_ip_subnet]
}

resource "azurerm_subnet" "vnet-hub-default" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.rg-hub.name
  virtual_network_name = azurerm_virtual_network.vnet-hub.name
  address_prefixes     = azurerm_virtual_network.vnet-hub.address_space
}

resource "azurerm_public_ip" "pip-ansible" {
  name                = "pip-ansible"
  resource_group_name = azurerm_resource_group.rg-hub.name
  location            = var.azure_region
  allocation_method   = "Static"
}

resource "azurerm_dns_a_record" "pip-ansible" {
  resource_group_name = azurerm_resource_group.rg-prod-dns-alefsec-com.name
  zone_name           = azurerm_dns_zone.alefsec-com.name
  name                = "ansible"
  ttl                 = "300"
  target_resource_id  = azurerm_public_ip.pip-ansible.id
}

resource "azurerm_network_security_group" "nsg-ansible" {
  resource_group_name = azurerm_resource_group.rg-hub.name
  location            = var.azure_region
  name                = "nsg-ansible"

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

resource "azurerm_network_interface" "nic-ansible" {
  resource_group_name = azurerm_resource_group.rg-hub.name
  name                = "nic-ansible"
  location            = var.azure_region

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vnet-hub-default.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip-ansible.id
  }
}

resource "azurerm_network_interface_security_group_association" "nsg-ansible" {
  network_interface_id      = azurerm_network_interface.nic-ansible.id
  network_security_group_id = azurerm_network_security_group.nsg-ansible.id
}

resource "azurerm_linux_virtual_machine" "vm-ansible" {
  depends_on = [module.alef-pki-pod]

  resource_group_name             = azurerm_resource_group.rg-hub.name
  name                            = "ansible"
  location                        = var.azure_region
  size                            = "Standard_B2s"
  disable_password_authentication = "false"
  admin_username                  = "ansible"
  admin_password                  = random_password.ansible_password.result
  network_interface_ids           = [azurerm_network_interface.nic-ansible.id]

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

  //  custom_data = base64encode(<<EOF
  //#cloud-config
  //package_upgrade: true
  //packages:
  //  - git
  //  - ansible-core
  //runcmd:
  //  - git clone https://github.com/mirrorofstripes/alef-pki /opt/alef-pki
  //EOF
  //  )
}

resource "azurerm_virtual_machine_extension" "vm-ansible" {
  depends_on = [azurerm_linux_virtual_machine.vm-ansible]

  virtual_machine_id   = azurerm_linux_virtual_machine.vm-ansible.id
  name                 = "Bootstrap-ansible"
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"

  # NOTE 1: Script is executed from a cmd-shell, therefore escape " as \".
  #         Second, since value is json-encoded, escape \" as \\\".
  # NOTE 2: https://hypernephelist.com/2019/06/25/azure-vm-custom-script-extensions-with-terraform.html
  # NOTE 3: Aby celá tahle debilita fungovala s logikou toho, že v systému je často více verzí pythonu naráz, je potřeba zjistit jakou verzi pythonu používá Ansible a pip a moduly instalovat do ní.
  # NOTE 4: Komunikaci s inventářem lze ozkoušet pomocí příkazu # ansible -i inventory/ -m ping linux-servers && ansible -i inventory/ -m win_ping windows-servers
  settings = <<SETTINGS
    {
      "commandToExecute": "dnf install -y git nano ansible-core && mkdir /opt/alef-pki && git clone https://github.com/mirrorofstripes/alef-pki /opt/alef-pki && chmod -R 777 /opt/alef-pki"
    }
SETTINGS
}

resource "terraform_data" "ansible_inventory" {
  depends_on = [azurerm_virtual_machine_extension.vm-ansible]

  provisioner "file" {
    source      = "${path.module}/modules/alef-pki-pod/.temp/"
    destination = "/opt/alef-pki/_ansible/inventory"

    connection {
      type     = "ssh"
      user     = azurerm_linux_virtual_machine.vm-ansible.admin_username
      password = azurerm_linux_virtual_machine.vm-ansible.admin_password
      host     = azurerm_linux_virtual_machine.vm-ansible.public_ip_address
    }
  }
}



resource "random_pet" "pod_name" {
  count  = var.number_of_pods
  length = 2
}

module "alef-pki-pod" {
  count = var.number_of_pods

  source = "./modules/alef-pki-pod"

  azure_region                        = var.azure_region
  pod_name                            = random_pet.pod_name[count.index].id
  pod_ip_subnet                       = cidrsubnet(var.pod_ip_subnet, 8, count.index)
  hub_resource_group_name             = azurerm_resource_group.rg-hub.name
  hub_vnet_name                       = azurerm_virtual_network.vnet-hub.name
  hub_vnet_id                         = azurerm_virtual_network.vnet-hub.id
  public_dns_zone_resource_group_name = azurerm_resource_group.rg-prod-dns-alefsec-com.name
  public_dns_zone_name                = azurerm_dns_zone.alefsec-com.name
}