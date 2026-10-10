variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "southeastasia"
}

variable "workload" {
  description = "Short workload name used in resource naming."
  type        = string
  default     = "netfound"
}

variable "environment" {
  description = "Environment name (dev, test, prod)."
  type        = string
  default     = "dev"
}

variable "vnet_address_space" {
  description = "Address space for the virtual network."
  type        = list(string)
  default     = ["10.10.0.0/20"]
}

variable "web_subnet_prefix" {
  description = "Address prefix for the web subnet. Must match docs/ip-address-plan.md."
  type        = string
  default     = "10.10.1.0/24"
}

variable "instance" {
  description = "Instance number used in resource names."
  type        = string
  default     = "001"
}
