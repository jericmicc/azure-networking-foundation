output "subnet_id" {
  description = "ID of the subnet."
  value       = azurerm_subnet.this.id
}

output "nsg_id" {
  description = "ID of the NSG."
  value       = azurerm_network_security_group.this.id
}

output "nsg_name" {
  description = "Name of the NSG, for rules added from outside the module."
  value       = azurerm_network_security_group.this.name
}

output "rules" {
  description = "The NSG rules of this tier as applied, keyed by rule name. Used by the tests to check the security rules."
  value = {
    for name, rule in azurerm_network_security_rule.this : name => {
      priority                   = rule.priority
      direction                  = rule.direction
      access                     = rule.access
      protocol                   = rule.protocol
      destination_port_range     = rule.destination_port_range
      source_address_prefix      = rule.source_address_prefix
      destination_address_prefix = rule.destination_address_prefix
    }
  }
}

output "default_outbound_access_enabled" {
  description = "Whether the subnet has Azure's default outbound access. It must be false."
  value       = azurerm_subnet.this.default_outbound_access_enabled
}
