locals {
  name_suffix = "${var.workload}-${var.environment}"

  tags = {
    project     = "azure-networking-foundation"
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_suffix}"
  location = var.location
  tags     = local.tags
}
