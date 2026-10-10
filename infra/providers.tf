provider "azurerm" {
  features {}
  # Subscription is supplied via the ARM_SUBSCRIPTION_ID environment variable.
  # Authentication uses your Azure CLI login. No credentials live in this repo.
}
