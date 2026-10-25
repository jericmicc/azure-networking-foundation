# Live traffic test: three small Linux VMs, one per tier.
# Off by default (deploy_test_vms = false) so a normal apply or CI run creates nothing billed.

variable "deploy_test_vms" {
  description = "Create the three test VMs and the web public IP. Billed. Destroy the same day."
  type        = bool
  default     = false
}

variable "test_vm_size" {
  description = "VM size for the test VMs. B-series is not available to this subscription in southeastasia."
  type        = string
  default     = "Standard_DC1ds_v3"
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
  test_vm_tiers = var.deploy_test_vms ? toset(["web", "app", "db"]) : toset([])

  tier_subnet_ids = {
    web = azurerm_subnet.web.id
    app = azurerm_subnet.app.id
    db  = azurerm_subnet.db.id
  }
}

resource "azurerm_public_ip" "web_test" {
  count               = var.deploy_test_vms ? 1 : 0
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
  name                = "nic-${each.key}-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = local.tier_subnet_ids[each.key]
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = each.key == "web" ? azurerm_public_ip.web_test[0].id : null
  }
}

resource "azurerm_linux_virtual_machine" "test" {
  for_each                        = local.test_vm_tiers
  name                            = "vm-${each.key}-${local.name_suffix}"
  location                        = azurerm_resource_group.main.location
  resource_group_name             = azurerm_resource_group.main.name
  size                            = var.test_vm_size
  admin_username                  = "azureadmin"
  disable_password_authentication = true
  allow_extension_operations      = false
  network_interface_ids           = [azurerm_network_interface.test[each.key].id]
  tags                            = local.tags

  custom_data = base64encode(templatefile("${path.module}/test-vms-cloud-init.tftpl", {
    tier   = each.key
    web_ip = azurerm_network_interface.test["web"].private_ip_address
    app_ip = azurerm_network_interface.test["app"].private_ip_address
    db_ip  = azurerm_network_interface.test["db"].private_ip_address
    nat    = var.deploy_nat_gateway
    nat_ip = try(azurerm_public_ip.nat_app[0].ip_address, "none")
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
