#!/usr/bin/env bash
# Creates the Azure Storage account that holds Terraform's remote state (see infra/backend.tf).
# Created outside Terraform on purpose: Terraform cannot store its state in something it has not built yet.
# Uses your az login only. No secrets and no subscription ID are stored in this file.
# Run step by step on 2026-10-14, then run as a whole on 2026-10-16 against the existing resources: it finished without error, so it can be re-run. Not yet tested on a fresh subscription.
set -euo pipefail

RG="rg-tfstate-dev-southeastasia-001"
LOCATION="southeastasia"
SA="sttfstatenetfound001"
CONTAINER="tfstate"
TAGS="project=azure-networking-foundation environment=dev managed_by=azure-cli purpose=terraform-state"

# 1. Resource group, separate from the project group so "terraform destroy" never touches the state.
az group create --name "$RG" --location "$LOCATION" --tags $TAGS -o none

# 2. Storage account: private, TLS 1.2, HTTPS only, no public blobs, no shared keys (Entra ID only).
az storage account create --name "$SA" --resource-group "$RG" --location "$LOCATION" --sku Standard_LRS --kind StorageV2 --access-tier Hot --min-tls-version TLS1_2 --https-only true --allow-blob-public-access false --allow-shared-key-access false --tags $TAGS -o none

# 3. Versioning and 7-day soft delete so a bad or deleted state file can be recovered.
az storage account blob-service-properties update --account-name "$SA" --resource-group "$RG" --enable-versioning true --enable-delete-retention true --delete-retention-days 7 -o none

# 4. Container, created through the management plane so it works while shared keys are disabled.
az storage container-rm create --storage-account "$SA" --resource-group "$RG" --name "$CONTAINER" -o none

# 5. Data-plane role for the signed-in user, scoped to this one container (least privilege).
CONTAINER_ID=$(az storage container-rm show --storage-account "$SA" --resource-group "$RG" --name "$CONTAINER" --query id -o tsv)
az role assignment create --assignee-object-id "$(az ad signed-in-user show --query id -o tsv)" --assignee-principal-type User --role "Storage Blob Data Contributor" --scope "$CONTAINER_ID" -o none

echo "Done. Next: cd infra && terraform init"
