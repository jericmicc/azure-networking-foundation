# NSG Rules

Every tier follows the same pattern: allow only the flows in [traffic-matrix.md](traffic-matrix.md), deny everything else in both directions.

Rule status:
- **Deployed and checked**: deployed to Azure and listed with `az network nsg rule list` (see `docs/evidence/`).
- **In code, not yet deployed**: present in Terraform and passing CI, but never deployed or tested with traffic.
- **Tested live, optional**: created only when a switch such as `deploy_nat_gateway` is on. Deployed and tested with live traffic, see `docs/evidence/outbound-nat-test.md`.

## Web tier: `nsg-web-netfound-dev-southeastasia-001`

Attached to `snet-web` (`10.10.1.0/24`).

| Dir | Priority | Name | Action | Peer | Port | Status | Why it exists |
|---|---|---|---|---|---|---|---|
| In | 100 | `Allow-HTTPS-Inbound` | Allow | `Internet` | TCP 443 | Deployed and checked | The web tier serves HTTPS. Port 80 is deliberately not allowed |
| In | 4000 | `Allow-AzureLoadBalancer-Inbound` | Allow | `AzureLoadBalancer` | Any | Deployed and checked | Keeps load balancer health probes working after the deny rule |
| In | 4096 | `Deny-All-Inbound` | Deny | Any | Any | Deployed and checked | Replaces the built-in `AllowVnetInBound` (65000), which allows every port between subnets |
| Out | 100 | `Allow-Web-To-App-Outbound` | Allow | `10.10.2.0/24` | TCP 8443 | Deployed and checked | The web tier may call the application tier |
| Out | 4096 | `Deny-All-Outbound` | Deny | Any | Any | Deployed and checked | Overrides the built-in `AllowInternetOutBound` (65001) |

## App tier: `nsg-app-netfound-dev-southeastasia-001`

Attached to `snet-app` (`10.10.2.0/24`).

| Dir | Priority | Name | Action | Peer | Port | Status | Why it exists |
|---|---|---|---|---|---|---|---|
| In | 100 | `Allow-Web-To-App-Inbound` | Allow | `10.10.1.0/24` | TCP 8443 | Deployed and checked | Only the web tier may call the application |
| In | 4000 | `Allow-AzureLoadBalancer-Inbound` | Allow | `AzureLoadBalancer` | Any | Deployed and checked | Health probes, needed if a load balancer fronts this tier |
| In | 4096 | `Deny-All-Inbound` | Deny | Any | Any | Deployed and checked | Closes the built-in allow-all between subnets |
| Out | 100 | `Allow-App-To-DB-Outbound` | Allow | `10.10.3.0/24` | TCP 1433 | Deployed and checked | The application may only reach the database tier |
| Out | 110 | `Allow-App-To-Internet-Outbound` | Allow | `Internet` | TCP 443 | Tested live, optional | Lets the application reach the internet through the NAT Gateway. Exists only when `deploy_nat_gateway` is on. Filters by port, not domain |
| Out | 4096 | `Deny-All-Outbound` | Deny | Any | Any | Deployed and checked | A compromised application cannot send data out |

## Database tier: `nsg-db-netfound-dev-southeastasia-001`

Attached to `snet-db` (`10.10.3.0/24`).

| Dir | Priority | Name | Action | Peer | Port | Status | Why it exists |
|---|---|---|---|---|---|---|---|
| In | 100 | `Allow-App-To-DB-Inbound` | Allow | `10.10.2.0/24` | TCP 1433 | Deployed and checked | Only the application tier may query the database |
| In | 4096 | `Deny-All-Inbound` | Deny | Any | Any | Deployed and checked | Blocks the web tier and everything else |
| Out | 4096 | `Deny-All-Outbound` | Deny | Any | Any | Deployed and checked | The database has no path out |

## Design notes

- Azure evaluates rules from the lowest priority number to the highest and stops at the first match. Custom rules can use 100 to 4096. Built-in defaults sit at 65000 and above and cannot be edited.
- Priorities are spaced out (100, 4000, 4096) so rules can be inserted later without renumbering.
- The built-in rules allow all traffic between subnets and all outbound internet traffic. Explicit denies at 4096 are what make each tier deny by default.
- A deny at 4096 would also block load balancer health probes (the built-in allow sits at 65001), so web and app tiers have an explicit allow at 4000. The database tier has none because nothing load balances it.
- Rule names only need to be unique within one NSG, so the same name is reused across tiers.
- Rules are separate `azurerm_network_security_rule` resources. Mixing inline rules and separate rule resources in Terraform causes conflicts.
- NSGs are stateful, so replies to an allowed connection are let through without extra rules.

## Known simplifications

- Allowing the whole internet on 443 is acceptable for a reference implementation. Production designs usually put Application Gateway, Front Door or a firewall in front, and allow only that service as the source.
- By default no outbound path to the internet exists. With `deploy_nat_gateway = true`, the app tier can reach the internet on TCP 443 through a NAT Gateway (rule `Allow-App-To-Internet-Outbound`). This filters by port, not by domain, so any host on port 443 is reachable. Domain filtering needs a firewall.
- Denying all outbound traffic could break Azure platform traffic once virtual machines exist (for example DNS and the VM agent, which use Azure's platform address 168.63.129.16). The VM agent reported Ready on all three test VMs with the deny rules in place. DNS was not tested.
- Ports 8443 and 1433 are placeholders.
- The rules were tested with live traffic on 22 October 2026, and again with the outbound design on 25 October 2026 (see `docs/evidence/`). Each test was one full run, TCP only. UDP and ICMP were not tested.
