# TEST ONLY. Never merge. An insecure rule inside switch-gated code, to prove that CI scans it.
resource "azurerm_network_security_rule" "negative_test_ssh" {
  count                       = var.deploy_nat_gateway ? 1 : 0
  name                        = "TEST-Allow-SSH-From-Internet"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.app.name
}
