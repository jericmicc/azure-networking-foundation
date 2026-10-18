# Azure Networking Foundation

[![terraform-ci](https://github.com/jericmicc/azure-networking-foundation/actions/workflows/terraform-ci.yml/badge.svg)](https://github.com/jericmicc/azure-networking-foundation/actions/workflows/terraform-ci.yml)

A reference implementation of a segmented Azure network, built with Terraform in small, documented steps. **Work in progress.** Each piece is deployed, verified, documented and then destroyed to keep costs at zero. In the status table, **Deployed** means deployed and checked during a session, then destroyed afterwards, so nothing is running now.

## Status

| Area | State |
|---|---|
| Resource group, virtual network, tags, naming convention | Done |
| Web subnet (no default outbound access) and web NSG with deny-by-default inbound | Done |
| CI: format check, init, validate, tflint with the Azure ruleset and a pinned Checkov security scan (blocking) on every push and pull request, with a [documented failing test](docs/evidence/ci-negative-test.md) | Done |
| App and database subnets with NSGs | Deployed (not yet tested with traffic) |
| Routing and outbound design | Planned |
| Private endpoint and private DNS | Planned |
| Monitoring and VNet flow logs | Planned |
| Branch protection on `main` (pull request and passing checks required) | Done |
| Remote state in Azure Storage with Entra ID auth and versioning ([details](docs/remote-state.md)) | Done |
| Terraform plan on pull requests | Planned |
| Terraform modules and hub-and-spoke topology | Planned |

## Documentation

- [IP address plan](docs/ip-address-plan.md): subnet ranges and the reasoning behind them
- [NSG rules](docs/nsg-rules.md): every rule, its priority and why it exists, based on the [traffic matrix](docs/traffic-matrix.md)
- [Evidence](docs/evidence/): command output captured before each teardown
- [Remote state](docs/remote-state.md): why state lives in Azure Storage, the bootstrap script, settings, cost and limits

## Design principles

- Deny by default, with each exception documented
- No credentials or subscription IDs in code: authentication uses the Azure CLI login
- Pinned Terraform and provider versions, with the lock file committed
- Names follow the Microsoft Cloud Adoption Framework pattern: type, workload, environment, region, instance
- Plan before apply, destroy after every session. Changes to `main` go through pull requests with required CI checks (format, validate, Checkov)

## Run it yourself

Requires Terraform, the Azure CLI and an Azure subscription. The resources used so far are free. State is stored remotely: `infra/backend.tf` points at a storage account that belongs to the repo owner, so to run this yourself first create your own with `bootstrap/create-state-storage.sh` (change the names in it) and pass your names to `terraform init` with `-backend-config`. See [remote state](docs/remote-state.md).

    az login
    export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    cd infra
    terraform init
    terraform plan
    terraform apply
    terraform destroy

## Known simplifications

- Terraform state is remote (Azure Storage, Entra ID auth, versioned), but in a locally redundant, single-region account with a public endpoint protected by authentication only. It lives in a free-trial subscription. See [remote state](docs/remote-state.md).
- The NSG rules have not yet been tested with live traffic.
- A single flat VNet is a starting point, not an enterprise landing zone.
- The web tier accepts HTTPS from the whole internet. A production design would put Application Gateway, Front Door or a firewall in front.
- Ports 8443 (web to app) and 1433 (app to database) are placeholders for a reference implementation.
- There is no outbound path to the internet yet. It will be added deliberately, with narrow rules, when a workload needs it.
