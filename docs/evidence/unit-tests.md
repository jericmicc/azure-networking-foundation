# Unit tests and their failing test

Date: 2026-11-11. Tool: `terraform test` (Terraform 1.16.5), mock provider `azurerm`, no Azure login, no cost.

## What is tested

15 tests in `infra/tests/`, all against a plan with a mock provider. They check the shape of the code, not the behaviour of Azure. The live tests in this folder cover Azure's behaviour.

| File | Tests | Claims checked |
|---|---|---|
| `tiers.tftest.hcl` | 6 | every tier has Deny-All-Inbound and Deny-All-Outbound at 4096; allow rules win over the deny rules; only the web tier accepts the internet, and only on 443; web to app is 8443 and app to db is 1433 on both NSGs; the db tier has no outbound allow; all tier subnets have default outbound access off; the db default route has next hop None |
| `switches.tftest.hcl` | 6 | with every switch off no optional resource is planned; each switch creates only its own resources; the NAT rule is 443 to the internet only; the test storage accounts have shared keys and public access off; monitoring covers three NSGs, or four with the private endpoint; hub and spoke creates four peerings without forwarding or gateways |
| `validation.tftest.hcl` | 3 | an unknown test VM tier is rejected; a hub VM without the hub switch is rejected; test VMs without an SSH key are rejected |

The tests read the applied rules through two outputs of `modules/tier` (`rules` and `default_outbound_access_enabled`), because a test cannot look inside a module.

## Result on a correct configuration

```
Success! 15 passed, 0 failed.
```

## Failing test (negative test)

To prove the tests can fail, the source of the app tier rule `Allow-Web-To-App-Inbound` in `infra/main.tf` was changed from the web subnet to `"Internet"` on purpose. Result:

```
run "only_web_443_is_open_to_the_internet"... fail
  Error: Test assertion failed
  on tests/tiers.tftest.hcl line 50, in run "only_web_443_is_open_to_the_internet"
  The app and db tiers must never accept traffic from the internet or from any source.
Failure! 14 passed, 1 failed.
```

The failure output printed the rules of the app tier, and `Allow-Web-To-App-Inbound` showed `"source_address_prefix": "Internet"`. The change was then undone with `git checkout -- infra/main.tf` and the run was green again (15 passed, 0 failed). The broken line was never committed.

## What this does not prove

- A mock plan checks what the code says, not what Azure does. Live traffic tests, Checkov and the read-only plan on pull requests cover that.
- Values that Azure computes (IDs, IP addresses) are random placeholders in a mock, so tests assert only on values written in the code.
- The tests run in CI as the job `unit-tests`.
