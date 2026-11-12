# Azure Policy: live test

Date: 2026-11-12. The network plus the three policy resources were applied, tested by hand with the Azure CLI, then destroyed. Subscription ID, public IPs and GUIDs are left out on purpose. Error text is summarised to its error code and policy name.

## Setup

- `deploy_policy = true`: 29 resources planned (26 network, 3 policy: custom definition, initiative, assignment).
- Scope: the project resource group. Enforcement mode `Default`.
- Unit tests before the live run: 21 passed (15 earlier plus 6 for policy).

## Enforced mode: bad changes are refused

| Attempt | Result |
|---|---|
| Inbound Allow, TCP, from `Internet`, port `22` on the web NSG | Refused, `RequestDisallowedByPolicy`, custom management port rule |
| The same with port `3389` | Refused, same rule |
| Storage account with public network access enabled | Refused, `RequestDisallowedByPolicy`, storage rule |
| VNet in `eastus` | Refused, `RequestDisallowedByPolicy`, allowed locations |
| NIC with a public IP | Refused, NIC rule |
| Subnet with default outbound access on | Refused, subnet rule |
| Inbound Allow, TCP, from `Internet`, port `443` | Allowed, as intended |
| A new harmless NSG | Allowed |

A first attempt with `westeurope` was inconclusive: the error code was `RequestDisallowedByAzure`, which is a restriction of the subscription or region, not a policy refusal. The test was repeated with `eastus`.

## A gap found by testing, and its fix

A rule that sent the port as a list (`22` and `8080` together) and the source as a list was allowed. The first version of the custom rule only looked at the single-value fields. The rule now also checks `destinationPortRanges[*]` and `sourceAddressPrefixes[*]` with `count` and `where`, and treats `*` as a blocked port. The fix was applied (1 changed) and the same attempts were refused. A unit test now checks that the rule text covers both list fields and the three blocked values.

## Compliance

After the fix and a scan (`az policy state trigger-scan`, then `az policy state summarize`): 0 non-compliant resources, 21 compliant. Some rules had nothing to report because the resource group has no resource of that type (no NIC, no storage account).

## Report only mode

| Step | Result |
|---|---|
| `terraform apply -var deploy_policy=true -var policy_enforce=false` | 1 changed. The apply took 1m47s |
| `az policy assignment show` | `enforcementMode: DoNotEnforce` |
| The port 22 rule from `Internet` created on the web NSG | `provisioningState: Succeeded`, not blocked |
| `trigger-scan`, then `summarize` | 1 non-compliant resource, 1 non-compliant policy |
| The test rule deleted | No `Test*` rule left |
| `terraform apply -var deploy_policy=true` | 1 changed. `enforce = false -> true`, 1m46s |

So report only mode reports without blocking, and switching it back restores enforcement.

## Teardown

`terraform destroy -var deploy_policy=true`, then three checks: `az group exists` printed `false`, and the lists of custom policy definitions and initiatives with `netfound` in the name were both empty.

## What this does not prove

- Only the rules above were tried. Other resource types were not tested.
- Ranges such as `20-30` that contain port 22 are not caught.
- A test on an existing violation was done once, in one resource group, in one subscription.
