# Live traffic test: three small Linux VMs, one per tier.
# Off by default (deploy_test_vms = false) so a normal apply or CI run creates nothing billed.

variable "deploy_test_vms" {
  description = "Create the test VMs chosen in test_vm_tier_names (default web, app, db) and the web public IP (not created when deploy_policy is on, because the policy denies public IPs on network interfaces). Billed. Destroy the same day."
  type        = bool
  default     = false
}

variable "test_vm_size" {
  description = "VM size for the test VMs. B-series is not available to this subscription in southeastasia."
  type        = string
  default     = "Standard_DC1ds_v3"
}

variable "test_vm_tier_names" {
  description = "Which test VMs to create. Every VM uses 1 vCPU and this subscription has a Total Regional vCPUs quota of 4 in southeastasia. The hub and spoke2 VMs need deploy_hub_spoke = true."
  type        = list(string)
  default     = ["web", "app", "db"]

  validation {
    condition     = alltrue([for t in var.test_vm_tier_names : contains(["web", "app", "db", "hub", "spoke2"], t)])
    error_message = "Allowed test VM names are web, app, db, hub and spoke2."
  }

  validation {
    condition     = var.deploy_hub_spoke || !anytrue([for t in var.test_vm_tier_names : contains(["hub", "spoke2"], t)])
    error_message = "The hub and spoke2 test VMs need deploy_hub_spoke = true."
  }
}

variable "test_vm_ssh_public_key" {
  description = "SSH public key for the VM admin user. Supplied through TF_VAR_test_vm_ssh_public_key. Never committed."
  type        = string
  default     = "set-via-TF_VAR_test_vm_ssh_public_key"

  validation {
    condition     = !var.deploy_test_vms || startswith(var.test_vm_ssh_public_key, "ssh-")
    error_message = "Set the SSH key via TF_VAR_test_vm_ssh_public_key."
  }
}

locals {
  test_vm_tiers = var.deploy_test_vms ? toset(var.test_vm_tier_names) : toset([])

  # The spoke2 VM lives in the second region, so its NIC and VM use that region and its name suffix.
  test_vm_location = { for t in local.test_vm_tiers : t => t == "spoke2" ? var.spoke2_location : azurerm_resource_group.main.location }
  test_vm_suffix   = { for t in local.test_vm_tiers : t => t == "spoke2" ? local.spoke2_name_suffix : local.name_suffix }

  tier_subnet_ids = {
    web    = module.web.subnet_id
    app    = module.app.subnet_id
    db     = module.db.subnet_id
    hub    = try(module.hub_shared[0].subnet_id, "none")
    spoke2 = try(module.spoke2_workload[0].subnet_id, "none")
  }
}

resource "azurerm_public_ip" "web_test" {
  count               = var.deploy_test_vms && contains(var.test_vm_tier_names, "web") && !var.deploy_policy ? 1 : 0
  name                = "pip-web-test-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_network_interface" "test" {
  #checkov:skip=CKV_AZURE_119: Deliberate public IP on the web test VM, temporary.
  for_each            = local.test_vm_tiers
  name                = "nic-${each.key}-${local.test_vm_suffix[each.key]}"
  location            = local.test_vm_location[each.key]
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = local.tier_subnet_ids[each.key]
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = each.key == "web" ? one(azurerm_public_ip.web_test[*].id) : null
  }
}

resource "azurerm_linux_virtual_machine" "test" {
  for_each                        = local.test_vm_tiers
  name                            = "vm-${each.key}-${local.test_vm_suffix[each.key]}"
  location                        = local.test_vm_location[each.key]
  resource_group_name             = azurerm_resource_group.main.name
  size                            = var.test_vm_size
  admin_username                  = "azureadmin"
  disable_password_authentication = true
  allow_extension_operations      = false
  network_interface_ids           = [azurerm_network_interface.test[each.key].id]
  tags                            = local.tags

  custom_data = base64encode(templatefile("${path.module}/test-vms-cloud-init.tftpl", {
    tier   = each.key
    web_ip = try(azurerm_network_interface.test["web"].private_ip_address, "none")
    app_ip = try(azurerm_network_interface.test["app"].private_ip_address, "none")
    db_ip  = try(azurerm_network_interface.test["db"].private_ip_address, "none")
    hub_ip = try(azurerm_network_interface.test["hub"].private_ip_address, "none")
    nat    = var.deploy_nat_gateway
    nat_ip = try(azurerm_public_ip.nat_app[0].ip_address, "none")
    pe     = var.deploy_private_endpoint
    pe_ip  = try(azurerm_private_endpoint.blob[0].private_service_connection[0].private_ip_address, "none")
    pe_dns = try(azurerm_storage_account.pe_test[0].primary_blob_host, "none")
  }))

  admin_ssh_key {
    username   = "azureadmin"
    public_key = var.test_vm_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  boot_diagnostics {}
}

output "test_vm_private_ips" {
  description = "Private IP of each test VM, keyed by tier."
  value       = { for tier, nic in azurerm_network_interface.test : tier => nic.private_ip_address }
}

output "test_web_public_ip" {
  description = "Public IP of the web test VM, or null when the VMs are off."
  value       = one(azurerm_public_ip.web_test[*].ip_address)
}
