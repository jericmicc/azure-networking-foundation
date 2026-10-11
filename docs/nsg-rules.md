# NSG Rules

## Web tier: `nsg-web-netfound-dev-southeastasia-001`

Attached to `snet-web` (`10.10.1.0/24`). Inbound policy is deny by default with two explicit exceptions.

| Priority | Name | Direction | Action | Source | Port | Why it exists |
|---|---|---|---|---|---|---|
| 100 | `Allow-HTTPS-Inbound` | Inbound | Allow | `Internet` | TCP 443 | The web tier serves HTTPS. Port 80 is deliberately not allowed |
| 4000 | `Allow-AzureLoadBalancer-Inbound` | Inbound | Allow | `AzureLoadBalancer` | Any | Keeps load balancer health probes working after the deny rule is added |
| 4096 | `Deny-All-Inbound` | Inbound | Deny | Any | Any | Replaces the built-in `AllowVnetInBound` (65000), which allows every port between subnets |

## Design notes

- Azure evaluates rules from the lowest priority number to the highest and stops at the first match. Custom rules can use 100 to 4096. Built-in defaults sit at 65000 and above and cannot be edited.
- Priorities are spaced out (100, 4000, 4096) so rules can be inserted later without renumbering.
- The deny rule at 4096 would also block the load balancer's health probes (the built-in allow for them sits at 65001), so an explicit allow at 4000 is required.
- Rules are defined as separate `azurerm_network_security_rule` resources. Mixing inline rules and separate rule resources in Terraform causes conflicts.
- The deny rule also blocks other subnets from calling the web tier. That is intentional. If a management path is needed (for example Azure Bastion), add a narrow allow rule above the deny, with a written reason.

## Known simplifications

- Allowing the whole internet on 443 is acceptable for a reference implementation. Production designs usually put Application Gateway, Front Door or a firewall in front, and allow only that service as the source.
- Outbound rules still use the built-in defaults. This is mostly moot because `snet-web` has default outbound access disabled, but outbound will be tightened when routing is designed.
- The rules have not yet been tested with live traffic, because the subnet has no workload.
