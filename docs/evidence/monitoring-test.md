# Monitoring test: VNet flow log and NSG logs

Date: 2026-10-31 (UTC). Switch: `deploy_monitoring`.

This test checks that the monitoring switch works end to end: a VNet flow log writes to a locked down storage account, and the NSGs send their logs to a Log Analytics workspace. Traffic Analytics was not used, because it is billed per GB.

## What was deployed

| Resource | Purpose |
|---|---|
| Storage account for flow logs | Standard LRS, shared keys off, firewall default Deny, trusted Azure services allowed, 7 day blob soft delete |
| Role assignment | Storage Blob Data Reader on that account for the identity that runs Terraform |
| VNet flow log | Version 2, 90 day retention, created in the existing Network Watcher |
| Log Analytics workspace | PerGB2018, 30 day retention, 0.1 GB daily cap |
| Diagnostic settings | One per NSG, categories NetworkSecurityGroupEvent and NetworkSecurityGroupRuleCounter |

The Network Watcher already exists outside the project, so Terraform only reads it and never creates or destroys it.

## Stage A: monitoring only, no VMs

Plan: 33 to add. Apply: 33 added. Read back from Azure after the apply:

| Check | Result |
|---|---|
| Flow log | Provisioning succeeded, enabled, JSON version 2, retention enabled for 90 days |
| Storage account | Firewall Deny, bypass Logging, Metrics and AzureServices, shared key off, TLS 1.2, public blob access off |
| Diagnostic setting on the app NSG | Both log categories enabled, sent to the project workspace |
| Destroy | 33 destroyed in two runs, because a transient 409 stopped the first. No flow log left in the region. The Network Watcher was untouched |

Stage A showed that Azure accepts the design. It could not show data, because there was no traffic.

## Stage B: VMs, private endpoint and monitoring

Switches: `deploy_test_vms`, `deploy_private_endpoint` and `deploy_monitoring`, plus an optional reader IP for the session so the laptop could read the blobs. The IP is never committed.

Plan: 52 to add. The first apply stopped on a transient 409 (AnotherOperationInProgress) while creating a subnet. Running the same apply again added the remaining 6. The state then held 54 entries, which is 52 resources plus 2 data sources.

### Connection tests from the VM boot logs

| VM | PASS | FAIL | Finished |
|---|---|---|---|
| web | 5 | 0 | DONE |
| app | 6 | 0 | DONE |
| db | 4 | 0 | DONE |

### Flow log blobs

The container `insights-logs-flowlogflowevent` held 3 blobs. They were readable from the laptop through the reader IP and the Blob Data Reader role, which shows that the flow log writes through the trusted service bypass. The newest blob grew from about 73.8 KB to about 90.5 KB while it was being checked.

Rule names found in the newest blob. These are how often each name appears in the file, not connection counts:

| Rule | Appearances |
|---|---|
| UserRule_Deny-All-Inbound | 28 |
| PlatformRule | 16 |
| UserRule_Allow-HTTPS-Inbound | 11 |
| UserRule_Deny-All-Outbound | 3 |
| UserRule_Allow-Web-To-App-Outbound | 1 |

Four flow tuples with the IP addresses replaced. The timestamps are 14:31 UTC, during the VM boot tests:

    1793457078014,<ip>,<ip>,23456,25810,6,I,B,NX,0,0,0,0
    1793457083030,<ip>,<ip>,23456,25810,6,I,E,NX,1,128,1,60
    1793457086040,<ip>,<ip>,59712,8081,6,I,D,NX,0,0,0,0
    1793457071040,<ip>,<ip>,33590,443,6,O,D,NX,0,0,0,0

Field order, as read from the data and not checked against Microsoft's format reference: time in milliseconds, source, destination, source port, destination port, protocol (6 is TCP), direction (I inbound, O outbound), flow state (B begin, E end, D denied), encryption, then packet and byte counters. The first two lines are one allowed inbound flow. The last two are denied flows, which fits Deny-All-Inbound and the blocked internet tests. No tuple was matched to a specific rule.

### NSG logs in the workspace

A query over the last 3 hours returned 93 rows of each category, NetworkSecurityGroupRuleCounter and NetworkSecurityGroupEvent. A second query summed the matched connections per rule over the rule counter rows:

| Action | Direction | Rule | Connections |
|---|---|---|---|
| block | Out | UserRule_Deny-All-Outbound | 1037 |
| block | In | UserRule_Deny-All-Inbound | 1025 |
| allow | In | UserRule_Allow-HTTPS-Inbound | 27 |
| allow | Out | UserRule_Allow-App-To-PE-Outbound | 4 |
| allow | In | UserRule_Allow-App-To-DB-Inbound | 3 |
| allow | Out | UserRule_Allow-App-To-DB-Outbound | 2 |
| allow | In | UserRule_Allow-Web-To-App-Inbound | 2 |
| allow | Out | UserRule_Allow-Web-To-App-Outbound | 1 |

Rules with zero matches (the Azure default rules and Allow-AzureLoadBalancer-Inbound) are left out. The large block counts include retries of blocked connections, and possibly scanning of the web VM's public IP from the internet. The causes were not separated.

## Destroy and cleanup

Destroy used the same three switches. It took two runs: the first stopped on another transient 409, this time while removing the route table association on the database subnet, and the second run removed the last 5 resources. Checks after the destroy:

| Check | Result |
|---|---|
| Project resource group | Does not exist |
| State resource group | Still exists |
| Terraform state | 0 entries |
| Flow logs in the region | None |
| Network Watcher | Still present, not part of this project |
| Soft deleted workspaces | None |

The same workspace name was created again in Stage B after Stage A, without a conflict, with `permanently_delete_on_destroy` set. Without that setting the behaviour was not tested.

The throwaway SSH key and the session variables (the public key and the reader IP) were removed afterwards, and the downloaded blob was deleted.

## Cost

Not read yet. The billed window for Stage B was about 14:20 to 15:27 UTC on 2026-10-31. Stage A had no VMs and ran for minutes. The real figure comes from Cost analysis and will be added in a later change.

## Not tested

- Traffic Analytics (billed per GB, not used).
- Disabling public network access on the flow log storage account completely.
- Flow log retention deleting old blobs, which would need 90 days.
- The diagnostic setting on the endpoint NSG was created, but its logs were not queried separately.
- Which rule matched each individual flow tuple.
- Alerts or dashboards on the logs.
