# Phase 1 feasibility assessment

> **Final CMK-IP-02 follow-up, 2026-10-19 local date:** NSP removed, absence verified, public access Disabled and bypass `None` retained, one stored control-plane IP firewall rule added. A new key version created over the VM PE was applied; CMK failed with 403 `ForbiddenByConnection`. Current workspace provisioning `Failed`, prior CMK retained. This confirms the stored IP rule did not admit the public request with PNA Disabled. Active selected-network access requires PNA Enabled, contrary to this follow-up's constraint and blocked in the earlier policy test. Historical NSP successes below do not describe current posture; supportability remains unconfirmed.

> **Update 2026-10-18 — experimental result.** Applying Managed Services CMK with the vault at public access Disabled, bypass `None` and private-endpoint-only access failed: the control plane's `KeyGet` was rejected with 403 `ForbiddenByConnection` from a public Azure address. The approved NCC connection did not change that result. Changing only bypass to `AzureServices` succeeded. An Enforced NSP inbound rule also allowed CMK with bypass `None`; removing the rule then failed with 403 `ForbiddenByNsp`, and restoring it made the repeat succeed. The NSP success is still a public control-plane path, not customer Private Endpoint routing. See [results](results.md). **Overall feasibility remains inconclusive pending written vendor confirmation**; the exact tested private-endpoint-only configuration failed, but no explicit support statement or supported routing setup has been obtained.

**Documentation re-check 2026-10-18.** Microsoft's Key Vault trusted-services page (updated 2026-08-20) lists **Azure Databricks** as a trusted service and states: "The bypass continues to apply when public access is disabled, so listed services don't require a private endpoint to connect", and that services *not* in the table "need a firewall IP rule, a virtual network rule, or a private endpoint". The Databricks managed-services CMK page (updated 2026-09-11) still takes only a vault URI, key name and pinned version, and its Key Vault setup contains no networking step. So the documented design is: the control plane reaches the vault **as a trusted service**, which requires bypass `AzureServices`. No customer private-endpoint route is documented, which is consistent with the experiment. The Key Vault Managed HSM variant has its own page that was not reviewed in detail.

**Confirmed by experiment, same day.** Changing only the vault bypass to `AzureServices` (public access still Disabled) made the CMK deployment succeed, and the audit log shows the control plane's `KeyGet` and `KeyUnwrap` authorised as trusted service `AzureDatabricks` from a public Azure address. This matches the documented design above. It still is not a customer private-endpoint route. See [results](results.md).

Initial research date: **2026-10-17**. The statements below that describe pre-deployment checks are historical snapshots; preflight, subscription context and VM networking were subsequently verified. This assessment is not a vendor support certification.

## Executive finding

**Do not assume the primary CMK objective is feasible.** The reviewed Managed Services CMK documentation and workspace ARM schema provide a vault URI, key name and explicit key version. They do not expose a customer VNet, Private Endpoint, NCC or routing configuration for the control-plane key client.

A Key Vault Private Endpoint is reachable by clients with routing/DNS to its VNet. It does not place the Databricks managed-services control plane in that VNet. Consequently, VM/cluster success calling Key Vault would validate a different source and cannot establish the requested CMK path.

**Precise finding:** Managed Services CMK with `publicNetworkAccess=Disabled`, `networkAcls.bypass=None` and Private Endpoint-only access is **not documented or configurable through the reviewed public interfaces, and the tested update failed at the Key Vault network layer**. No affirmative official support statement was located. This is not an explicit vendor declaration of non-support, nor proof that no alternative supported configuration exists. Seek written Microsoft/Databricks clarification before relying on any route.

**Current final-result category: 4 — Inconclusive (supportability).** Runtime evidence now exists for the tested configurations: private-only and NCC with bypass `None` failed; `AzureServices` succeeded; Enforced NSP with one inbound rule succeeded, its rule-removed negative control failed with `ForbiddenByNsp`, and restoring the rule succeeded. These results do not prove a customer-private-endpoint route or official support. The classic Key Vault selected-networks/IP test remains blocked because policy forces public access Disabled. Keep the overall feasibility classification inconclusive until written support guidance clarifies whether the requested private-only route is supported/configurable.

## Scope boundaries

