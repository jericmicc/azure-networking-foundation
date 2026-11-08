# Hub-and-spoke, behind a switch.
# The existing VNet (vnet-netfound-...) is spoke 1. A new hub VNet holds a shared subnet, and a second spoke VNet holds a workload subnet.
# Each spoke is peered with the hub only. Peering is not transitive, so the two spokes have no path to each other.
# Spoke 2 sits in a second region (spoke2_location), so its peering with the hub is a global VNet peering. The reason is the
# Total Regional vCPUs quota of 4 per region on this subscription: the test VMs do not all fit into one region.
# Off by default (deploy_hub_spoke = false). VNets, subnets, NSGs and peerings cost nothing to hold. Only data that crosses a peering is billed.

variable "deploy_hub_spoke" {
  description = "Create the hub VNet, the second spoke VNet and the four peerings. Free to hold. Destroy after tests."
  type        = bool
  default     = false
}

variable "hub_vnet_address_space" {
  description = "Address space of the hub VNet. Must match docs/ip-address-plan.md and not overlap the spokes."
  type        = list(string)
  default     = ["10.20.0.0/22"]
}

variable "hub_shared_subnet_prefix" {
  description = "Address prefix of the shared services subnet in the hub. Must match docs/ip-address-plan.md."
  type        = string
  default     = "10.20.0.0/24"
}

variable "spoke2_location" {
  description = "Azure region of the second spoke. It must offer Standard_DC1ds_v3 to this subscription (checked: japaneast, australiaeast, centralindia)."
  type        = string
  default     = "japaneast"
}

locals {
  # The naming convention puts the region in every name, so spoke 2 resources use its own region.
  spoke2_name_suffix = "${var.workload}-${var.environment}-${var.spoke2_location}-${var.instance}"
}

variable "spoke2_vnet_address_space" {
  description = "Address space of the second spoke VNet. Must match docs/ip-address-plan.md and not overlap the hub or spoke 1."
  type        = list(string)
  default     = ["10.30.0.0/20"]
}

variable "spoke2_workload_subnet_prefix" {
  description = "Address prefix of the workload subnet in the second spoke. Must match docs/ip-address-plan.md."
  type        = string
  default     = "10.30.1.0/24"
}

resource "azurerm_virtual_network" "hub" {
  count               = var.deploy_hub_spoke ? 1 : 0
  name                = "vnet-hub-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.hub_vnet_address_space
  tags                = local.tags
}

resource "azurerm_virtual_network" "spoke2" {
  count               = var.deploy_hub_spoke ? 1 : 0
  name                = "vnet-spoke2-${local.spoke2_name_suffix}"
  location            = var.spoke2_location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.spoke2_vnet_address_space
  tags                = local.tags
}

# Shared services subnet in the hub. It may call the app tier of spoke 1 on 8443 and accepts 443 from the workload subnet of spoke 2.
module "hub_shared" {
  count                = var.deploy_hub_spoke ? 1 : 0
  source               = "./modules/tier"
  name                 = "hub-shared"
  name_suffix          = local.name_suffix
  location             = azurerm_resource_group.main.location
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub[0].name
  address_prefix       = var.hub_shared_subnet_prefix
  tags                 = local.tags

  rules = {
    "Allow-Spoke2-To-Shared-Inbound" = {
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      destination_port_range     = "443"
      source_address_prefix      = var.spoke2_workload_subnet_prefix
      destination_address_prefix = var.hub_shared_subnet_prefix
    }
    "Deny-All-Inbound" = {
      priority  = 4096
      direction = "Inbound"
      access    = "Deny"
    }
    "Allow-Shared-To-App-Outbound" = {
      priority                   = 100
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      destination_port_range     = "8443"
      source_address_prefix      = var.hub_shared_subnet_prefix
      destination_address_prefix = var.app_subnet_prefix
    }
    "Deny-All-Outbound" = {
      priority  = 4096
      direction = "Outbound"
      access    = "Deny"
    }
  }
}

# Workload subnet in spoke 2. It may call the shared subnet in the hub on 443 and nothing else.
module "spoke2_workload" {
  count                = var.deploy_hub_spoke ? 1 : 0
  source               = "./modules/tier"
  name                 = "spoke2-workload"
  name_suffix          = local.spoke2_name_suffix
  location             = var.spoke2_location
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.spoke2[0].name
  address_prefix       = var.spoke2_workload_subnet_prefix
  tags                 = local.tags

  rules = {
    "Deny-All-Inbound" = {
      priority  = 4096
      direction = "Inbound"
      access    = "Deny"
    }
    "Allow-Workload-To-Shared-Outbound" = {
      priority                   = 100
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      destination_port_range     = "443"
      source_address_prefix      = var.spoke2_workload_subnet_prefix
      destination_address_prefix = var.hub_shared_subnet_prefix
    }
    "Deny-All-Outbound" = {
      priority  = 4096
      direction = "Outbound"
      access    = "Deny"
    }
  }
}

# The app tier of spoke 1 accepts 8443 from the hub shared subnet. It is a separate rule resource so the module call of the app tier stays unchanged.
resource "azurerm_network_security_rule" "app_from_hub_shared" {
  count                       = var.deploy_hub_spoke ? 1 : 0
  name                        = "Allow-Hub-Shared-To-App-Inbound"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8443"
  source_address_prefix       = var.hub_shared_subnet_prefix
  destination_address_prefix  = var.app_subnet_prefix
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = module.app.nsg_name
}

# The four peering resources are chained with depends_on because Azure serializes changes in one VNet.
# Forwarded traffic, gateway transit and remote gateways stay off: there is no firewall and no gateway in this design.
resource "azurerm_virtual_network_peering" "spoke1_to_hub" {
  count                        = var.deploy_hub_spoke ? 1 : 0
  name                         = "peer-spoke1-to-hub"
  resource_group_name          = azurerm_resource_group.main.name
  virtual_network_name         = azurerm_virtual_network.main.name
  remote_virtual_network_id    = azurerm_virtual_network.hub[0].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false

  depends_on = [module.web, module.app, module.db, module.hub_shared]
}

resource "azurerm_virtual_network_peering" "hub_to_spoke1" {
  count                        = var.deploy_hub_spoke ? 1 : 0
  name                         = "peer-hub-to-spoke1"
  resource_group_name          = azurerm_resource_group.main.name
  virtual_network_name         = azurerm_virtual_network.hub[0].name
  remote_virtual_network_id    = azurerm_virtual_network.main.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false

  depends_on = [azurerm_virtual_network_peering.spoke1_to_hub]
}

resource "azurerm_virtual_network_peering" "spoke2_to_hub" {
  count                        = var.deploy_hub_spoke ? 1 : 0
  name                         = "peer-spoke2-to-hub"
  resource_group_name          = azurerm_resource_group.main.name
  virtual_network_name         = azurerm_virtual_network.spoke2[0].name
  remote_virtual_network_id    = azurerm_virtual_network.hub[0].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false

  depends_on = [module.spoke2_workload, azurerm_virtual_network_peering.hub_to_spoke1]
}

resource "azurerm_virtual_network_peering" "hub_to_spoke2" {
  count                        = var.deploy_hub_spoke ? 1 : 0
  name                         = "peer-hub-to-spoke2"
  resource_group_name          = azurerm_resource_group.main.name
  virtual_network_name         = azurerm_virtual_network.hub[0].name
  remote_virtual_network_id    = azurerm_virtual_network.spoke2[0].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false

  depends_on = [azurerm_virtual_network_peering.spoke2_to_hub]
}
