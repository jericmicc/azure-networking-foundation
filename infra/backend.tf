terraform {
  backend "azurerm" {
    storage_account_name = "sttfstatenetfound001"
    container_name       = "tfstate"
    key                  = "azure-networking-foundation/dev.tfstate"
    use_azuread_auth     = true
  }
}