| Feature | Documented purpose | Does it establish Managed Services CMK → customer Key Vault PE connectivity? |
| --- | --- | --- |
| VNet Injection | Classic compute NICs in customer host/container subnets | No; control plane is not injected |
| SCC / `enableNoPublicIp=true` | Outbound cluster-initiated control-plane connections; no public cluster NIC IPs | No |
| Front-end Private Link | Client/browser/API → workspace | No |
| Back-end/classic Private Link | Classic clusters → control-plane API/SCC relay | No; direction and caller differ |
| Key Vault Private Link | Routed client → vault data plane through private NIC | Only for clients with an actual network/DNS path |
| NCC private endpoints | Databricks serverless compute → customer resources | No documented applicability to managed-services key client; not in the original plan. **Now a user-requested test, see "NCC constraint" below** |
| Key Vault trusted-services bypass | Selected service scenarios may bypass the firewall, still subject to identity authorization | Not a customer Private Endpoint path and therefore does not satisfy the requested private-only target; separately tested as the approved `AzureServices` control |
| DBFS-root / managed-disk CMK | Other encryption surfaces | Different from Managed Services CMK; not substitutes |

## Documented details and constraints

- Premium is required for managed-services CMK and the proposed classic Private Link deployment.
- VNet and workspace must be in the same subscription and region. Two dedicated, equal-sized host/container subnets are required; use at least `/26`, delegate to `Microsoft.Databricks/workspaces`, and attach required NSGs **before** workspace deployment. No PEs or unrelated resources in these delegated subnets.
- Set `publicNetworkAccess=Disabled`, `requiredNsgRules=NoAzureDatabricksRules`, and `parameters.enableNoPublicIp.value=true` explicitly. Some linked instructions describe hybrid/public-access configurations; do **not** copy their public-enable steps into this experiment.
- `databricks_ui_api` serves both inbound and classic back-end connectivity. Browser SSO additionally needs `browser_authentication`. The draft uses a new isolated auth workspace rather than a pre-existing regional endpoint. Discover actual required DNS names from endpoint configuration; do not hardcode an assumed regional auth record ordering.
- Browser authentication can be shared regionally. Inspect existing DNS visibility/conflicts read-only; never reuse or overwrite an existing endpoint/zone. If the existing VM VNet already has a same-name private-zone link, stop and design isolated conditional forwarding with approval.
- PE subnet NSG enforcement, if enabled, needs required service ports: 443, 6666, 3306 and 8443–8451 per current concepts guidance. Never remove delegated service-managed rules or invent a blanket deny that breaks bootstrap.
- New VNets need explicit outbound connectivity. Back-end Private Link is **not** proof that package repositories, storage and all platform dependencies are private. A tightly controlled egress design remains a deployment blocker; a NAT gateway alone is not egress filtering.
- Managed-services CMK uses the AzureDatabricks enterprise application. Resolve its tenant-specific object ID read-only from the documented **public application ID** `2ff814a6-3304-4ab8-85cb-cd0e6f879c1d`; do not assume a workspace identity is interchangeable. The current enablement article also mentions a storage-account managed identity: verify exactly which identities apply and grant only required key scope permissions. Do not add DBFS/disk CMK merely to satisfy an example.
- Documented key permissions: `get`, `wrapKey`, `unwrapKey`; RBAC role `Key Vault Crypto Service Encryption User`. Key creator needs separately scoped temporary authoring rights, not Owner. Use a new enabled RSA software key and a pinned version, not `latest`.
- Key Vault must be in the same tenant; this lab additionally fixes it to Korea Central and the PoC subscription. RBAC, soft delete and purge protection are proposed; retention 7 days for the disposable lab, subject to policy.
- Managed-services CMK cannot be disabled after enablement. Existing content is not automatically re-encrypted. Key cache duration is unspecified; after rotation the old key must remain available for **24 hours**.
- Key Vault `publicNetworkAccess=Disabled` alone is insufficient to exclude trusted-service traffic: reviewed networking guidance says bypass can still apply. Require `bypass=None`, `defaultAction=Deny`, empty IP/VNet allowlists and no network-perimeter override. Public DNS/TLS visibility can remain; data-plane requests must be denied publicly.
- Key Vault network restrictions protect its **data plane**, not Azure Resource Manager management access. The objective cannot mean that ARM resource configuration becomes inaccessible over the management endpoint.
- Azure Databricks requires a service-managed RG separate from the customer RG. New service-managed compute/storage must be in Korea Central; if the provider introduces any other regional resource, stop and report it. Global service/identity metadata is not a regional workload resource.
- Purge protection prevents immediate permanent removal of a deleted vault. Resource-group deletion cannot promise zero soft-delete residue. No purge or existing-resource deletion is approved.

