# Live traffic test of the outbound design

Date: 25 October 2026 (full run). Region: southeastasia.

## Result

All 16 checks matched the design: 13 from inside the VMs and 3 from the Internet. Azure's effective route tables also confirmed the route table on the database subnet and the NAT Gateway path on the app subnet.

## What was tested

The outbound design from `infra/outbound.tf`, switched on with `deploy_nat_gateway=true`:

- A NAT Gateway with its own public IP on the app subnet. It is the only way out to the Internet.
- An NSG rule on the app subnet that allows outbound TCP 443 to the Internet. Everything else outbound stays denied.
- A route table on the database subnet with a default route (0.0.0.0/0) whose next hop is `None`, so database traffic toward the Internet is dropped.
- The web subnet has no route table and no NAT. Its public IP is only for the test.

The same three Ubuntu 24.04 LTS VMs from the first live test were used (`infra/test-vms.tf`). Everything was destroyed afterwards, `az group exists` for the project resource group returned `false`, and the state storage group was left in place.

## How it was tested

Same method as `live-traffic-test.md`: a cloud-init script on each VM (`infra/test-vms-cloud-init.tftpl`) runs the checks at first boot and prints the results to the serial console, which was read from outside with `az vm boot-diagnostics get-boot-log`. New in this test: the app VM asks `https://1.1.1.1/cdn-cgi/trace` which source address the Internet sees and compares it with the NAT Gateway's address. The effective route tables were read with `az network nic show-effective-route-table`. The Internet checks were run from an administrator laptop with `nc -vz -w 5`.

## Results

From the web VM:

| To | Expected | Actual | Result |
| --- | --- | --- | --- |
| app 8443 | open | open | PASS |
| app 22 | blocked | filtered | PASS |
| db 1433 | blocked | filtered | PASS |
| Internet 1.1.1.1:443 | blocked | filtered | PASS |

From the app VM:

| To | Expected | Actual | Result |
| --- | --- | --- | --- |
| db 1433 | open | open | PASS |
| db 22 | blocked | filtered | PASS |
| web 443 | blocked | filtered | PASS |
| Internet 1.1.1.1:443 (via NAT) | open | open | PASS |
| Internet source address | equals `<NAT public IP>` | equals `<NAT public IP>` | PASS |
| Internet 1.1.1.1:80 | blocked | filtered | PASS |

From the db VM:

| To | Expected | Actual | Result |
| --- | --- | --- | --- |
| app 8443 | blocked | filtered | PASS |
| web 443 | blocked | filtered | PASS |
| Internet 1.1.1.1:443 | blocked | filtered | PASS |

From the Internet to the web VM public IP (`<web public IP>`):

| Port | Expected | Actual | Result |
| --- | --- | --- | --- |
| 443 | open | connection succeeded | PASS |
| 22 | blocked | timed out | PASS |
| 80 | blocked | timed out | PASS |

Effective routes reported by Azure:

| NIC | Route | Next hop | State |
| --- | --- | --- | --- |
| db | 0.0.0.0/0 (source: User, our route table) | None | Active |
| db | 0.0.0.0/0 (system default) | Internet | Invalid, overridden by ours |
| app | 0.0.0.0/0 (system default) | Internet | Active, with the NAT Gateway on the subnet |

## Findings

- The source address seen by an Internet service was the NAT Gateway's public IP, so the app tier leaves through the NAT Gateway and not through any other path.
- On the database subnet, the route table cannot be seen in the traffic tests, because the NSG already drops all outbound traffic. Only the effective route table proves it is attached and active.
- The VM agent reported `Ready` on all three VMs when checked, about 50 minutes after the apply, including the database VM with the `None` default route. It was not checked earlier.
- The first NAT run on 24 October was incomplete: only the app log and the Internet checks were captured before the environment was destroyed. The web and database logs and the effective routes were missing, so the full run on 25 October is the evidence.

## What this does not prove

- It was one full run, with TCP only. UDP and ICMP were not tested.
- The NAT Gateway filters by port and not by domain. The app VM can reach any host on port 443, not only the ones it needs. The test only used 1.1.1.1. Domain filtering needs a firewall.
- DNS resolution from the VMs was not tested.
- NAT idle timeout behavior and NSG flow logs were not tested.
- The web VM had a public IP attached directly. A production design would put a load balancer or application gateway in front.

## Cost

Real figures: to be added from Azure Cost analysis once the billing data has updated. The NAT Gateway Standard list price is $0.045 per hour plus $0.045 per GB processed (Azure Retail Prices API). The full run lasted a little over one hour.
