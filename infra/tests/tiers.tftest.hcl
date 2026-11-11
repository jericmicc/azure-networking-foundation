# Unit tests for the three tiers. They run against a mock provider: no Azure login, no cost.
# They check the shape of the code (plan only), not the behaviour of Azure. The live tests in docs/evidence cover that.

mock_provider "azurerm" {}

run "every_tier_has_deny_all_rules" {
  command = plan

  assert {
    condition = alltrue([
      for tier in [module.web.rules, module.app.rules, module.db.rules] :
      tier["Deny-All-Inbound"].access == "Deny" && tier["Deny-All-Inbound"].direction == "Inbound" && tier["Deny-All-Inbound"].priority == 4096
    ])
    error_message = "Every tier must have Deny-All-Inbound at priority 4096."
  }

  assert {
    condition = alltrue([
      for tier in [module.web.rules, module.app.rules, module.db.rules] :
      tier["Deny-All-Outbound"].access == "Deny" && tier["Deny-All-Outbound"].direction == "Outbound" && tier["Deny-All-Outbound"].priority == 4096
    ])
    error_message = "Every tier must have Deny-All-Outbound at priority 4096."
  }
}

run "allow_rules_win_over_the_deny_rules" {
  command = plan

  assert {
    condition = alltrue([
      for tier in [module.web.rules, module.app.rules, module.db.rules] :
      alltrue([for name, rule in tier : rule.access == "Deny" || rule.priority < 4096 || name == "Allow-AzureLoadBalancer-Inbound"])
    ])
    error_message = "An allow rule must have a lower number than the deny-all rules (4096), or it never wins. Only the load balancer probe rule at 4000 is expected to sit just below."
  }
}

run "only_web_443_is_open_to_the_internet" {
  command = plan

  assert {
    condition = alltrue([
      for name, rule in module.web.rules :
      !(rule.direction == "Inbound" && rule.access == "Allow" && contains(["Internet", "*", "0.0.0.0/0"], rule.source_address_prefix)) || rule.destination_port_range == "443"
    ])
    error_message = "The web tier may accept the internet on port 443 only."
  }

  assert {
    condition = alltrue([
      for tier in [module.app.rules, module.db.rules] :
      alltrue([
        for name, rule in tier :
        !(rule.direction == "Inbound" && rule.access == "Allow" && contains(["Internet", "*", "0.0.0.0/0"], rule.source_address_prefix))
      ])
    ])
    error_message = "The app and db tiers must never accept traffic from the internet or from any source."
  }
}

run "tiers_only_talk_to_the_next_tier" {
  command = plan

  assert {
    condition     = module.web.rules["Allow-Web-To-App-Outbound"].destination_port_range == "8443" && module.app.rules["Allow-Web-To-App-Inbound"].destination_port_range == "8443"
    error_message = "Web to app must be TCP 8443 on both NSGs."
  }

  assert {
    condition     = module.app.rules["Allow-App-To-DB-Outbound"].destination_port_range == "1433" && module.db.rules["Allow-App-To-DB-Inbound"].destination_port_range == "1433"
    error_message = "App to db must be TCP 1433 on both NSGs."
  }

  assert {
    condition     = length([for name, rule in module.db.rules : name if rule.direction == "Outbound" && rule.access == "Allow"]) == 0
    error_message = "The db tier must have no outbound allow rule."
  }
}

run "subnets_have_no_default_outbound_access" {
  command = plan

  assert {
    condition     = module.web.default_outbound_access_enabled == false && module.app.default_outbound_access_enabled == false && module.db.default_outbound_access_enabled == false
    error_message = "Every tier subnet must have default outbound access turned off."
  }
}

run "db_default_route_goes_nowhere" {
  command = plan

  assert {
    condition     = length(azurerm_route_table.db.route) == 1 && alltrue([for r in azurerm_route_table.db.route : r.address_prefix == "0.0.0.0/0" && r.next_hop_type == "None"])
    error_message = "The db route table must have one default route with next hop None."
  }
}
