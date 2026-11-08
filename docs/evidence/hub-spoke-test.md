# Live traffic test of the hub-and-spoke topology

Date: 8 November 2026 (full run). Regions: southeastasia (hub and spoke 1) and japaneast (spoke 2).

## Result

All 19 checks matched the design. The effective route table of the spoke 2 network card confirmed that peering is not transitive: it has a route to the hub and none to spoke 1.

## What was tested

The topology from `infra/hub-spoke.tf`, switched on with `deploy_hub_spoke=true` together with `deploy_test_vms=true` and five test VMs (`test_vm_tier_names`):

- A hub VNet (`10.20.0.0/22`) with one shared subnet, spoke 1 (the existing `10.10.0.0/20` network) and spoke 2 (`10.30.0.0/20`, japaneast).
- Four peering resources: spoke 1 to hub, hub to spoke 1, spoke 2 to hub and hub to spoke 2. The hub and spoke 1 link is regional peering and the hub and spoke 2 link is global peering. All four were `Connected` and forwarded traffic was off.
- An NSG on the hub shared subnet and one on the spoke 2 workload subnet, both deny by default, and one extra rule on the app tier of spoke 1 that accepts TCP 8443 from the hub shared subnet.
- Five Ubuntu VMs, one per subnet: web, app, db, hub shared and spoke 2 workload. All five were created in the same minute.

The spoke 2 VM is in another region only because of the 4 vCPU regional quota, see `docs/troubleshooting.md`.

## How it was tested

Same method as `live-traffic-test.md`: a cloud-init script on each VM (`infra/test-vms-cloud-init.tftpl`) runs the checks at first boot and prints `NETTEST` lines to the serial console, read from outside with `az vm boot-diagnostics get-boot-log`. The peering state was read with `az network vnet peering list` and the routes with `az network nic show-effective-route-table`.

## Results

From the web VM:

| To | Expected | Actual | Result |
| --- | --- | --- | --- |
| app 8443 | open | open | PASS |
| app 22 | blocked | filtered | PASS |
| db 1433 | blocked | filtered | PASS |
| Internet 443 | blocked | filtered | PASS |

From the app VM:

| To | Expected | Actual | Result |
| --- | --- | --- | --- |
| db 1433 | open | open | PASS |
| db 22 | blocked | filtered | PASS |
| web 443 | blocked | filtered | PASS |
| Internet 443 | blocked | filtered | PASS |

From the db VM:

| To | Expected | Actual | Result |
| --- | --- | --- | --- |
| app 8443 | blocked | filtered | PASS |
| web 443 | blocked | filtered | PASS |
| Internet 443 | blocked | filtered | PASS |

From the hub shared VM (new):

| To | Expected | Actual | Result |
| --- | --- | --- | --- |
| app 8443 over peering | open | open | PASS |
| app 22 | blocked | filtered | PASS |
| db 1433 | blocked | filtered | PASS |
| Internet 443 | blocked | filtered | PASS |

From the spoke 2 VM (new):

| To | Expected | Actual | Result |
| --- | --- | --- | --- |
| hub shared 443 | open | open | PASS |
| hub shared 22 | blocked | filtered | PASS |
| app 8443 (spoke 1) | blocked | filtered | PASS |
| Internet 443 | blocked | filtered | PASS |

Peering state, read from the hub:

| Peering | State | Forwarded traffic |
| --- | --- | --- |
| peer-hub-to-spoke1 | Connected | False |
| peer-hub-to-spoke2 | Connected | False |

Effective routes of the spoke 2 network card (the user-relevant entries; the rest are Azure's default entries with next hop `None`):

| Prefix | Next hop |
| --- | --- |
| 10.30.0.0/20 (spoke 2) | VnetLocal |
| 10.20.0.0/22 (hub) | VNetGlobalPeering |
| 10.0.0.0/8 (covers spoke 1, `10.10.0.0/20`) | None |

There is no route to `10.10.0.0/20` other than the default `10.0.0.0/8` entry with next hop `None`, so traffic from spoke 2 to spoke 1 is dropped before the NSGs matter. The blocked spoke 2 to app check agrees with this.

## What this does and does not prove

- Peering is not transitive, shown by the route table and by the blocked spoke 2 to app check. The NSG on spoke 2 also denies it, so two controls agree.
- The only cross-network flows that work are the two written in the traffic matrix: spoke 2 to hub shared on 443, and hub shared to app on 8443.
- The blocked checks cannot say which control dropped the packet (the route, the source NSG or the destination NSG). The route table evidence covers the spoke 2 to spoke 1 case only.
- It was one full run, with TCP only. UDP and ICMP were not tested.
- Spoke 1 to hub traffic initiated from the app tier was not tested, because the app tier has no outbound rule toward the hub.
- No firewall or network virtual appliance was used, so nothing inspects traffic between spokes. This is a hub-and-spoke layout, not a secured landing zone.
- Gateway transit and remote gateways were off, so no VPN or ExpressRoute path was tested.
- Latency and bandwidth across regions were not measured.

## Cleanup

Everything was destroyed afterwards. `az group exists` for the project resource group returned `false` and the state storage group was left in place. The free `NetworkWatcher_japaneast` that Azure creates in `NetworkWatcherRG` remains and is not managed by Terraform.

## Cost

Billed: five small virtual machines with their OS disks, for about an hour or less on 8 November 2026. VNet peering is billed by the amount of data transferred (global peering between regions at a higher rate than peering inside a region), and the test sent very little data. The virtual networks, subnets and NSGs are free.

No figure was read: Azure Cost analysis had not shown this test yet when the resources were destroyed. Prices depend on the region, the VM size, how long things run and the pricing of your subscription, so this file does not quote any. Read your own figures in Azure Cost analysis (Cost Management) after a run: the data can lag by hours, and its dates are in UTC.
