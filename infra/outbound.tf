# Outbound design for the app tier, behind a switch.
# Off by default (deploy_nat_gateway = false): the app tier keeps no path out, as proven on 22 October.

variable "deploy_nat_gateway" {
  description = "Create a NAT Gateway for the app subnet and the narrow NSG rule that lets it use it. Billed. Destroy the same day."
  type        = bool
  default     = false
}

resource "azurerm_public_ip" "nat_app" {
  count               = var.deploy_nat_gateway ? 1 : 0
  name                = "pip-natgw-app-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "app" {
  count                   = var.deploy_nat_gateway ? 1 : 0
  name                    = "ng-app-${local.name_suffix}"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 4
  tags                    = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "app" {
  count                = var.deploy_nat_gateway ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.app[0].id
  public_ip_address_id = azurerm_public_ip.nat_app[0].id
}

resource "azurerm_subnet_nat_gateway_association" "app" {
  count          = var.deploy_nat_gateway ? 1 : 0
  subnet_id      = azurerm_subnet.app.id
  nat_gateway_id = azurerm_nat_gateway.app[0].id
}

resource "azurerm_network_security_rule" "app_allow_internet_outbound" {
  count                       = var.deploy_nat_gateway ? 1 : 0
  name                        = "Allow-App-To-Internet-Outbound"
  priority                    = 110
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.app_subnet_prefix
  destination_address_prefix  = "Internet"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.app.name
}

resource "azurerm_route_table" "db" {
  name                          = "rt-db-${local.name_suffix}"
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  bgp_route_propagation_enabled = false
  tags                          = local.tags

  route {
    name           = "Default-To-None"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "None"
  }
}

resource "azurerm_subnet_route_table_association" "db" {
  subnet_id      = azurerm_subnet.db.id
  route_table_id = azurerm_route_table.db.id
}

output "nat_app_public_ip" {
  description = "Public IP of the app tier NAT Gateway, or null when the switch is off."
  value       = one(azurerm_public_ip.nat_app[*].ip_address)
}
