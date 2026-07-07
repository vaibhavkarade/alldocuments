terraform {
  required_providers {
    #azurerm = {
      #source = "hashicorp/azurerm"
      #version = "3.8.0"
    #}

  }
  backend "azurerm"{
      
  }
  
}

provider "azurerm" {
  
  subscription_id = "08fcb844-e578-44ed-adfb-519383394cb0"
  #client_id       = "ca4dcc62-25f8-4018-a681-112f0ad82d7d"
  #client_secret   = "vvt8Q~OYCpVqB4Y4yizimiECEPtTjWkMdzbQFdbw"
  tenant_id       = "b41b72d0-4e9f-4c26-8a69-f949f367c91d"
  features {}
}

resource "azurerm_resource_group" "appgrp" {
  name     = "app-grp"
  location = "North Europe"
}

