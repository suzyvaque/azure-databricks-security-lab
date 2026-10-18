# Resource inventory

**Baseline and CMK-NSP-03 repeat verified 2026-10-18.** Current target workspace is `Succeeded` with Managed Services CMK applied. Names use the `RUN` alias for the real run identifier. No subscription/tenant IDs, addresses or key versions are published; actual values are in ignored local storage.

## Actual deployed inventory (verified in Azure)

All resources are in one new resource group in `koreacentral` unless noted. Validation "configuration" means properties were read, not traffic tested.

| Resource | Type | Region | Verified configuration | Validation | Cleanup |
| --- | --- | --- | --- | --- | --- |
| rg-dbxcmk-krc-RUN | Resource group | koreacentral | Tags: project, environment, region, run, managedBy | Exists | Primary cleanup boundary |
| vnet-…-ws | VNet | koreacentral | /24; host, container (delegated, /26) and PE (/27) subnets; NAT gateway on host and container | Configuration | In RG |
| vnet-…-transit | VNet | koreacentral | /24; auth host/container (delegated, /27) and PE (/26) subnets | Configuration | In RG |
| nsg-…-ws, nsg-…-auth | NSG | koreacentral | Three outbound rules required by the Databricks network intent policy (SQL 3306, Storage 443, EventHub 9093) | Configuration | In RG |
| nat-…, pip-…-nat | NAT gateway, public IP | koreacentral | Outbound-only egress for the workspace subnets; unfiltered | Exists | In RG |
| dbw-… | Databricks workspace | koreacentral | Premium; custom VNet; `enableNoPublicIp=true`; public access Disabled; `NoAzureDatabricksRules`; final provisioning state **`Succeeded`** after CMK-NSP-03 phase B | Configuration; current CMK applied | In RG; managed RG separate; **CMK cannot be disabled once enabled** |
| dbw-…-auth | Databricks workspace (auth only) | koreacentral | Same private-only settings; no compute | Configuration | In RG; managed RG separate |
| pe-…-uiapi | Private endpoint | koreacentral | `databricks_ui_api`, Approved/Succeeded; front-end and back-end roles | Configuration | In RG |
| pe-…-auth | Private endpoint | koreacentral | `browser_authentication`, Approved/Succeeded | Configuration | In RG |
| pe-…-vault | Private endpoint | koreacentral | `vault`, Approved/Succeeded, in the workspace VNet | Configuration | In RG |
| pe-…-vault-vm | Private endpoint | koreacentral | `vault`, Approved/Succeeded; its NIC takes one IP from the **existing VM subnet** | Resolves privately from the VM | In RG |
| privatelink.azuredatabricks.net | Private DNS zone | global | Links: workspace VNet and transit VNet; 3 record sets | Configuration | In RG |
| privatelink.vaultcore.azure.net | Private DNS zone | global | Links: workspace VNet and transit VNet | Configuration | In RG |
| \<vault\>.privatelink.vaultcore.azure.net | Private DNS zone | global | One link: the **existing VM VNet**; one A record to the VM-side endpoint | Resolves privately from the VM | In RG; link affects existing VNet |
| kv… | Key Vault | koreacentral | Standard; RBAC; public access Disabled; bypass `None`; default Deny; no Key Vault IP rules; soft delete 7 days; purge protection | Configuration; private access from the VM; control-plane CMK request admitted by Enforced NSP rule, not by a customer PE | Soft-deleted vault remains after RG deletion |
| cmk-managed-services | Key | koreacentral (vault child) | RSA 2048 software key, enabled; created over the private endpoint | Enabled | With vault |
| law-… | Log Analytics workspace | koreacentral | PerGB2018, 30-day retention | Exists | In RG |
| audit-to-law | Diagnostic setting | Vault child | AuditEvent to the new workspace | Created; queried for CMK audit events across the experiments | With vault |
| Role assignment (AzureDatabricks app) | RBAC | Vault scope | Key Vault Crypto Service Encryption User on the vault; the principal is the tenant's AzureDatabricks service principal | Read back 2026-10-18: present, correct principal and scope | Scope-bound |
| Role assignment (signed-in user) | RBAC | Vault scope | Key Vault Crypto Officer, created for key authoring | Used successfully | Remove after the experiment |
| adb-koreacentral-dp-to-cp-pl-… (four) | Network intent policies | koreacentral | Created by Databricks in the RG; require the NSG rules above | Exists | Provider-managed |
| …-snet-pe-nsg-koreacentral (two) | NSGs | koreacentral | Created automatically on the PE subnets; **not** defined in the templates | Exists | In RG |
| rg-managed-…-ws, rg-managed-…-auth | Databricks managed resource groups | **Not verified** | Service-created; the workspace storage account uses ZRS | Not read | Provider-managed; verify deletion |
| peer-to-vm-ws, peer-to-vm-transit | VNet peering (new side) | PoC RG | Connected; vnet access on; forwarded traffic off; no gateway transit | Connected | In RG |
| peer-dbxcmk-RUN-to-ws, peer-dbxcmk-RUN-to-transit | VNet peering (**existing VM VNet side**) | **Existing VM resource group** | Connected; vnet access on; forwarded traffic off; no gateway transit | Connected | **Must be deleted explicitly**; not removed by deleting the PoC RG |
| link-vm (on privatelink.azuredatabricks.net) | Private DNS zone link | PoC RG | Links the new zone to the **existing VM VNet** | VM resolves workspace privately | In RG; affects the existing VNet |
| nsp-… | Network security perimeter | koreacentral | Profile `profile-poc`; vault association Enforced; one inbound address rule restored after CMK-NSP-03 phase A; Log Analytics association Learning/Transition mode | Final read-back: vault association Enforced, one rule; CMK-NSP-03 A denied with `ForbiddenByNsp`, B succeeded | In RG; **retain pending owner decision**; removal requires an approved sequence. If the vault is `SecuredByPerimeter` when its association is removed it is locked down |
| assoc-vault | Perimeter resource association | PoC RG | Key Vault, **Enforced** mode | Succeeded, no provisioning issues | With the perimeter |
| assoc-law | Perimeter resource association | PoC RG | Log Analytics workspace, Transition mode | Succeeded | With the perimeter |
| allow-databricks-cp | Perimeter inbound access rule | PoC RG | One public IPv4 address (/32), the control-plane address seen in the audit log; actual address stays in local evidence | Present in final state; removal caused `ForbiddenByNsp`, restoration was followed by successful CMK | With the perimeter; retain pending owner decision |
| nsp-to-law | Diagnostic setting on the perimeter | Perimeter child | All perimeter logs to the PoC Log Analytics workspace | Created; no log rows when read | With the perimeter |

