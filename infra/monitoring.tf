# Monitoring, behind a switch.
# Off by default (deploy_monitoring = false): nothing here is created and nothing is billed.

variable "deploy_monitoring" {
  description = "Create a VNet flow log with its storage account, a Log Analytics workspace and diagnostic settings on the NSGs. A short test costs a few cents. Destroy the same day."
  type        = bool
  default     = false
}

variable "flow_log_reader_ip" {
  description = "Optional public IP address that may read the flow log storage account. Supply it with TF_VAR_flow_log_reader_ip and never commit it."
  type        = string
  default     = ""
}

# Azure creates one Network Watcher per region, outside this project.
# It is only read here: Terraform must never create or destroy it.
data "azurerm_network_watcher" "main" {
  count               = var.deploy_monitoring ? 1 : 0
  name                = "NetworkWatcher_${var.location}"
  resource_group_name = "NetworkWatcherRG"
}

# The identity that runs Terraform. It gets read access to the flow logs below.
data "azurerm_client_config" "current" {}

resource "azurerm_storage_account" "flow_logs" {
  #checkov:skip=CKV_AZURE_33: No queue service is used, the account only holds flow log blobs.
  #checkov:skip=CKV_AZURE_59: Firewall default is Deny. Access is only through the trusted service bypass and one optional reader IP. Fully disabling public network access was not tested.
  #checkov:skip=CKV_AZURE_206: LRS is enough for disposable test logs that can be recreated.
  #checkov:skip=CKV2_AZURE_33: The Azure flow log service writes through the trusted service bypass, so no private endpoint is used.
  #checkov:skip=CKV2_AZURE_1: A customer managed key needs a Key Vault, which is billed. Microsoft managed keys are used.
  count                           = var.deploy_monitoring ? 1 : 0
  name                            = "stfl${var.workload}${var.instance}"
  location                        = azurerm_resource_group.main.location
  resource_group_name             = azurerm_resource_group.main.name
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  tags                            = local.tags

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices", "Logging", "Metrics"]
    ip_rules       = compact([var.flow_log_reader_ip])
  }

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }
}

resource "azurerm_role_assignment" "flow_logs_reader" {
  count                = var.deploy_monitoring ? 1 : 0
  scope                = azurerm_storage_account.flow_logs[0].id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_network_watcher_flow_log" "vnet" {
  count                = var.deploy_monitoring ? 1 : 0
  name                 = "fl-vnet-${local.name_suffix}"
  network_watcher_name = data.azurerm_network_watcher.main[0].name
  resource_group_name  = data.azurerm_network_watcher.main[0].resource_group_name
  target_resource_id   = azurerm_virtual_network.main.id
  storage_account_id   = azurerm_storage_account.flow_logs[0].id
  enabled              = true
  version              = 2
  tags                 = local.tags

  retention_policy {
    enabled = true
    days    = 90
  }
}

resource "azurerm_log_analytics_workspace" "main" {
  count               = var.deploy_monitoring ? 1 : 0
  name                = "log-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 0.1
  tags                = local.tags
}

# One diagnostic setting per NSG. The endpoint NSG exists only when deploy_private_endpoint is on.
# The keys come from the switches alone, because resource IDs are not known until apply.
locals {
  nsg_log_ids = {
    web = azurerm_network_security_group.web.id
    app = azurerm_network_security_group.app.id
    db  = azurerm_network_security_group.db.id
    pe  = one(azurerm_network_security_group.pe[*].id)
  }
  nsg_log_keys = concat(["web", "app", "db"], var.deploy_private_endpoint ? ["pe"] : [])
}

resource "azurerm_monitor_diagnostic_setting" "nsg" {
  for_each                   = var.deploy_monitoring ? toset(local.nsg_log_keys) : toset([])
  name                       = "diag-nsg-${each.key}"
  target_resource_id         = local.nsg_log_ids[each.key]
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "NetworkSecurityGroupEvent"
  }

  enabled_log {
    category = "NetworkSecurityGroupRuleCounter"
  }
}

output "flow_log_storage_account_name" {
  description = "Name of the flow log storage account, or null when the switch is off."
  value       = one(azurerm_storage_account.flow_logs[*].name)
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (a GUID) of the workspace, used to query it with the CLI, or null when the switch is off."
  value       = one(azurerm_log_analytics_workspace.main[*].workspace_id)
}
