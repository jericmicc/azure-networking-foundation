# Traffic Matrix

Status: planned. This is written before any app or database resources exist, so the code can be checked against it.

## Tiers

| Tier | Subnet | CIDR | NSG | Status |
|---|---|---|---|---|
| Web | `snet-web` | `10.10.1.0/24` | `nsg-web-netfound-dev-southeastasia-001` | Deployed |
| App | `snet-app` | `10.10.2.0/24` | planned | Planned |
| Database | `snet-db` | `10.10.3.0/24` | planned | Planned |

## Allowed flows

Everything not listed here is denied.

| # | From | To | Port | Why |
|---|---|---|---|---|
| 1 | Internet | Web | TCP 443 | Users reach the web tier over HTTPS |
| 2 | Web | App | TCP 8443 | The web tier calls the application (placeholder port) |
| 3 | App | Database | TCP 1433 | The application reads and writes data (SQL Server, placeholder) |
| 4 | Azure Load Balancer | Web and App | Any | Health probes. Required once a load balancer fronts a tier |
| 5 | Azure Bastion | App and Database | TCP 22 and 3389 | Admin access, only when Bastion is added. Not part of the first build |

## Planned rules per NSG

Priorities are spaced out so rules can be inserted later. Custom rules can use 100 to 4096.

| Tier | Direction | Priority | Action | Source or destination | Port |
|---|---|---|---|---|---|
| Web | Inbound | 100 | Allow | Internet | TCP 443 |
| Web | Inbound | 4000 | Allow | AzureLoadBalancer | Any |
| Web | Inbound | 4096 | Deny | Any | Any |
| Web | Outbound | 100 | Allow | `10.10.2.0/24` | TCP 8443 |
| Web | Outbound | 4096 | Deny | Any | Any |
| App | Inbound | 100 | Allow | `10.10.1.0/24` | TCP 8443 |
| App | Inbound | 4000 | Allow | AzureLoadBalancer | Any |
| App | Inbound | 4096 | Deny | Any | Any |
| App | Outbound | 100 | Allow | `10.10.3.0/24` | TCP 1433 |
| App | Outbound | 4096 | Deny | Any | Any |
| Database | Inbound | 100 | Allow | `10.10.2.0/24` | TCP 1433 |
| Database | Inbound | 4096 | Deny | Any | Any |
| Database | Outbound | 4096 | Deny | Any | Any |

## Design notes

- The built-in rules at priority 65000 allow all traffic between subnets in both directions. Each tier therefore needs its own explicit deny at 4096, otherwise the web tier could reach the database directly.
- The web tier has no outbound rules deployed yet. They are added in this phase so all three tiers follow the same pattern.
- Denying all outbound traffic can break Azure platform traffic once virtual machines exist (agents, updates, monitoring). Service tag allows will be added when a workload is deployed.
- Ports are placeholders for a reference implementation.
- A managed database such as Azure SQL would normally use a private endpoint in `snet-pe` instead of a subnet of its own. `snet-db` assumes a database running on virtual machines or a SQL managed instance.
