# IP Address Plan

## Principles

- Subnets are sized deliberately and documented before deployment.
- Address space is reserved for future growth (bastion, private endpoints, additional tiers).
- Ranges avoid common home and corporate defaults (`192.168.0.0/16`, `10.0.0.0/16`) to keep future peering and VPN connectivity possible.

## Virtual network

| Name | Address space |
|---|---|
| `vnet-netfound-dev-southeastasia-001` | `10.10.0.0/20` |

## Subnets

| Subnet | CIDR | Usable IPs | Purpose | Status |
|---|---|---|---|---|
| `snet-web` | `10.10.1.0/24` | 251 | Internet-facing tier (load balancer, web servers) | Deployed |
| `snet-app` | `10.10.2.0/24` | 251 | Application tier, no direct internet inbound | Deployed |
| `snet-db` | `10.10.3.0/24` | 251 | Data tier, reachable only from the app tier | Deployed |
| `snet-pe` | `10.10.4.0/24` | 251 | Private endpoints. Created only when `deploy_private_endpoint` is on | Tested live, optional |
| `AzureBastionSubnet` | `10.10.5.0/26` | 59 | Azure Bastion (name is mandatory, minimum size /26) | Reserved |

Unallocated: `10.10.0.0/24`, `10.10.5.64` to `10.10.5.255`, and `10.10.6.0` to `10.10.15.255`.

## Notes

- Azure reserves 5 addresses in every subnet (network address, default gateway, two for Azure DNS, and broadcast), so a /24 gives 251 usable addresses, not 256.
- Subnet ranges are sized for a reference implementation. In a real organization the VNet range would be allocated from a central IP address management (IPAM) plan.
- Subnets are numbered so the third octet matches the tier order (web = 1, app = 2, db = 3, private endpoints = 4, bastion = 5). `10.10.0.0/24` is intentionally left unused to keep that numbering readable.
- `snet-pe` has private endpoint network policies enabled, so its NSG applies to the endpoint. In the test, the private endpoint received `10.10.4.4`, the first usable address after the five that Azure reserves.

## Hub and spoke (optional, `deploy_hub_spoke`)

Spoke 1 is the virtual network above. The ranges below do not overlap with it or with each other, which is required for peering.

| Name | Region | Address space | Subnet | Subnet CIDR | Status |
|---|---|---|---|---|---|
| `vnet-hub-netfound-dev-southeastasia-001` | southeastasia | `10.20.0.0/22` | `snet-hub-shared` | `10.20.0.0/24` | Tested live, optional |
| `vnet-spoke2-netfound-dev-japaneast-001` | japaneast | `10.30.0.0/20` | `snet-spoke2-workload` | `10.30.1.0/24` | Tested live, optional |

- The hub range is a /22, which leaves room for more hub subnets later (for example a firewall subnet, which needs at least a /26). None of them are created or reserved in code.
- Spoke 2 follows the same numbering pattern as spoke 1 (third octet 1 for the first workload subnet).
- Spoke 2 is in japaneast because the subscription has a limit of 4 vCPUs per region, which five test VMs in one region would exceed. See `docs/troubleshooting.md`.
