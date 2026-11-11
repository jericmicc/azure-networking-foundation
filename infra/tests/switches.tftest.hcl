# Unit tests for the optional switches. Each switch must create nothing when off and only its own parts when on.
# Mock provider: no Azure login, no cost.

mock_provider "azurerm" {}

run "all_switches_off_creates_no_optional_resources" {
  command = plan

  assert {
    condition = alltrue([
      length(azurerm_nat_gateway.app) == 0,
      length(azurerm_public_ip.nat_app) == 0,
      length(azurerm_subnet.pe) == 0,
      length(azurerm_private_endpoint.blob) == 0,
      length(azurerm_storage_account.pe_test) == 0,
      length(azurerm_storage_account.flow_logs) == 0,
      length(azurerm_log_analytics_workspace.main) == 0,
      length(azurerm_virtual_network.hub) == 0,
      length(azurerm_virtual_network.spoke2) == 0,
      length(azurerm_virtual_network_peering.spoke1_to_hub) == 0,
      length(azurerm_public_ip.web_test) == 0,
      length(azurerm_linux_virtual_machine.test) == 0,
    ])
    error_message = "With every switch off, no optional resource may be planned."
  }
}

run "nat_gateway_switch" {
  command = plan

  variables {
    deploy_nat_gateway = true
  }

  assert {
    condition     = length(azurerm_nat_gateway.app) == 1 && length(azurerm_public_ip.nat_app) == 1
    error_message = "The NAT switch must create one NAT gateway and one public IP."
  }

  assert {
    condition     = azurerm_network_security_rule.app_allow_internet_outbound[0].destination_port_range == "443" && azurerm_network_security_rule.app_allow_internet_outbound[0].destination_address_prefix == "Internet"
    error_message = "The NAT rule must allow TCP 443 to the internet and nothing wider."
  }
}

run "private_endpoint_switch" {
  command = plan

  variables {
    deploy_private_endpoint = true
  }

  assert {
    condition     = length(azurerm_private_endpoint.blob) == 1 && length(azurerm_private_dns_zone.blob) == 1
    error_message = "The private endpoint switch must create one endpoint and one private DNS zone."
  }

  assert {
    condition     = azurerm_storage_account.pe_test[0].public_network_access_enabled == false && azurerm_storage_account.pe_test[0].shared_access_key_enabled == false
    error_message = "The test storage account must have public access and shared keys off."
  }
}

run "monitoring_switch" {
  command = plan

  variables {
    deploy_monitoring = true
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.nsg) == 3
    error_message = "Monitoring must send logs for the three tier NSGs."
  }

  assert {
    condition     = azurerm_storage_account.flow_logs[0].shared_access_key_enabled == false && azurerm_storage_account.flow_logs[0].allow_nested_items_to_be_public == false
    error_message = "The flow log storage account must have shared keys and public blobs off."
  }
}

run "monitoring_and_private_endpoint_cover_the_endpoint_nsg" {
  command = plan

  variables {
    deploy_monitoring       = true
    deploy_private_endpoint = true
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.nsg) == 4
    error_message = "With the private endpoint on, monitoring must also cover its NSG (four in total)."
  }
}

run "hub_spoke_switch" {
  command = plan

  variables {
    deploy_hub_spoke = true
  }

  assert {
    condition = alltrue([
      length(azurerm_virtual_network_peering.spoke1_to_hub) == 1,
      length(azurerm_virtual_network_peering.hub_to_spoke1) == 1,
      length(azurerm_virtual_network_peering.spoke2_to_hub) == 1,
      length(azurerm_virtual_network_peering.hub_to_spoke2) == 1,
    ])
    error_message = "Hub and spoke must create exactly the four peerings, always paired with the hub."
  }

  assert {
    condition = alltrue([
      for p in [
        azurerm_virtual_network_peering.spoke1_to_hub[0],
        azurerm_virtual_network_peering.hub_to_spoke1[0],
        azurerm_virtual_network_peering.spoke2_to_hub[0],
        azurerm_virtual_network_peering.hub_to_spoke2[0],
      ] : p.allow_forwarded_traffic == false && p.allow_gateway_transit == false && p.use_remote_gateways == false
    ])
    error_message = "Peerings must not forward traffic or use gateways: there is no firewall or gateway in this design."
  }

  assert {
    condition = alltrue([
      for tier in [module.hub_shared[0].rules, module.spoke2_workload[0].rules] :
      tier["Deny-All-Inbound"].priority == 4096 && tier["Deny-All-Outbound"].priority == 4096
    ])
    error_message = "The hub and spoke 2 tiers must also have deny-all rules."
  }
}
