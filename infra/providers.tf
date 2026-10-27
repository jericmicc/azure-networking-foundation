provider "azurerm" {
  features {
    # The test storage account has shared keys off and public access off, so the provider cannot use its data plane.
    storage {
      data_plane_available = false
    }
  }
  # Subscription is supplied via the ARM_SUBSCRIPTION_ID environment variable.
  # Authentication uses your Azure CLI login. No credentials live in this repo.
}
