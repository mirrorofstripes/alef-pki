resource "azurerm_resource_group" "rg-prod-dns-alefsec-com" {
  location = "westeurope"
  name     = "rg-prod-dns-alefsec.com"
}

import {
  to = azurerm_resource_group.rg-prod-dns-alefsec-com
  id = "/subscriptions/3f8210db-d6ea-450e-8841-df355ea44e97/resourceGroups/rg-prod-dns-alefsec.com"
}

resource "azurerm_dns_zone" "alefsec-com" {
  resource_group_name = azurerm_resource_group.rg-prod-dns-alefsec-com.name
  name                = "alefsec.com"
}

import {
  to = azurerm_dns_zone.alefsec-com
  id = "/subscriptions/3f8210db-d6ea-450e-8841-df355ea44e97/resourceGroups/rg-prod-dns-alefsec.com/providers/Microsoft.Network/dnsZones/alefsec.com"
}