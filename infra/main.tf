locals {
  name_suffix = "${var.workload}-${var.environment}-${var.location}-${var.instance}"

  tags = {
    project     = "azure-networking-foundation"
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_suffix}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space
  tags                = local.tags
}

# The three tiers share one module: a subnet with default outbound access off, its NSG and the rules.
# The built-in NSG rules at priority 65000 allow all traffic between subnets of the VNet, so every tier lists its own deny-all rules.

module "web" {
  source               = "./modules/tier"
  name                 = "web"
  name_suffix          = local.name_suffix
  location             = azurerm_resource_group.main.location
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefix       = var.web_subnet_prefix
  tags                 = local.tags

  rules = {
    "Allow-HTTPS-Inbound" = {
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      destination_port_range     = "443"
      source_address_prefix      = "Internet"
      destination_address_prefix = var.web_subnet_prefix
    }
    "Allow-AzureLoadBalancer-Inbound" = {
      priority                   = 4000
      direction                  = "Inbound"
      access                     = "Allow"
      source_address_prefix      = "AzureLoadBalancer"
      destination_address_prefix = var.web_subnet_prefix
    }
    "Deny-All-Inbound" = {
      priority  = 4096
      direction = "Inbound"
      access    = "Deny"
    }
    "Allow-Web-To-App-Outbound" = {
      priority                   = 100
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      destination_port_range     = "8443"
      source_address_prefix      = var.web_subnet_prefix
      destination_address_prefix = var.app_subnet_prefix
    }
    "Deny-All-Outbound" = {
      priority  = 4096
      direction = "Outbound"
      access    = "Deny"
    }
  }
}

module "app" {
  source               = "./modules/tier"
  name                 = "app"
  name_suffix          = local.name_suffix
  location             = azurerm_resource_group.main.location
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefix       = var.app_subnet_prefix
  tags                 = local.tags

  rules = {
    "Allow-Web-To-App-Inbound" = {
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      destination_port_range     = "8443"
      source_address_prefix      = var.web_subnet_prefix
      destination_address_prefix = var.app_subnet_prefix
    }
    "Allow-AzureLoadBalancer-Inbound" = {
      priority                   = 4000
      direction                  = "Inbound"
      access                     = "Allow"
      source_address_prefix      = "AzureLoadBalancer"
      destination_address_prefix = var.app_subnet_prefix
    }
    "Deny-All-Inbound" = {
      priority  = 4096
      direction = "Inbound"
      access    = "Deny"
    }
    "Allow-App-To-DB-Outbound" = {
      priority                   = 100
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      destination_port_range     = "1433"
      source_address_prefix      = var.app_subnet_prefix
      destination_address_prefix = var.db_subnet_prefix
    }
    "Deny-All-Outbound" = {
      priority  = 4096
      direction = "Outbound"
      access    = "Deny"
    }
  }
}

module "db" {
  source               = "./modules/tier"
  name                 = "db"
  name_suffix          = local.name_suffix
  location             = azurerm_resource_group.main.location
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefix       = var.db_subnet_prefix
  tags                 = local.tags

  rules = {
    "Allow-App-To-DB-Inbound" = {
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      destination_port_range     = "1433"
      source_address_prefix      = var.app_subnet_prefix
      destination_address_prefix = var.db_subnet_prefix
    }
    "Deny-All-Inbound" = {
      priority  = 4096
      direction = "Inbound"
      access    = "Deny"
    }
    "Deny-All-Outbound" = {
      priority  = 4096
      direction = "Outbound"
      access    = "Deny"
    }
  }
}
