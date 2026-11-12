# Azure Policy guardrails

File: `infra/policy.tf`. Switch: `deploy_policy` (default `false`). Policy itself has no charge.

## Why this exists

NSG rules, tests and CI protect the network that Terraform builds. They do not stop a person from changing the network by hand in the portal or the CLI afterwards. Azure Policy does: it sits in Azure Resource Manager, so a request that breaks a rule is refused whoever sends it, including a user with the Owner role.

## The vocabulary

| Term | Meaning here |
|---|---|
| Definition | One rule: an `if` condition and an effect |
| Effect | What happens on a match: `Deny` refuses the request, `Audit` only reports it |
| Initiative (policy set) | A bundle of definitions, assigned as one unit |
| Assignment | Applies a definition or initiative to a scope. Here the scope is the project resource group only |
| Enforcement mode | `Default` blocks. `DoNotEnforce` evaluates and reports but blocks nothing. Set with `policy_enforce` |
| Compliance | The report of which existing resources break which rule. It is computed after the fact and lags behind changes |

## The five guardrails

| Guardrail | Source | Stops |
|---|---|---|
| Network interfaces should not have public IPs | Built-in | A NIC with a public IP attached |
| Subnets should be private | Built-in | A subnet with default outbound access left on |
| No management ports open to the internet | Custom (in `policy.tf`) | An inbound Allow rule for port 22, 3389 or `*` from `*`, `Internet` or `0.0.0.0/0`, also when the port or source is given in a list |
| Storage accounts should disable public network access | Built-in | A storage account reachable from the public network |
| Allowed locations | Built-in | Resources outside the two project regions, plus `global` (needed by the private DNS zone) |

The built-in definitions are looked up by their fixed ID, so nothing is copied. The custom one exists because no built-in rule covers a rule that opens the management ports to a wildcard source from a list field.

## Rollout in two modes

1. `terraform apply -var deploy_policy=true -var policy_enforce=false` assigns the initiative in report only mode. Read the compliance report and see what would break.
2. `terraform apply -var deploy_policy=true` turns enforcement on.

Both modes were tested live. See the [policy test](evidence/policy-test.md).

## Interaction with the test VMs

The web test VM used a public IP for the live traffic test. With `deploy_policy = true` that public IP is not created, because the NIC rule would refuse it. The code decides this in `test-vms.tf`, and a unit test covers both cases.

## Limits

- A port range such as `20-30` that contains 22 is not caught by the custom rule. Only exact values (`22`, `3389`, `*`) are matched.
- Scope is one resource group. Nothing outside it is affected, and the guardrails do not protect other resource groups.
- A new assignment or a changed mode takes minutes to apply, and the compliance report lags further behind. Do not test right after an apply.
- Policy governs the Azure control plane (creating and changing resources). It does not filter traffic. The NSGs do that.
- A policy refusal looks different from a subscription restriction. See [troubleshooting](troubleshooting.md).
