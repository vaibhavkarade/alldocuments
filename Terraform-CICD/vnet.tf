resource "azurerm_virtual_network" "appnetwork" {
  name                = "app-networkbunty"
  location            = "North Europe"
  resource_group_name = "app-grp"
  address_space       = ["10.0.0.0/16"]

  subnet {
    name           = "subnetbunty"
    address_prefix = "10.0.0.0/24"
  }

  subnet {
    name           = "subnetbunty2"
    address_prefix = "10.0.1.0/24"    
  }
  depends_on = [
      azurerm_resource_group.appgrp
  ]
}