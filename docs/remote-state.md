# Remote state

Terraform records what it built in a state file. This project keeps that file in Azure Storage, not on a laptop and not in Git.

## Why not Git
State can contain subscription IDs and, depending on the resources, secrets. It must never be committed. `*.tfstate` is gitignored.

## Why a separate bootstrap
Terraform cannot keep its state in a storage account it has not built yet. The state storage is therefore created once with the Azure CLI (`bootstrap/create-state-storage.sh`), in its own resource group that normal project destroys never touch.

| Item | Value |
|---|---|
| Resource group | `rg-tfstate-dev-southeastasia-001` |
| Storage account | `sttfstatenetfound001` |
| Container | `tfstate` |
| State blob | `azure-networking-foundation/dev.tfstate` |

## Settings and why
- Shared key access disabled: no long-lived keys exist. Terraform authenticates with Entra ID (`use_azuread_auth = true`).
- Public blob access off, HTTPS only, TLS 1.2 minimum.
- Blob versioning on and 7-day soft delete: a bad or deleted state can be recovered.
- Access is the data-plane role `Storage Blob Data Contributor`, scoped to the container only. Being Owner of the subscription does not grant blob data access.
- State locking uses blob leases. A lock is taken during plan and apply and released afterwards.

## Using it
Sign in and select the subscription, then initialise:

    az login
    export ARM_SUBSCRIPTION_ID="<your subscription id>"
    cd infra && terraform init

No tenant or subscription ID is stored in the repo. CI runs `terraform init -backend=false`, so it needs no Azure credentials and never touches the state.

To use your own storage instead, run `terraform init -backend-config="storage_account_name=<yours>"` (add `resource_group_name` and `container_name` the same way if they differ).

## Cost
Observed in Azure Cost Management for October 2026: under $0.01 (storage), bandwidth $0.00. Cost data can lag by up to a day.

## Known limitations
- Locally redundant storage (LRS), a single region. Acceptable for a lab, not for production.
- The storage account has a public endpoint protected by authentication only, with no private endpoint or IP restriction yet.
- No delete lock on the state resource group yet.
- It lives in a free-trial subscription that expires around 9 Nov 2026. After that the state is gone unless it is moved. Recreate with the bootstrap script.

## Tear down
Only after `terraform destroy` of the project, and only when the state is no longer needed:

    az group delete --name rg-tfstate-dev-southeastasia-001 --yes

The bootstrap script was run step by step on 2026-10-14 and as a whole on 2026-10-16 against the existing resources without error. It has not yet been tested on a fresh subscription.