## Korea Central readiness matrix

| Requirement | Official evidence | Live subscription evidence | Gate |
| --- | --- | --- | --- |
| Azure Databricks in Korea Central | `koreacentral` appears in supported-regions list | Provider listed Korea Central; target and auth workspaces deployed there successfully | Regional deployment verified; exact CMK route support still needs vendor response |
| Premium + CMK + front/back-end/auth Private Link combination | Feature guides describe prerequisites; no KRC-specific combination guarantee established | Premium workspaces, PEs and CMK stages deployed; strict private-only route failed; NSP-based CMK passed functionally | Deployed combination observed; private-only CMK support remains unconfirmed |
| VNet/NSG/route/PE/Key Vault/Log Analytics | Azure services documented; no live regional eligibility checked | Required PoC regional resources deployed successfully in Korea Central | Deployment verifies this PoC combination, not all quota or production limits |
| Classic node SKU and capacity | No node SKU selected | Preflight found `Standard_D4s_v3` unrestricted and 8 regional vCPUs free; no classic cluster started | Classic-compute SKU/capacity and workload still require verification before cluster test |
| Firewall/explicit egress, DNS resolver if needed | Architecture options documented | Not obtained | Approve exact SKU, routes, required destinations and budget |
| Required provider registrations | Providers must be registered for deployed service types | Preflight found seven required providers registered | Satisfied for deployed resources; do not unregister shared providers |
| Existing VM peering/DNS compatibility | Azure supports global peering, explicit DNS links/forwarding | VM and network inspected; approved direct peerings and DNS links created; private reachability verified | Basic connectivity verified; effective routes/NSGs not re-inspected after changes; cleanup is approval-gated |

A provider location listing is a necessary check, not proof of SKU allocation, feature eligibility or capacity. No required feature may silently move to Korea South or any other region.

## NCC constraint and the NAT-IP alternative (2026-10-18)

