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

resource "azurerm_subnet" "web" {
  name                            = "snet-web"
  resource_group_name             = azurerm_resource_group.main.name
  virtual_network_name            = azurerm_virtual_network.main.name
  address_prefixes                = [var.web_subnet_prefix]
  default_outbound_access_enabled = false
}

resource "azurerm_network_security_group" "web" {
  name                = "nsg-web-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}

resource "azurerm_network_security_rule" "web_allow_https_inbound" {
  name                        = "Allow-HTTPS-Inbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "Internet"
  destination_address_prefix  = var.web_subnet_prefix
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.web.name
}

resource "azurerm_network_security_rule" "web_allow_lb_inbound" {
  name                        = "Allow-AzureLoadBalancer-Inbound"
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = var.web_subnet_prefix
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.web.name
}

resource "azurerm_network_security_rule" "web_deny_all_inbound" {
  name                        = "Deny-All-Inbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.web.name
}

resource "azurerm_subnet" "app" {
  name                            = "snet-app"
  resource_group_name             = azurerm_resource_group.main.name
  virtual_network_name            = azurerm_virtual_network.main.name
  address_prefixes                = [var.app_subnet_prefix]
  default_outbound_access_enabled = false
}

resource "azurerm_network_security_group" "app" {
  name                = "nsg-app-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

resource "azurerm_network_security_rule" "app_allow_web_inbound" {
  name                        = "Allow-Web-To-App-Inbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8443"
  source_address_prefix       = var.web_subnet_prefix
  destination_address_prefix  = var.app_subnet_prefix
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.app.name
}

resource "azurerm_network_security_rule" "app_allow_lb_inbound" {
  name                        = "Allow-AzureLoadBalancer-Inbound"
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = var.app_subnet_prefix
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.app.name
}

resource "azurerm_network_security_rule" "app_deny_all_inbound" {
  name                        = "Deny-All-Inbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.app.name
}

resource "azurerm_network_security_rule" "app_allow_db_outbound" {
  name                        = "Allow-App-To-DB-Outbound"
  priority                    = 100
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "1433"
  source_address_prefix       = var.app_subnet_prefix
  destination_address_prefix  = var.db_subnet_prefix
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.app.name
}

resource "azurerm_network_security_rule" "app_deny_all_outbound" {
  name                        = "Deny-All-Outbound"
  priority                    = 4096
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.app.name
}

resource "azurerm_subnet" "db" {
  name                            = "snet-db"
  resource_group_name             = azurerm_resource_group.main.name
  virtual_network_name            = azurerm_virtual_network.main.name
  address_prefixes                = [var.db_subnet_prefix]
  default_outbound_access_enabled = false
}

resource "azurerm_network_security_group" "db" {
  name                = "nsg-db-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "db" {
  subnet_id                 = azurerm_subnet.db.id
  network_security_group_id = azurerm_network_security_group.db.id
}

resource "azurerm_network_security_rule" "db_allow_app_inbound" {
  name                        = "Allow-App-To-DB-Inbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "1433"
  source_address_prefix       = var.app_subnet_prefix
  destination_address_prefix  = var.db_subnet_prefix
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.db.name
}

resource "azurerm_network_security_rule" "db_deny_all_inbound" {
  name                        = "Deny-All-Inbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.db.name
}

resource "azurerm_network_security_rule" "db_deny_all_outbound" {
  name                        = "Deny-All-Outbound"
  priority                    = 4096
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.db.name
}

resource "azurerm_network_security_rule" "web_allow_app_outbound" {
  name                        = "Allow-Web-To-App-Outbound"
  priority                    = 100
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8443"
  source_address_prefix       = var.web_subnet_prefix
  destination_address_prefix  = var.app_subnet_prefix
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.web.name
}

resource "azurerm_network_security_rule" "web_deny_all_outbound" {
  name                        = "Deny-All-Outbound"
  priority                    = 4096
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.web.name
}

resource "azurerm_network_security_rule" "test_insecure_ssh" {
  name                        = "TEST-Allow-SSH-From-Internet"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = var.web_subnet_prefix
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.web.name
}
