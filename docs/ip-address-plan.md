# IP Address Plan

## Principles

- Subnets are sized deliberately and documented before deployment.
- Address space is reserved for future growth (bastion, private endpoints, additional tiers).
- Ranges avoid common home and corporate defaults (`192.168.0.0/16`, `10.0.0.0/16`) to keep future peering and VPN connectivity possible.

## Virtual network

| Name | Address space |
|---|---|
| `vnet-netfound-dev` | `10.10.0.0/20` |

## Subnets

| Subnet | CIDR | Usable IPs | Purpose | Status |
|---|---|---|---|---|
| `snet-web` | `10.10.1.0/24` | 251 | Internet-facing tier (load balancer, web servers) | Planned |
| `snet-app` | `10.10.2.0/24` | 251 | Application tier, no direct internet inbound | Planned |
| `snet-db` | `10.10.3.0/24` | 251 | Data tier, reachable only from the app tier | Planned |
| `snet-pe` | `10.10.4.0/24` | 251 | Private endpoints | Reserved |
| `AzureBastionSubnet` | `10.10.5.0/26` | 59 | Azure Bastion (name is mandatory, minimum size /26) | Reserved |

Unallocated: `10.10.0.0/24`, `10.10.5.64` to `10.10.5.255`, and `10.10.6.0` to `10.10.15.255`.

## Notes

- Azure reserves 5 addresses in every subnet (network address, default gateway, two for Azure DNS, and broadcast), so a /24 gives 251 usable addresses, not 256.
- Subnet ranges are sized for a reference implementation. In a real organization the VNet range would be allocated from a central IP address management (IPAM) plan.
- Subnets are numbered so the third octet matches the tier order (web = 1, app = 2, db = 3, private endpoints = 4, bastion = 5). `10.10.0.0/24` is intentionally left unused to keep that numbering readable.
