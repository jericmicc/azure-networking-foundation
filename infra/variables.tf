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
