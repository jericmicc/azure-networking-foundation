# Troubleshooting

Problems met while building this project, with what was seen and what fixed it. Where a cause was never found, the entry says so.

## Terraform and Azure

### 409 AnotherOperationInProgress on subnets, route table or NSG associations

- Seen: three times (two destroys and one apply) while changing a subnet, the route table association or an NSG association.
- Fix: read the plan or destroy summary, then run the same command again with the same `-var` switches. Terraform continues where it stopped. The second run finished the job every time.
- Not known: the cause. It was not investigated. Ideas not tried: `depends_on` between the subnet resources, or `terraform apply -parallelism=1`.

### A storage account with shared keys off

- Seen: the test storage accounts have shared key access off, and Terraform cannot reach the data plane of such an account.
- Fix: `data_plane_available = false` in the `storage` block under `features` in `infra/providers.tf`. Terraform then uses the management API only.

### A deleted Log Analytics workspace

- Azure soft-deletes a workspace for 14 days by default (from Azure's documented behaviour).
- Fix used: `permanently_delete_on_destroy = true` in the `log_analytics_workspace` block under `features`. After two destroys no soft-deleted workspace was listed and the same name was created again. It was not tested without the setting, so this fits the setting working but does not prove it.

### The flow log is not in the project resource group

- The VNet flow log is created in `NetworkWatcherRG`, next to the existing Network Watcher (`NetworkWatcher_southeastasia`). Terraform only reads that Network Watcher and never creates or destroys it.
- After a destroy, `az group exists` on the project group does not cover the flow log. Check it with:

        az network watcher flow-log list --location southeastasia --query "[].name" -o tsv

  It should list none of ours. Keep the `--query`: without it the output includes the subscription ID.

### Azure Run Command does not work under deny-all outbound rules

- Seen: Microsoft's documentation says Run Command needs outbound TCP 443 to Azure public IP addresses to return its result. The deny-all outbound NSG rules block that.
- Fix: the VMs run a cloud-init self-test that writes `NETTEST` lines, and the result is read from the boot log.

### The boot log is one very long line

- Seen: `az vm boot-diagnostics get-boot-log` returns about 80 KB as a single line, with line breaks written as text. `grep NETTEST` prints all of it.
- Fix: print only the matching text, one result per line:

        az vm boot-diagnostics get-boot-log --resource-group RESOURCE_GROUP --name VM_NAME | grep -o 'NETTEST [^\\]*'

### A VM size is not available

- Seen: every B-series size was `NotAvailableForSubscription` in `southeastasia` for this subscription.
- Fix: check availability and quota first, price second. `az vm list-skus` hides restricted sizes unless `--all` is given. The tests use `Standard_DC1ds_v3`.

### Counts do not match

- `terraform state list` counts data sources as well. A plan of 52 resources shows 54 lines, because two data sources are listed.
- `terraform plan | tail -3` shows the note about `-out`, not the summary. Use `terraform plan | grep "Plan:"`.
- `terraform validate` in the repository root checks nothing, because there are no `.tf` files there. Use `terraform -chdir=infra validate`.

### Why every tier has its own deny rule

- The built-in NSG rules at priority 65000 allow all traffic between subnets of the same VNet. Without an explicit deny at 4096 in each NSG, the web tier could reach the database directly. See the [traffic matrix](traffic-matrix.md).

## Checkov and CI

### CI did not scan the code behind a switch

- Seen: Checkov does not scan a resource whose `count` is 0, so the default scan passed the same number of checks before and after the optional NAT Gateway code was added.
- Fix: `infra/checkov.tfvars` switches every optional part on, and CI passes it with `--var-file`. When a new switch is added, set it to `true` in that file in the same pull request. A deliberate failing test showed that CI now fails on a bad optional resource ([evidence](evidence/checkov-switch-gated-negative-test.md)).
- Not explained: after five inline skips were added to a resource with `count = 0`, the default scan's skipped count rose by five, including three single-resource checks. The explanation that single-resource checks ignore such a resource is at least incomplete.

### CKV_AZURE_206 and zone-redundant storage

- Seen: zone-redundant storage (ZRS) does not satisfy the check. It wants geo-redundant replication.
- Fix: keep locally redundant storage and skip the check inline with a written reason, for a short-lived test account.

### Inline skips

- A skip is a comment inside the resource block, in the form `#checkov:skip=CKV_AZURE_206: reason`. Every skip in this repo has a written reason.

### Changing the Checkov version

- Install the new version in a separate virtual environment, run both scans (with and without the var file) and compare the counts before changing the pin in `.github/workflows/terraform-ci.yml`. The move from 3.3.28 to 3.3.30 gave identical counts.
- Dependabot here watches GitHub Actions only, so the Checkov, Terraform and tflint versions are updated by hand.
- On macOS, `brew install tflint` did not find a formula. The command from the tflint README worked: `brew install terraform-linters/tap/tflint`.

## Costs and prices

### Cost analysis uses UTC dates

- Manila is UTC+8, so a run in the early morning of Oct 24 shows under Oct 23. Start the date range a day early and check the total against the subscription Overview.

### The Retail Prices API returns an empty list

- Seen: empty results with an `armRegionName` filter or an exact `serviceName`.
- Fix: widen the filter, for example `contains(productName,'NAT Gateway')`. The private endpoint and private DNS meters are `Global`, so a region filter hides them. These are list prices, not the bill.

## Azure CLI

### A query prints nothing

- A null result prints nothing, so empty output is not proof that something is missing. Choose the query from the shape of the output: a bare list needs `[].name`, an object with a `value` list needs `value[].name`. For example, `az monitor diagnostic-settings list` returned a bare list, so a query starting with `value[]` printed nothing.
- The VM agent status in `az vm get-instance-view` is under `instanceView.vmAgent.statuses[0]`.

### az group exists prints false

- `false` also means that the name never existed. Copy the exact name, and use `--name`. The project group is `rg-netfound-dev-southeastasia-001`.

### Output that contains identifiers

- Commands without `--query` can print the subscription ID and resource IDs. Select the fields you need with `--query` and `-o tsv`. Never paste raw terminal logs into the repository, and crop or blur the subscription ID in screenshots.

## macOS shell and tools

- `grep` refuses a repetition count above 255 (`maximum repetition exceeds 255`). Use 200 or less.
- `nano` wraps long lines by default. Use `nano -w`. To open a file at a line, use `nano -w +63 FILE`.
- The system `pip` is old and does not support `pip index versions`. Do not upgrade it. Keep tools such as Checkov in a virtual environment.
- A heredoc (`cat > FILE << 'EOF'`) shows a `heredoc>` prompt and waits for `EOF` alone on its line. Ctrl+C aborts it. A copy box cut short, or a pasted `^[[200~` marker (`zsh: bad pattern`), writes nothing: paste again.

## Git

- Push rejected with GH007: GitHub email privacy is on. Set your GitHub noreply address as the Git email, run `git commit --amend --reset-author --no-edit`, and push again.
- A pager that freezes the terminal: press `q`, or use `git --no-pager`.
- `git pull` printing "Already up to date" and `git branch -d` warning "not yet merged" mean the pull request was not merged yet. Merge it first, then run `git switch main`, `git pull`, `git branch -d BRANCH`, `git fetch --prune`.
