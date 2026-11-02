variable "name" {
  description = "Tier name (web, app or db). Used in the subnet and NSG names."
  type        = string
}

variable "name_suffix" {
  description = "Naming suffix shared by all resources, for example netfound-dev-southeastasia-001."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that holds the subnet and the NSG."
  type        = string
}

variable "virtual_network_name" {
  description = "Virtual network that holds the subnet."
  type        = string
}

variable "address_prefix" {
  description = "Address prefix of the subnet."
  type        = string
}

variable "tags" {
  description = "Tags for the NSG."
  type        = map(string)
}

variable "rules" {
  description = "NSG rules of this tier, keyed by rule name. Source port is always any. Everything not listed is allowed or denied by the built-in rules, so each tier lists its own deny-all rules."
  type = map(object({
    priority                   = number
    direction                  = string
    access                     = string
    protocol                   = optional(string, "*")
    destination_port_range     = optional(string, "*")
    source_address_prefix      = optional(string, "*")
    destination_address_prefix = optional(string, "*")
  }))
}
