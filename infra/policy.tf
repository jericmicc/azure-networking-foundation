# Azure Policy guardrails: Azure itself refuses unsafe changes, even ones made by hand in the portal.
# Off by default (deploy_policy = false). Policy costs nothing.
# Scope: the project resource group only. The state resource group and the rest of the subscription are not touched.

variable "deploy_policy" {
  description = "Assign the guardrail initiative to the project resource group."
  type        = bool
  default     = false
}

variable "policy_enforce" {
  description = "true = Azure blocks changes that break a rule (Deny). false = report only (DoNotEnforce): compliance is evaluated, nothing is blocked."
  type        = bool
  default     = true
}

locals {
  # "global" is needed because some resources, such as the private DNS zone, have the location global.
  policy_allowed_locations = [var.location, var.spoke2_location, "global"]
}

# Built-in definitions, looked up by their fixed ID. The display name is in the comment.
data "azurerm_policy_definition_built_in" "nic_no_public_ip" {
  count = var.deploy_policy ? 1 : 0
  name  = "83a86a26-fd1f-447c-b59d-e51f44264114" # Network interfaces should not have public IPs (effect is fixed to deny)
}

data "azurerm_policy_definition_built_in" "subnets_private" {
  count = var.deploy_policy ? 1 : 0
  name  = "7bca8353-aa3b-429b-904a-9229c4385837" # Subnets should be private (default outbound access off)
}

data "azurerm_policy_definition_built_in" "storage_no_public" {
  count = var.deploy_policy ? 1 : 0
  name  = "b2982f36-99f2-4db5-8eff-283140c09693" # Storage accounts should disable public network access
}

data "azurerm_policy_definition_built_in" "allowed_locations" {
  count = var.deploy_policy ? 1 : 0
  name  = "e56962a6-4747-49cd-b67b-bf8b01975c4c" # Allowed locations
}

# No built-in policy denies management ports, so this one is custom.
# It denies an inbound Allow rule that opens SSH, RDP or every port to the internet.
# A rule keeps its ports and sources either in a single field or in a list field, so both are checked.
# Limit: a port range such as "20-30" that happens to include 22 is not caught.
locals {
  nsg_rule_field        = "Microsoft.Network/networkSecurityGroups/securityRules"
  policy_blocked_ports  = ["22", "3389", "*"]
  policy_internet_hosts = ["*", "Internet", "0.0.0.0/0"]
}

resource "azurerm_policy_definition" "deny_mgmt_ports_from_internet" {
  count        = var.deploy_policy ? 1 : 0
  name         = "deny-mgmt-ports-${local.name_suffix}"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Deny SSH and RDP rules open to the internet"
  description  = "Denies an inbound Allow NSG rule for port 22, port 3389 or every port from the internet or from any source."

  policy_rule = jsonencode({
    if = {
      allOf = [
        { field = "type", equals = local.nsg_rule_field },
        { field = "${local.nsg_rule_field}/access", equals = "Allow" },
        { field = "${local.nsg_rule_field}/direction", equals = "Inbound" },
        {
          anyOf = [
            { field = "${local.nsg_rule_field}/destinationPortRange", in = local.policy_blocked_ports },
            {
              count = {
                field = "${local.nsg_rule_field}/destinationPortRanges[*]"
                where = { field = "${local.nsg_rule_field}/destinationPortRanges[*]", in = local.policy_blocked_ports }
              }
              greater = 0
            },
          ]
        },
        {
          anyOf = [
            { field = "${local.nsg_rule_field}/sourceAddressPrefix", in = local.policy_internet_hosts },
            {
              count = {
                field = "${local.nsg_rule_field}/sourceAddressPrefixes[*]"
                where = { field = "${local.nsg_rule_field}/sourceAddressPrefixes[*]", in = local.policy_internet_hosts }
              }
              greater = 0
            },
          ]
        },
      ]
    }
    then = { effect = "deny" }
  })
}

# The initiative bundles the five rules so that they are assigned as one unit.
resource "azurerm_policy_set_definition" "guardrails" {
  count        = var.deploy_policy ? 1 : 0
  name         = "guardrails-${local.name_suffix}"
  policy_type  = "Custom"
  display_name = "Network foundation guardrails"
  description  = "No public IPs on network interfaces, private subnets, no open management ports, no public storage, approved regions only."

  parameters = jsonencode({
    allowedLocations = {
      type     = "Array"
      metadata = { displayName = "Allowed locations" }
    }
  })

  policy_definition_reference {
    policy_definition_id = data.azurerm_policy_definition_built_in.nic_no_public_ip[0].id
    reference_id         = "nic-no-public-ip"
  }

  policy_definition_reference {
    policy_definition_id = data.azurerm_policy_definition_built_in.subnets_private[0].id
    reference_id         = "subnets-private"
    parameter_values     = jsonencode({ effect = { value = "Deny" } })
  }

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.deny_mgmt_ports_from_internet[0].id
    reference_id         = "no-open-management-ports"
  }

  policy_definition_reference {
    policy_definition_id = data.azurerm_policy_definition_built_in.storage_no_public[0].id
    reference_id         = "storage-no-public-access"
    parameter_values     = jsonencode({ effect = { value = "Deny" } })
  }

  policy_definition_reference {
    policy_definition_id = data.azurerm_policy_definition_built_in.allowed_locations[0].id
    reference_id         = "allowed-locations"
    parameter_values = jsonencode({
      effect                 = { value = "Deny" }
      listOfAllowedLocations = { value = "[parameters('allowedLocations')]" }
    })
  }
}

resource "azurerm_resource_group_policy_assignment" "guardrails" {
  count                = var.deploy_policy ? 1 : 0
  name                 = "guardrails-${local.name_suffix}"
  display_name         = "Network foundation guardrails"
  resource_group_id    = azurerm_resource_group.main.id
  policy_definition_id = azurerm_policy_set_definition.guardrails[0].id
  enforce              = var.policy_enforce

  parameters = jsonencode({
    allowedLocations = { value = local.policy_allowed_locations }
  })
}

output "policy_assignment_name" {
  description = "Name of the policy assignment, or null when the policy switch is off. Use it to query compliance."
  value       = one(azurerm_resource_group_policy_assignment.guardrails[*].name)
}