Added after the control experiment, before any NCC or IP-allowlist change. Sources: [Serverless compute plane networking](https://learn.microsoft.com/en-us/azure/databricks/security/network/serverless-network-security/) (updated 2026-10-06), [Configure private connectivity to Azure resources](https://learn.microsoft.com/en-us/azure/databricks/security/network/serverless-network-security/serverless-private-link) (2026-10-08), [Manage private endpoint rules](https://learn.microsoft.com/en-us/azure/databricks/security/network/serverless-network-security/manage-private-endpoint-rules) (2026-10-09), [IP addresses and domains](https://learn.microsoft.com/en-us/azure/databricks/resources/ip-domain-region) (2026-10-16) and [Key Vault network security](https://learn.microsoft.com/en-us/azure/key-vault/general/network-security).

### NCC constraint: documented for serverless compute only

| Point | What Microsoft documents |
| --- | --- |
| Purpose | "Serverless network connectivity is managed with network connectivity configurations (NCCs)." NCCs are account-level regional constructs that create private endpoints for the **serverless compute plane** |
| Who can use it | "NCC private endpoints are supported from SQL warehouses, jobs, notebooks, Lakeflow pipelines, and model serving endpoints." The control plane's encryption service is not listed |
| Key Vault | Azure Key Vault **is** a supported destination resource for NCC private endpoint rules (sub-resource `vault`). That makes the test possible, but it is about serverless compute reaching the vault |
| Managed Services CMK | The workspace encryption settings take only a key vault URI, key name and pinned version (ARM schema and CMK page). No NCC field exists, and the CMK page does not mention NCC |
| Prerequisites | Premium plan, a Databricks **account admin**, NCC in the **same region** as the workspace. Limits: 10 NCCs per region, 100 private endpoint rules per region, 50 workspaces per NCC |
| Lifecycle | After attaching, wait about 10 minutes and restart serverless resources. Rule states: CREATING, PENDING (needs approval on the vault), ESTABLISHED, REJECTED, DISCONNECTED, EXPIRED (after 14 days in PENDING, REJECTED or DISCONNECTED), CREATE_FAILED |
| Cost | Private endpoint rules "are billed by Azure for each hour they exist, regardless of connection state"; delete the rule when finished (Databricks may keep the endpoint on the resource for one day) |

**What this means for the test.** A pass cannot be assumed and would be undocumented behavior. A failure is the expected result and would be consistent with the documentation. Even if an NCC rule reaches `ESTABLISHED`, it only shows a serverless path exists; it does not show that the control plane's key requests use it. The deciding evidence is successful `KeyGet`/`KeyUnwrap` with bypass `None` plus route evidence; neither a changed `CallerIpAddress` nor absence of the `TrustedService` label is sufficient by itself.

**Observed result of the NCC test (2026-10-18).** Failed: with an approved Databricks-created NCC connection on the vault and bypass `None`, the control plane's `KeyGet` was still denied with 403 `ForbiddenByConnection` from the same public address. See [results](results.md). **Correction:** the "no `TrustedService` label" criterion above is withdrawn; the label appeared on denied requests too.

### NSP outcome and negative/repeat control (2026-10-18)

The classic Key Vault selected-networks test could not be performed because a management-group modify policy kept `publicNetworkAccess` Disabled. The NSP association in Transition mode did not avoid that policy. With the vault association Enforced and one inbound rule for the observed control-plane address, CMK succeeded at bypass `None`. In CMK-NSP-03, removing only that rule caused a 403 `ForbiddenByNsp`; restoring it and applying another key version succeeded. This controlled A/B supports that the NSP rule admits the public control-plane request. Caveats: the phase-A vault audit row and NSP access-log correlation were unavailable, the NCC connection remained Approved as a confounder, and only one A/B cycle was performed. This is not a PE path, and vendor support remains unconfirmed. Full timestamps and final-state details are in [results](results.md).

### Reviewer proposal: allow the control plane NAT address on a selected-networks vault

> **Update 2026-10-18 — blocked in this subscription.** A tenant-level Azure Policy (`KeyVault_PublicNetwork_Modify`, effect `modify`) forces Key Vault `publicNetworkAccess` to `Disabled` on every write, so the selected-networks design could not be applied here. See [results](results.md). The assessment below is unchanged and remains untested.

A colleague proposed: if NCC does not work, use **Selected networks + Allow trusted services OFF + allow only the control plane NAT address**, with these reasons: (1) trusted-service bypass admits Azure datacenter traffic from any tenant, so disable it; (2) for audit, CMK can be justified by managing only known IP sources. They also suggested allowing the control plane IP inbound on 443 in the private endpoint subnet.

| Item | Assessment |
| --- | --- |
| Vault settings it implies | `publicNetworkAccess=Enabled` (portal: Enabled from selected virtual networks and IP addresses), `defaultAction=Deny`, `bypass=None`, one IP rule. Key Vault IP rules apply only while public network access is not Disabled, so this **ends the "public access Disabled" posture** the lab was built to prove. That is a deliberate deviation and needs explicit approval at the time |
| Address to allow | The address seen in our own audit log (`CallerIpAddress` on the Databricks `KeyGet`). Microsoft's published list names that address under the **East US 2** Control Plane NAT, not under Korea Central, so allowing the Korea Central NAT addresses would not have matched. Caveat: Microsoft says the NAT values apply when secure cluster connectivity is disabled, and this workspace has it enabled, so reading the table against this request is an observation, not a documented guarantee. The address is not written into these public documents; it stays in local evidence |
| Stability | Microsoft warns that control plane IP addresses change and that one NAT address is assigned to a workspace at creation. An allowlist needs a re-check process. Key Vault IP rules accept public IPv4 addresses and ranges, not service tags |
| Reason 1 ("trusted services admits any tenant") | Partly right as a network statement: the bypass is a firewall exception for listed Microsoft services. Not right as an access statement: Microsoft says bypassing services must still present a valid Microsoft Entra token and hold RBAC or access-policy permission, which is the tenant boundary. An IP allowlist of a Databricks NAT address is also not customer-specific (it is shared control plane egress, an inference from it being a NAT range), so RBAC remains the real control in both designs |
| Reason 2 (known IP sources for audit) | Reasonable as a governance argument: one named address is easier to explain than a service-wide exception, provided the address is monitored for change |
| PE subnet inbound 443 for the control plane IP | Not planned. A private endpoint has a private address and the control plane was observed reaching the vault's **public** endpoint, so a rule on the endpoint subnet is not expected to change that path. To be clarified with the colleague, not tested unless asked |

**Expected outcome (stated before testing):** with the address allowed and bypass `None`, the control plane's `KeyGet` and `KeyUnwrap` should succeed, with `IsAddressAuthorized=true`; the `TrustedService` label is not a discriminator because it also appeared on denied requests. **This classic selected-networks outcome remains untested** because the policy prevented public access from being Enabled. The NSP variant is separately tested above and is not the same configuration. Neither would prove private-endpoint-only access.

## Support questions (blocking primary objective)

1. Does Managed Services CMK support a Key Vault with public access disabled **and** bypass None, with every key operation going through an approved private endpoint?
2. If yes, what exact supported control-plane network object, DNS mechanism and API configure that route? Who owns the endpoint and in which RG/subscription/region is it created?
3. Is that configuration available for Premium classic VNet-injected workspaces in **koreacentral**? Are private-only bootstrap/update operations supported without transient public access?
4. Which tenant principals issue Get/Wrap/Unwrap requests, and which Key Vault log fields identify the private path? What cache/refresh behavior permits a conclusive test?
5. What is the required cleanup procedure and service-managed RG lifecycle for failed CMK configuration and workspace deletion?

## Official references reviewed

| ID | Source | Relevance |
| --- | --- | --- |
| S1 | [Enable Managed Services CMK](https://learn.microsoft.com/en-us/azure/databricks/security/keys/cmk-managed-services-azure/customer-managed-key-managed-services-azure) | Control-plane scope, identities, permissions, key settings, caching, rotation and irreversible enablement; page dated 2026-09-11 |
| S2 | [CMK overview](https://learn.microsoft.com/en-us/azure/databricks/security/keys/customer-managed-keys) | Distinguishes encryption surfaces |
| S3 | [VNet Injection](https://learn.microsoft.com/en-us/azure/databricks/security/network/classic/vnet-inject) | Delegation, subnet/NSG and outbound requirements; page dated 2026-10-09 |
| S4 | [Private Link concepts](https://learn.microsoft.com/en-us/azure/databricks/security/network/concepts/privatelink-concepts) | Traffic directions, endpoint types, topology, ports; page dated 2026-10-15 |
| S5 | [Inbound Private Link](https://learn.microsoft.com/en-us/azure/databricks/security/network/front-end/front-end-private-connect) | Browser auth workspace and private DNS; hybrid examples must not be copied blindly |
| S6 | [Classic back-end Private Link](https://learn.microsoft.com/en-us/azure/databricks/security/network/classic/private-link-standard) | Cluster/control-plane endpoint and runtime checks |
| S7 | [SCC](https://learn.microsoft.com/en-us/azure/databricks/security/network/classic/secure-cluster-connectivity) | No public cluster IPs and explicit egress |
| S8 | [NCC private connectivity](https://learn.microsoft.com/en-us/azure/databricks/security/network/serverless-network-security/serverless-private-link) | Serverless scope only |
| S9 | [Key Vault network security](https://learn.microsoft.com/en-us/azure/key-vault/general/network-security) | Public access, trusted-services bypass and data-plane boundary; page dated 2026-06-16 |
| S10 | [Key Vault Private Link](https://learn.microsoft.com/en-us/azure/key-vault/general/private-link-service) | PE approval, private DNS, public DNS visibility |
| S11 | [Key Vault trusted-services list](https://learn.microsoft.com/en-us/azure/key-vault/general/overview-vnet-service-endpoints#trusted-services) | Azure Databricks listing is not universal scenario authorization |
| S12 | [Supported regions](https://learn.microsoft.com/en-us/azure/databricks/resources/supported-regions) | Korea Central listing, not subscription eligibility |
| S13 | [Workspace ARM schema 2024-05-01](https://learn.microsoft.com/en-us/azure/templates/microsoft.databricks/2024-05-01/workspaces) | Workspace network fields and CMK object; no managed-services PE-route field |
| S14 | [PE DNS integration](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns-integration) | Peered VNet links and DNS forwarding |
| S15 | [VNet peering](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-peering-overview) | Cross-region peering; DNS not inherited |
| S16 | [Key Vault soft delete](https://learn.microsoft.com/en-us/azure/key-vault/general/soft-delete-overview) | Retention and purge-protection residuals |

Failed lookups retained in the journal: `/security/keys/customer-managed-keys-managed-services` and `/admin/delete-workspace` returned HTTP 404. No claim is based on those pages. Managed RG deletion behavior must be verified during approved cleanup rather than assumed from a broken link.
