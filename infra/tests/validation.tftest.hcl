# Bad input must be rejected before anything is planned. Mock provider: no Azure login, no cost.

mock_provider "azurerm" {}

run "unknown_test_vm_tier_is_rejected" {
  command = plan

  variables {
    test_vm_tier_names = ["web", "bogus"]
  }

  expect_failures = [var.test_vm_tier_names]
}

run "hub_test_vm_needs_the_hub_switch" {
  command = plan

  variables {
    deploy_test_vms        = true
    test_vm_tier_names     = ["hub"]
    test_vm_ssh_public_key = "ssh-ed25519 AAAAFAKEKEYFORTESTSONLY"
  }

  expect_failures = [var.test_vm_tier_names]
}

run "test_vms_need_an_ssh_key" {
  command = plan

  variables {
    deploy_test_vms = true
  }

  expect_failures = [var.test_vm_ssh_public_key]
}
