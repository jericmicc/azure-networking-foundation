# Unit tests for the policy switch. Mock provider: no Azure login, no cost.
# They check what the code says. That Azure really refuses the changes is shown by the live test in docs/evidence.

mock_provider "azurerm" {}

run "policy_off_creates_nothing" {
  command = plan

  assert {
    condition = alltrue([
      length(azurerm_policy_definition.deny_mgmt_ports_from_internet) == 0,
      length(azurerm_policy_set_definition.guardrails) == 0,
      length(azurerm_resource_group_policy_assignment.guardrails) == 0,
    ])
    error_message = "With deploy_policy off, no policy resource may be planned."
  }
}

run "policy_on_bundles_five_rules_and_enforces" {
  command = plan

  variables {
    deploy_policy = true
  }

  assert {
    condition     = length(azurerm_policy_set_definition.guardrails[0].policy_definition_reference) == 5
    error_message = "The initiative must bundle exactly five rules."
  }

  assert {
    condition     = azurerm_resource_group_policy_assignment.guardrails[0].enforce == true
    error_message = "By default the assignment must enforce (block), not only report."
  }

  assert {
    condition     = jsondecode(azurerm_policy_definition.deny_mgmt_ports_from_internet[0].policy_rule).then.effect == "deny"
    error_message = "The custom management port rule must deny."
  }

  assert {
    condition     = contains(jsondecode(azurerm_resource_group_policy_assignment.guardrails[0].parameters).allowedLocations.value, "global")
    error_message = "The allowed locations must include global, or the private DNS zone would be blocked."
  }
}

run "management_port_rule_checks_lists_and_wildcards" {
  command = plan

  variables {
    deploy_policy = true
  }

  # Found by a live test: a rule with ports 22 and 8080 keeps them in a list field, which the first version did not read.
  assert {
    condition     = strcontains(azurerm_policy_definition.deny_mgmt_ports_from_internet[0].policy_rule, "destinationPortRanges[*]")
    error_message = "The rule must also check the list field for ports."
  }

  assert {
    condition     = strcontains(azurerm_policy_definition.deny_mgmt_ports_from_internet[0].policy_rule, "sourceAddressPrefixes[*]")
    error_message = "The rule must also check the list field for sources."
  }

  assert {
    condition     = strcontains(azurerm_policy_definition.deny_mgmt_ports_from_internet[0].policy_rule, "[\"22\",\"3389\",\"*\"]")
    error_message = "The blocked ports must be 22, 3389 and the wildcard."
  }
}

run "report_only_mode" {
  command = plan

  variables {
    deploy_policy  = true
    policy_enforce = false
  }

  assert {
    condition     = azurerm_resource_group_policy_assignment.guardrails[0].enforce == false
    error_message = "policy_enforce = false must switch the assignment to report only (DoNotEnforce)."
  }
}

run "web_vm_has_no_public_ip_when_policy_is_on" {
  command = plan

  variables {
    deploy_policy          = true
    deploy_test_vms        = true
    test_vm_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINvzE3cJVmV6cyC8T44SFNEZeePmRZYwNkGKMzenTX77 unit-test-only-throwaway"
  }

  assert {
    condition     = length(azurerm_public_ip.web_test) == 0
    error_message = "With the policy on, the web test VM must not get a public IP."
  }

  assert {
    condition     = azurerm_network_interface.test["web"].ip_configuration[0].public_ip_address_id == null
    error_message = "The web NIC must have no public IP reference when the policy is on."
  }
}

run "web_vm_keeps_its_public_ip_when_policy_is_off" {
  command = plan

  variables {
    deploy_test_vms        = true
    test_vm_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINvzE3cJVmV6cyC8T44SFNEZeePmRZYwNkGKMzenTX77 unit-test-only-throwaway"
  }

  assert {
    condition     = length(azurerm_public_ip.web_test) == 1
    error_message = "Without the policy, the web test VM keeps its temporary public IP."
  }
}
