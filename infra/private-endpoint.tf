# Private endpoint for blob storage, behind a switch.
# Off by default (deploy_private_endpoint = false): nothing here is created and nothing is billed.

variable "deploy_private_endpoint" {
  description = "Create the private endpoint subnet, a test storage account, a private endpoint and a private DNS zone. Billed by the hour. Destroy the same day."
  type        = bool
  default     = false
}

variable "pe_subnet_prefix" {
  description = "Address prefix for the private endpoint subnet. Must match docs/ip-address-plan.md."
  type        = string
  default     = "10.10.4.0/24"
}

resource "azurerm_subnet" "pe" {
  count                             = var.deploy_private_endpoint ? 1 : 0
  name                              = "snet-pe"
  resource_group_name               = azurerm_resource_group.main.name
  virtual_network_name              = azurerm_virtual_network.main.name
  address_prefixes                  = [var.pe_subnet_prefix]
  default_outbound_access_enabled   = false
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_network_security_group" "pe" {
  count               = var.deploy_private_endpoint ? 1 : 0
  name                = "nsg-pe-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "pe" {
  count                     = var.deploy_private_endpoint ? 1 : 0
  subnet_id                 = azurerm_subnet.pe[0].id
  network_security_group_id = azurerm_network_security_group.pe[0].id
}

resource "azurerm_network_security_rule" "pe_allow_app_inbound" {
  count                       = var.deploy_private_endpoint ? 1 : 0
  name                        = "Allow-App-To-PE-Inbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.app_subnet_prefix
  destination_address_prefix  = var.pe_subnet_prefix
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.pe[0].name
}

resource "azurerm_network_security_rule" "pe_deny_all_inbound" {
  count                       = var.deploy_private_endpoint ? 1 : 0
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
  network_security_group_name = azurerm_network_security_group.pe[0].name
}

resource "azurerm_network_security_rule" "pe_deny_all_outbound" {
  count                       = var.deploy_private_endpoint ? 1 : 0
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
  network_security_group_name = azurerm_network_security_group.pe[0].name
}

resource "azurerm_network_security_rule" "app_allow_pe_outbound" {
  count                       = var.deploy_private_endpoint ? 1 : 0
  name                        = "Allow-App-To-PE-Outbound"
  priority                    = 120
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.app_subnet_prefix
  destination_address_prefix  = var.pe_subnet_prefix
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.app.name
}

resource "azurerm_storage_account" "pe_test" {
  #checkov:skip=CKV_AZURE_33: No queue service is used. Queue logging needs data-plane access, which this private-only account blocks from Terraform.
  #checkov:skip=CKV2_AZURE_1: Test account that holds no data. A customer-managed key needs a Key Vault, which is billed and out of scope for this test.
  #checkov:skip=CKV_AZURE_206: Throwaway test account that exists for about an hour and holds no data. Geo-redundant replication would add cost and protect nothing.
  count                           = var.deploy_private_endpoint ? 1 : 0
  name                            = "stpe${var.workload}${var.instance}"
  location                        = azurerm_resource_group.main.location
  resource_group_name             = azurerm_resource_group.main.name
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  public_network_access_enabled   = false
  tags                            = local.tags

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }
}

resource "azurerm_private_dns_zone" "blob" {
  count               = var.deploy_private_endpoint ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  count                 = var.deploy_private_endpoint ? 1 : 0
  name                  = "link-${azurerm_virtual_network.main.name}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.blob[0].name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_private_endpoint" "blob" {
  count               = var.deploy_private_endpoint ? 1 : 0
  name                = "pe-blob-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.pe[0].id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-blob-${local.name_suffix}"
    private_connection_resource_id = azurerm_storage_account.pe_test[0].id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob[0].id]
  }
}

output "private_endpoint_ip" {
  description = "Private IP of the blob private endpoint, or null when the switch is off."
  value       = one(azurerm_private_endpoint.blob[*].private_service_connection[0].private_ip_address)
}

output "pe_test_blob_host" {
  description = "Blob host name of the test storage account, or null when the switch is off."
  value       = one(azurerm_storage_account.pe_test[*].primary_blob_host)
}
