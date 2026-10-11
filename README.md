# Azure Networking Foundation

![terraform-ci](https://github.com/jericmicc/azure-networking-foundation/actions/workflows/terraform-ci.yml/badge.svg)

A reference implementation of a segmented Azure network, built with Terraform in small, documented steps. **Work in progress.** Each piece is deployed, verified, documented and then destroyed to keep costs at zero.

## Status

| Area | State |
|---|---|
| Resource group, virtual network, tags, naming convention | Done |
| Web subnet (no default outbound access) and web NSG with deny-by-default inbound | Done |
| CI: format check, init and validate on every push | Done |
| App and database subnets with NSGs | Planned |
| Routing and outbound design | Planned |
| Private endpoint and private DNS | Planned |
| Monitoring and VNet flow logs | Planned |
| Remote state, security scanning, plan on pull requests | Planned |
| Terraform modules and hub-and-spoke topology | Planned |

## Documentation

- [IP address plan](docs/ip-address-plan.md): subnet ranges and the reasoning behind them
- [NSG rules](docs/nsg-rules.md): every rule, its priority and why it exists
- [Evidence](docs/evidence/): command output captured before each teardown

## Design principles

- Deny by default, with each exception documented
- No credentials or subscription IDs in code: authentication uses the Azure CLI login
- Pinned Terraform and provider versions, with the lock file committed
- Names follow the Microsoft Cloud Adoption Framework pattern: type, workload, environment, region, instance
- Plan before apply, destroy after every session

## Run it yourself

Requires Terraform, the Azure CLI and an Azure subscription. The resources used so far are free.

    az login
    export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    cd infra
    terraform init
    terraform plan
    terraform apply
    terraform destroy

## Known simplifications

- Terraform state is stored locally. Remote state in Azure Storage is on the roadmap.
- The NSG rules have not yet been tested with live traffic.
- A single flat VNet is a starting point, not an enterprise landing zone.
