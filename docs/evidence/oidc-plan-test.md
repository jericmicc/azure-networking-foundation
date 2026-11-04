# Terraform plan on pull requests with OIDC

Dates: 2026-11-02 (plan job, pull request #24) and 2026-11-04 (negative test, pull request #25)

Purpose: run `terraform plan` on every pull request from this repository without storing any Azure password or key, and show that the identity used cannot change anything.

## How it works

- GitHub gives the `plan` job a short-lived OIDC token. The job asks for it with `permissions: id-token: write`, which only this job has.
- In Microsoft Entra ID there is an app registration, `github-oidc-netfound-plan`, with a federated credential. It trusts tokens from GitHub's token service whose subject is a pull request of this repository. The app has no client secret and no certificate.
- Terraform logs in by itself (`ARM_USE_OIDC=true`), both for the provider and for the remote state backend. The tenant, client and subscription IDs are repository secrets, so GitHub masks them in the public logs.
- The identity has two roles and nothing else: Reader on the subscription, and Storage Blob Data Reader on the `tfstate` container only. The plan therefore runs with `-lock=false`, because taking the lock would need write access to the state blob.
- The job runs only for pull requests from branches of this repository. It is skipped for fork pull requests and for Dependabot, which do not receive the secrets. A skipped job counts as passed for required checks.

## Result of the plan job (pull request #24)

- First run: failed in `terraform init` with AADSTS700213, "No matching federated identity record found for presented assertion subject". GitHub now puts the numeric owner and repository IDs into the subject (`repo:OWNER@ID/REPO@ID:pull_request`), and the credential had the plain `repo:OWNER/REPO:pull_request` form. The credential subject was updated and the job re-run.
- Second run: passed in 26 seconds. `terraform init` ended with "Terraform has been successfully initialized!" and `terraform plan` ended with `Plan: 26 to add, 0 to change, 0 to destroy.` That is the same count as the local plan with every switch off.
- After the merge, the run on `main` showed the `plan` job as skipped, as designed, because it only runs for the `pull_request` event.

## Result of the negative test (pull request #25, never merged)

A throwaway job logged in with the same identity and tried three things:

- Control, count the blobs in the state container: printed `1` (the state file). The identity can read what the plan needs.
- Upload a blob into the state container: refused. Matched phrase in Azure's error: "required permissions".
- Create a resource group: refused with an authorization error.

The job passed in 19 seconds and so did the other four checks. The first run of the negative job failed only because its check did not recognise Azure's wording for the refused write (nothing was written). The check was changed to print the phrase that matched, and the second run passed. The pull request was closed without merging and its branch deleted. The error text of the write attempts was kept out of the log on purpose.

## Limits

- Two write attempts were tested (a blob upload and a resource group). Deleting a blob, taking a lease or other writes were not tried. The role definitions of Reader and Storage Blob Data Reader are what rule them out.
- The plan covers the default configuration (26 resources). It does not plan the code behind the optional switches.
- The behaviour for fork pull requests and for Dependabot pull requests was not tested. It rests on GitHub's documented behaviour: secrets are not passed to workflows triggered by a pull request from a fork.
- The federated credential accepts any pull request of this repository, including one that edits the workflow. The two read-only roles are the real limit of what such a pull request can do.
- The plan logs are public. The IDs are masked, but a plan can print resource names and settings.
- `plan` was not a required status check when this was written.