### Deviations from the original plan

- Outbound uses a NAT gateway, not a filtering firewall. Back-end Private Link does not make every dependency private.
- No route tables or DNS resolver were created.
- Peerings were added later, on approval: both new VNets are peered directly with the VM VNet (no transit-to-workspace peering).
- The vault endpoint sits in the workspace VNet instead of the transit VNet, and a second endpoint was added in the VM's subnet with a VM-only zone, so the VM needs no peering to reach the vault.
- The key is created from the VM over the private endpoint, not by the template.

## Original plan (kept for comparison)

Aliases/prefix lengths below are not actual addresses or allocations. All actual CIDRs/IPs will be kept in ignored local inventory after read-only overlap review and deployment approval.

| Name template / alias | Type | Resource Group | Region | Purpose / important values | Connected resources | Deployment | Validation | Cleanup |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| rg-dbxcmk-krc-RUN | Resource group | Self | koreacentral | New operator-managed isolation boundary | All customer resources | Planned | Not run | Not applicable |
| vnet-dbxcmk-krc-RUN-workspace | VNet | PoC RG | koreacentral | CIDR TBD locally; nonoverlapping | Target workspace + UI/API PE | Planned | Not run | Not applicable |
| snet-host / snet-container | Delegated subnets | PoC RG, VNet children | Parent: koreacentral | `/26` each proposed; delegation Databricks | Workspace NSG + new route tables | Planned | Not run | Not applicable |
| snet-workspace-pe | Subnet | PoC RG | Parent: koreacentral | `/27`, no Databricks delegation | Shared UI/API PE | Planned | Not run | Not applicable |
| nsg-…-workspace; rt-…-host/container | NSG / route tables | PoC RG | koreacentral | Required delegated rules; explicit reviewed routes | Target compute subnets | Planned | Not run | Not applicable |
| vnet-dbxcmk-krc-RUN-transit | VNet | PoC RG | koreacentral | CIDR TBD locally; separate range | Auth workspace, vault/auth PEs | Planned | Not run | Not applicable |
| snet-auth-host/container; nsg-…-auth; rt-…-auth | Subnets/NSG/route tables | PoC RG | Parent/KRC | Two `/26` delegated subnets; no workloads | Auth-only workspace | Planned | Not run | Not applicable |
| snet-transit-pe | Subnet | PoC RG | Parent: koreacentral | `/26`, not delegated | Vault + auth PEs | Planned | Not run | Not applicable |
| egress-… and dedicated subnets/IPs | Firewall / routes / supporting resources | PoC RG | koreacentral | Exact SKU/allowlist pending | Compute subnet outbound | Blocked design gate | Not run | Not applicable |
| dbw-dbxcmk-krc-RUN | Databricks workspace | PoC RG | koreacentral | Premium; SCC true; PNA Disabled | New workspace VNet; CMK only at approved attempt | Planned | Not run | Not applicable |
| dbw-dbxcmk-krc-RUN-auth | Auth-only workspace | PoC RG | koreacentral | Premium; SCC true; PNA Disabled; no compute | New transit auth subnets | Planned | Not run | Not applicable |
| managed-dbxcmk-krc-RUN-target/auth | Two managed RGs | Outside customer RG | RG location must be checked | Service-created, never reused | Workspace-managed storage/compute; KRC only | Planned exception | Not run | Provider lifecycle; verify |
| pe-…-uiapi + generated NIC | Private Endpoint/NIC | PoC RG | koreacentral | `databricks_ui_api`, private IP not allocated | Target workspace; front + back roles | Planned | Not run | Not applicable |
| pe-…-auth + generated NIC | Private Endpoint/NIC | PoC RG | koreacentral | `browser_authentication`, private IP not allocated | New auth workspace | Planned | Not run | Not applicable |
| privatelink.azuredatabricks.net | Private DNS zone/records/zone groups | PoC RG | global | Workspace/relay/auth records from PE metadata | Links to both new VNets; approved VM VNet link | Planned | Not run | Not applicable |
| kvdbxcmkkrcRANDOM / cmk-managed-services | Key Vault / RSA key | PoC RG | koreacentral / parent | Standard, RBAC, PNA Disabled, bypass None, default Deny; exact key version local-only | Vault PE; documented CMK caller if approved | Planned | Not run | Soft-delete retention expected |
| pe-…-vault + generated NIC | Private Endpoint/NIC | PoC RG | koreacentral | `vault`, private IP not allocated | New vault + transit subnet | Planned | Not run | Not applicable |
| privatelink.vaultcore.azure.net | Private DNS zone/records/links | PoC RG | global | Vault A record; new transit and approved VM link | Vault PE; optional workspace link | Planned | Not run | Not applicable |
| law-dbxcmk-krc-RUN | Log Analytics workspace | PoC RG | koreacentral | PerGB2018; 30-day retention proposed | Vault AuditEvent setting | Planned | Not run | Not applicable |
| diag-…-vault | Diagnostic setting | Extension of new vault | Nonregional extension | AuditEvent to new LAW | New vault + LAW | Planned | Not run | Parent-bound |
| crypto/authoring role assignments | RBAC assignments | Scoped to new key/vault as supported | Nonregional | Least privilege; actual object IDs local-only | Approved operator/documented CMK caller | Planned | Not run | Scope-bound; verify |
| peer-…-vm-workspace / peer-…-vm-transit | Four directional peering children | Two new-side in PoC RG; two existing-side outside | Parent VNet regions | Connected required; no gateway transit | Existing VM VNet ↔ each new VNet | Approval required | Not run | Explicit cross-RG removal |
| resolver-…; inbound subnet/endpoint | Optional DNS resolver resources | PoC RG | koreacentral | Only if custom DNS requires it; dedicated subnet | New zones, approved existing forwarder | Conditional | Not run | Not applicable |

