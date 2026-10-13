# CI negative test

Date: 2026-10-13

Purpose: prove the CI security gate can fail, not only pass.

What was done: on a throwaway branch, one deliberately insecure rule was added: an inbound NSG rule allowing SSH (TCP 22) from any source to the web subnet. A pull request was opened (#1). It was never merged and never deployed. The branch was deleted afterwards.

Result:

- validate job: passed (code was valid and correctly formatted)
- security-scan job: FAILED, exit code 1
- Check: CKV_AZURE_10, Ensure that SSH access is restricted from the internet
- Failed for resource: azurerm_network_security_rule.test_insecure_ssh

Conclusion: the pinned Checkov scan blocks an insecure NSG rule before it can reach main. Pull request #1 remains viewable on GitHub as a closed pull request with the red check.
