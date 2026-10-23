# Live traffic test of the NSG design

Date: 22 October 2026. Region: southeastasia.

## Result

All 14 checks matched the design. The only open paths are Internet to web on 443, web to app on 8443, and app to db on 1433. Everything else was silently dropped by the NSGs.

## What was deployed

- The three-tier network from `infra/main.tf` (web, app and db subnets, one NSG each).
- Three Ubuntu 24.04 LTS (Gen2) VMs, size `Standard_DC1ds_v3`, one per subnet, from `infra/test-vms.tf`.
- A temporary public IP on the web VM only.
- Everything was destroyed after the test. `az group exists` for the project resource group returned `false`, and the state storage resource group was left in place.

## How it was tested

Each VM ran a cloud-init script (`infra/test-vms-cloud-init.tftpl`) at first boot. The script starts a small listener on the tier's port, waits 120 seconds for the other VMs, then tries TCP connections with a 4 second timeout. A connection that connects counts as `open`. A connection that times out counts as `filtered`, which is how an NSG deny behaves. The result lines were printed to the serial console and read from outside with `az vm boot-diagnostics get-boot-log`. The Internet checks were run from an administrator laptop with `nc -vz -w 5`.

## Results

Inside the network (from the VMs):

| From | To | Expected | Actual | Result |
| --- | --- | --- | --- | --- |
| web | app 8443 | open | open | PASS |
| web | app 22 | blocked | filtered | PASS |
| web | db 1433 | blocked | filtered | PASS |
| web | Internet 1.1.1.1:443 | blocked | filtered | PASS |
| app | db 1433 | open | open | PASS |
| app | db 22 | blocked | filtered | PASS |
| app | web 443 | blocked | filtered | PASS |
| app | Internet 1.1.1.1:443 | blocked | filtered | PASS |
| db | app 8443 | blocked | filtered | PASS |
| db | web 443 | blocked | filtered | PASS |
| db | Internet 1.1.1.1:443 | blocked | filtered | PASS |

From the Internet to the web VM public IP (`<web public IP>`):

| Port | Expected | Actual | Result |
| --- | --- | --- | --- |
| 443 | open | connection succeeded | PASS |
| 22 | blocked | timed out | PASS |
| 80 | blocked | timed out | PASS |

## Findings

- B-series VM sizes are not available to this subscription in southeastasia (`NotAvailableForSubscription`), so `Standard_DC1ds_v3` was used. Its VM family quota is 4 vCPUs, which fits three VMs.
- Azure Run Command needs outbound access on port 443 to return its results, which the deny-all outbound NSG rules block. The test therefore uses cloud-init and the serial console instead.
- The VM agent reported `Ready` ("Guest Agent is running") about 35 minutes after creation, with the deny-all outbound rules in place. The portal showed "agent status is not ready" two minutes after creation, which was early boot timing.
- Checkov raised three findings on the test VM code. Two were fixed in the code (SSH key default, VM extensions disabled). One is a documented skip: CKV_AZURE_119, the deliberate temporary public IP on the web VM.

## What this does not prove

- It was one run, with TCP connections only. UDP and ICMP were not tested.
- The listeners are plain TCP listeners, not real TLS services.
- SSH access to the VMs was not tested. Login was disabled for the test and the key was never used.
- NSG flow logs were not captured.
- The web VM had a public IP attached directly. A production design would put a load balancer or application gateway in front.

## Cost

Read from Azure Cost analysis on 23 October 2026, filtered to the project resource group (usage of 22 October, about one hour of runtime): $0.34 in total. Virtual Machines $0.32 (about $0.11 per VM), Virtual Network under $0.01, Storage under $0.01 and Bandwidth under $0.01. So the three OS disks and the public IP together cost under three cents.

The estimate made before the test (three VMs at about $0.141 per hour for about one hour, about $0.46) was roughly a third too high. The reason was not investigated: either the price used differs from what this subscription is charged, or the VMs ran for less time than assumed.
