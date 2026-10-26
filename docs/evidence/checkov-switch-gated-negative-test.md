# Checkov CI negative test: code behind a disabled switch

Date: 2026-10-26

Purpose: prove that the CI security scan now covers resources behind the switches `deploy_test_vms` and `deploy_nat_gateway`, which it did not scan before pull request #14.

What was done: on a throwaway branch, one deliberately insecure resource was added in its own file, `infra/negative-test.tf`: an inbound NSG rule on the app NSG that allows SSH (TCP 22) from any source, with `count = var.deploy_nat_gateway ? 1 : 0`. The file was correctly formatted and valid Terraform, so only the security scan should object. A pull request was opened (#15). It was never merged and never deployed. The branch was deleted afterwards.

Local result before the push, same code:

- Scan with the default variable values (how CI worked before pull request #14): 77 passed, 0 failed, 1 skipped. The insecure rule was not seen, because the switch is off by default and the resource has no instances.
- Scan with `infra/checkov.tfvars` (how CI works now): 99 passed, 1 failed, 3 skipped.

Result in CI:

- validate job: passed (the code was valid and correctly formatted)
- tflint job: passed
- security-scan job: FAILED after 36 seconds, exit code 1
- Check: CKV_AZURE_10, "Ensure that SSH access is restricted from the internet"
- Resource: `azurerm_network_security_rule.negative_test_ssh[0]`, file `negative-test.tf`, lines 2 to 15
- security-scan is a required status check, and GitHub disabled the Merge button

Conclusion: an insecure resource behind a disabled switch is now caught by CI and blocked from reaching main. Before pull request #14 the same code would have passed. Pull request #15 remains viewable on GitHub as a closed pull request with the red check.

Limits: one check on one resource type was tested. The var file covers the optional code that exists today. A new switch added later must also be set to true in `infra/checkov.tfvars`, or its resources will be unscanned again.
