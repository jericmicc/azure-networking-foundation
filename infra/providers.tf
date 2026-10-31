provider "azurerm" {
  features {
    # The test storage account has shared keys off and public access off, so the provider cannot use its data plane.
    storage {
      data_plane_available = false
    }
    # Delete the workspace for good on destroy. By default Azure only soft-deletes it for 14 days.
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
  # Subscription is supplied via the ARM_SUBSCRIPTION_ID environment variable.
  # Authentication uses your Azure CLI login. No credentials live in this repo.
}
