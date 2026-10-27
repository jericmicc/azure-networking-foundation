# Live test of the private endpoint and private DNS

Date: 27 October 2026 (full run). Region: southeastasia.

## Result

All 15 checks from inside the three VMs matched the design, and so did the 4 checks from the Internet and the deployed settings read with the Azure CLI. The VM agent reported `Ready` on all three VMs. Only the app VM can reach the private endpoint, and on the app VM the storage account's name resolved to the private IP.

## What was tested

The private endpoint design from `infra/private-endpoint.tf`, switched on with `deploy_private_endpoint=true`:

- A storage account with public network access off and shared key access off, so nothing reaches it from the Internet and no account key works.
- A private endpoint for its blob service in a new subnet, `snet-pe`, with its own NSG that allows TCP 443 only from the app subnet.
- A private DNS zone, `privatelink.blob.core.windows.net`, linked to the VNet, with an A record that Azure creates for the endpoint.
- An outbound NSG rule on the app subnet that allows TCP 443 to `snet-pe`. The web and database subnets have no such rule.

The same three Ubuntu 24.04 LTS VMs were used (`infra/test-vms.tf`) together with the private endpoint, 44 resources in total. The NAT Gateway was off. Everything was destroyed afterwards: Terraform reported 44 destroyed, `az group exists` for the project resource group returned `false`, and the state storage group was left in place.

## How it was tested

Same method as `live-traffic-test.md`: a cloud-init script on each VM (`infra/test-vms-cloud-init.tftpl`) runs the checks at first boot and prints the results to the serial console, which was read from outside with `az vm boot-diagnostics get-boot-log`. New in this test: the app VM resolves the storage account's blob host name with `getent hosts` and compares the answer with the private endpoint's IP, and every VM tries a TCP connection to the private endpoint on port 443. The deployed settings were read with the Azure CLI. The Internet checks were run from an administrator laptop: `nc -vz -w 5` against the web VM, and a request to the public blob endpoint.

## Results

From the app VM:

| To | Expected | Actual | Result |
| --- | --- | --- | --- |
| db 1433 | open | open | PASS |
| db 22 | blocked | filtered | PASS |
| web 443 | blocked | filtered | PASS |
| Internet 1.1.1.1:443 | blocked | filtered | PASS |
| Storage name resolves to | `10.10.4.4` (the private endpoint IP) | `10.10.4.4` | PASS |
| private endpoint 443 | open | open | PASS |

From the web VM:

| To | Expected | Actual | Result |
| --- | --- | --- | --- |
| app 8443 | open | open | PASS |
| app 22 | blocked | filtered | PASS |
| db 1433 | blocked | filtered | PASS |
| Internet 1.1.1.1:443 | blocked | filtered | PASS |
| private endpoint 443 | blocked | filtered | PASS |

From the db VM:

| To | Expected | Actual | Result |
| --- | --- | --- | --- |
| app 8443 | blocked | filtered | PASS |
| web 443 | blocked | filtered | PASS |
| Internet 1.1.1.1:443 | blocked | filtered | PASS |
| private endpoint 443 | blocked | filtered | PASS |

From the Internet to the web VM public IP (`<web public IP>`):

| Port | Expected | Actual | Result |
| --- | --- | --- | --- |
| 443 | open | connection succeeded | PASS |
| 22 | blocked | timed out | PASS |
| 80 | blocked | timed out | PASS |

From the Internet to the public blob endpoint of the test storage account:

| Request | Expected | Actual | Result |
| --- | --- | --- | --- |
| `?comp=list` on the blob host name | refused | HTTP 403, "This request is not authorized to perform this operation" | PASS |

Deployed settings read with the Azure CLI:

| Setting | Value |
| --- | --- |
| Private endpoint connection state | Approved |
| A record in the private DNS zone | `10.10.4.4` |
| Storage account public network access | Disabled |
| Storage account shared key access | False |
| Storage account replication and minimum TLS | Standard_LRS, TLS 1.2 |
| Blob soft delete | 7 days |

## Findings

- Only the app VM could reach the private endpoint. The web and database VMs got no answer on port 443 (filtered).
- Name resolution worked on the app VM even though the app NSG denies all other outbound traffic. I did not investigate why, only that it works.
- From the laptop, the storage host name resolves through the `privatelink` alias to a public address, and the public endpoint refuses the request. The private DNS zone only answers inside the VNet.
- The first apply created 36 of the 37 planned resources, then failed on the storage account: the Terraform provider tried to use the account's data plane, which needs keys, and shared keys are off. The fix is `data_plane_available = false` in `infra/providers.tf`. The provider then manages storage accounts through the management API only.
- The next apply failed with a 404 on the account's file share properties right after the account was created. The account was checked in Azure (public network access disabled, shared key access off, LRS, TLS 1.2), marked healthy with `terraform untaint` so it was not recreated, and the following apply created the one missing resource, the private endpoint.
- Three Checkov findings on the test storage account are skipped in `infra/private-endpoint.tf`, each with a written reason: queue logging (no queue is used), a customer-managed key (needs a billed Key Vault) and geo-redundant replication (the account lives about an hour and holds no data).

## What this does not prove

- It was one full run, with TCP only. UDP and ICMP were not tested.
- The checks open a TCP connection to the endpoint's IP on port 443. No HTTPS request, blob read or blob write was made. Shared keys are off, so a data request would need an Entra ID role, which was not tested.
- Name resolution was checked on the app VM only, not on the web or database VMs.
- The web and database results are explained by their own outbound deny rules, so they do not show whether the inbound rules of `nsg-pe` would also have blocked them.
- Only the blob service of one empty test account was used. Other storage services and real workloads were not tested.
- NSG flow logs and Private Link metrics were not tested. The web VM had a public IP attached directly, only for the test.

## Cost

Real cost from Azure Cost analysis has not been read yet. It lags by up to a day and its dates are in UTC. It will be added in a follow-up change. The private endpoint existed for about 1.5 hours and the three VMs for about 1 hour.

List prices (Azure Retail Prices API): a standard private endpoint is $0.01 per hour, plus $0.01 per GB of data processed in each direction. A private DNS zone is listed at $0.50, and I did not verify the unit (probably per month). The API also lists a meter named "Fixed Private Endpoint T1" at $14.00 per hour, effective 1 October 2026. I could not tell whether it applies to standard private endpoints, so the real meters will be read in Cost analysis.