## Changes outside PoC RG

**Actual changes outside the PoC RG:**

- Two peering links on the existing VM VNet (one per new VNet). **These live in the existing VM's resource group.**
- One private IP allocated in the existing VM subnet (the endpoint and NIC resources are in the PoC RG).
- One private DNS zone link from the PoC RG to the existing VM VNet, plus the vault-specific zone link.
- Two Databricks-managed resource groups (service-created).
- **Governance finding, not a change we made:** a management-group Azure Policy (`KeyVault_PublicNetwork_Modify`, effect `modify`) applies to the vault and forces `publicNetworkAccess` to `Disabled` on every write. We did not alter it.
- One private endpoint connection on the vault created by Databricks from the account-level NCC private endpoint rule (Approved). It is not in our templates. The NCC itself lives in the Databricks account, outside Azure. **Remove by deleting the NCC private endpoint rule in the account console**; Databricks may keep the endpoint on the vault for up to a day. The rule bills hourly while it exists.
- The VM, its NIC, NSG, routes and DNS-server settings were **not** modified.

Not approved and not done: existing resolver changes, NSG/UDR changes.

Before deployment create an ignored local manifest containing resource IDs, ownership/run identifiers, actual names/CIDRs/IPs, DNS links, baseline hashes and every approved cross-boundary artifact. After each operation record created/updated UTC time, verification and cleanup state. Public documentation retains only sanitized outcomes.
