# Proposed deployment plan — approval required

**Phase 1 deliverable, not an approved Phase 2 deployment.** No Azure writes executed. All regional resources and RG deployment metadata must explicitly use **koreacentral**; global DNS resources use their supported global scope. Required-feature unavailability means **stop**, not region substitution.

**Status 2026-10-18:** this plan was executed with deviations (NAT gateway instead of a firewall, no peerings yet, vault endpoint placement, a VM-side vault endpoint, key created privately). The authoritative record is the [deployment guide](deployment-guide.md) and [inventory](resource-inventory.md); this document is the original plan.

**Follow-up authorization, 2026-10-17:** the user now explicitly requests resource creation. Treat this as authorization for new PoC resources once mandatory prerequisites pass, not as resolution of the documented open design/support questions. The draft remains not deployment-ready: assistant terminal execution fails, live Azure context/VM/KRC eligibility is unknown and the managed-services CMK private-only path remains unresolved. No existing-network change, cleanup, publication or public-access workaround is authorized by this general creation request.

## Decision requested after blockers are resolved

Choose one of these later, not implicitly:

1. **Recommended now: research/support hold.** Finish read-only preflight and obtain a supported Managed Services CMK private-only configuration before incurring costs.
2. **Optional separately approved experiment:** deploy the private workspace baseline and attempt CMK under the exact restrictive vault settings, expecting that configuration may fail. This can demonstrate failure/limitations; it cannot establish official support. Never enable bypass/public access to rescue the test. Stop at failure, preserve evidence, and ask before a changed experiment.

Approval must acknowledge two Databricks managed RGs and soft-deleted vault retention. If immediate permanent removal through one RG alone is non-negotiable, **do not deploy**: Azure's managed-resource placement and purge protection cannot satisfy that literally.

## Names and public-repository policy

Pattern: `<type>-dbxcmk-krc-<run>`; vault: `kvdbxcmkkrc<random>` (3–24 characters, globally unique). These are templates, not actual resources. Use a fresh non-identifying random run suffix. Proposed tags: `project=dbx-cmk-private-poc`, `environment=poc`, `region=koreacentral`, `run=<random>`, `managedBy=iac`, `expiresOn=<approved-date>`; no personal/customer names. Apply tags where supported; record untaggable child resources by resource ID in ignored local manifest.

Maintain actual subscription/tenant/VM IDs, CIDRs, endpoint addresses, principal IDs, key versions and names only in ignored local configuration/evidence. Public docs use sanitized aliases and subnet prefix sizes. Actual deployed configuration remains human-readable in ignored local reports; never publish raw internal configurations.

## Resource proposal

All operator-created resources below go in **one fresh RG**, `rg-dbxcmk-krc-<run>`, with location `koreacentral`. No reuse of existing PoC RGs/resources merely because names match.

| Resource | Proposed configuration | Depends on |
| --- | --- | --- |
| Customer RG | New; KRC; ownership tags/run manifest | Subscription creation rights/policy approval |
| Workspace VNet | New KRC VNet, locally supplied nonoverlapping CIDR | Reviewed address plan |
| Workspace host + container subnets | Two equal `/26` minimum; new workspace NSG; delegate `Microsoft.Databricks/workspaces` | VNet, NSG and route tables |
| Workspace PE subnet | New `/27`, not delegated; network-policy mode explicit | VNet; NSG requirements if enforcing PE policies |
| Transit/auth VNet | New KRC VNet; separate nonoverlapping CIDR | Reviewed address plan |
| Auth host + container subnets | Two equal `/26`, delegated; new auth NSG and route tables | Transit VNet and auth NSG |
| Transit PE subnet | New `/26`, not delegated; auth and vault PEs | Transit VNet |
| Route tables | New per host/container subnet or shared per workspace if compatible; no guessed next hops | Explicit egress/bootstrap design |
| Explicit egress | Prefer new filtered firewall design in PoC RG; dedicated required subnet(s); public egress IP only if approved; KRC | Regional SKU/allowlist/budget review; no inbound workspace/vault public access |
| Target Databricks workspace | Premium; custom VNet/subnet references; SCC true; PNA Disabled; `NoAzureDatabricksRules` | Fully provisioned network, NSGs, routes |
| Auth-only Databricks workspace | New Premium, same private-only flags; no compute, notebooks or unrelated endpoints | Transit delegated subnets/NSG/routes |
| UI/API PE | `databricks_ui_api` in workspace PE subnet; serves **both front-end and back-end roles** | Target workspace; private-link group support/approval |
| Browser-auth PE | `browser_authentication` targeting new auth-only workspace; transit PE subnet | Auth workspace and regional auth compatibility |
| Databricks private zone | New `privatelink.azuredatabricks.net`, one authoritative lab zone; PE-derived records | PE DNS metadata; VNet links |
| Key Vault | Standard, RBAC, RSA software CMK, purge protection, soft-delete retention proposed 7 days; PNA Disabled, bypass None, default Deny, no allowlists | Network/private client path and tenant |
| Vault PE + private zone | New `vault` PE; new `privatelink.vaultcore.azure.net`; both new-zone VNet links as needed | Vault, transit PE subnet |
| Log Analytics | New KRC LAW, `PerGB2018`, retention 30 days proposed, ingest budget/alerts reviewed | RG, SKU/policy readiness |
| Diagnostic setting | Key Vault `AuditEvent`, resource-specific logs where supported; LAW sink | Vault + LAW; enable **before** CMK attempt |
| Key authoring permissions | Temporary least-privilege key creation role scoped to new vault/key as supported | Approved operator identity and RBAC grant authority |
| CMK authorization | Documented enterprise application and only additionally proven necessary identities; `get/wrapKey/unwrapKey` or scoped encryption-user role | Confirmed principals, new vault/key |
| VM connectivity | Two direct peering pairs; DNS link/conditional forwarder changes | Separate existing-network approval, no address overlap |
| Optional new DNS resolver | KRC; dedicated `/28` or larger nondelegation-conflicting inbound subnet with required resolver delegation; only if VM uses custom DNS | Resolver SKU/budget; exact approved forwarding delta |
| Databricks managed RGs | One service-created RG per target/auth workspace; new, provider-owned; regional resources KRC | Workspaces; exception to customer RG boundary |

No NCC, serverless data connectivity, DBFS-root CMK, disk CMK, public test VM or extra cluster pool is proposed. A minimal classic cluster is a later short-lived validation workload, after KRC node SKU/quota/budget review. Prefer single-node if policy/runtime supports the required test, otherwise smallest approved topology with auto-termination.

## Required workspace ARM/Bicep property contract

Use the documented stable `Microsoft.Databricks/workspaces@2024-05-01` schema if still supported in the subscription; verify before pinning implementation. Explicitly set:

| Property | Intended value |
| --- | --- |
| `location` | `koreacentral` |
| `sku.name` | `premium` |
| `properties.managedResourceGroupId` | New, reserved service-managed RG ID; never an existing RG |
| `properties.parameters.customVirtualNetworkId.value` | New matching VNet ID |
| `properties.parameters.customPublicSubnetName.value` | New host subnet name (legacy public label; SCC prevents public node IPs) |
| `properties.parameters.customPrivateSubnetName.value` | New container subnet name |
| `properties.parameters.enableNoPublicIp.value` | `true` |
| `properties.publicNetworkAccess` | `Disabled` from initial creation |
| `properties.requiredNsgRules` | `NoAzureDatabricksRules` |
| `properties.encryption.entities.managedServices.keySource` | `Microsoft.Keyvault`, **only at approved CMK attempt** |
| `...managedServices.keyVaultProperties.keyVaultUri` | New vault URI, local-only actual value |
| `...keyName`, `...keyVersion` | New RSA key and exact version, not `latest` |

No field in this object selects a CMK Private Endpoint route. Setting a vault URI does not establish network connectivity. Always preserve networking settings on workspace updates.

## Dependency order and checkpoints

1. **Preflight hold:** restore terminal, identify existing VM, verify tenant/subscription/read/write scopes, registered providers, policy, KRC combination availability, quotas, exact CIDRs, auth DNS conflicts and cleanup exceptions. Obtain plan approval and separate scoped network-change approval. Do not auto-register providers.
2. **RG/network stage:** create dedicated RG and ownership manifest. Create both new VNets, all required subnets, NSGs, route tables, explicit egress and global private DNS zones. Verify state/delegation/NSGs/routes/region **before** creating workspaces. Snapshot only newly created ownership records.
3. **Workspace stage:** create target and auth workspaces with PNA disabled and SCC enabled from the first request. New managed RG names are reserved and checked absent beforehand. Workspaces may be temporarily inaccessible until PEs exist; that is expected and not a reason to enable public access.
4. **PE stage:** query target Private Link group IDs/required DNS names; create/approve shared UI/API and browser-auth endpoints. Verify Approved/Succeeded, actual NIC private IPs and authoritative private records.
5. **Approved connectivity stage:** create the new-side and explicitly approved existing-side peering children, with no gateway transit. Add approved DNS links/forwarders, verify both directions Connected and existing baseline unaffected. No VM relocation/restart/adapter change.
6. **Vault/logging stage:** create vault with public disabled/bypass None from initial creation; create vault PE/DNS, LAW, AuditEvent setting; verify private administration from VM. Create RSA CMK through private data-plane connectivity only after authoring rights propagate. Capture exact local config and key version without key material.
7. **Baseline validation checkpoint:** prove authenticated private workspace API/TLS access and classic cluster back-end behavior independently. Prove workspace/vault public data-plane denials with an approved existing external client if available. Never create that client or change existing external infrastructure implicitly.
8. **CMK checkpoint:** only after supported-route confirmation **or explicit negative-experiment approval**, grant reviewed least-privilege crypto rights and apply managed-services CMK fields. Record ARM result, bounded retries/propagation waits and complete diagnostic evidence. Preserve fail-closed settings and stop on network errors. No rollback to public/bypass as a workaround.
9. **Report hold:** classify support/runtime findings separately. Keep old key available 24 hours if rotating, and collect asynchronous/cache-aware evidence. Ask before cleanup or publication.

Every stage must update dashboard, progress, guide, inventory and journal immediately. No stage is marked complete until its state checks pass. Failed deployment does not trigger automatic cleanup.

## Existing-infrastructure changes needing explicit approval

| Change | Ownership/location | Risk | Planned rollback |
| --- | --- | --- | --- |
| Existing VNet → new workspace VNet peering child | Existing VNet's RG and original region | Broader connectivity; route effects | Delete only new named child; compare baseline |
| Existing VNet → new transit VNet peering child | Existing VNet's RG and original region | Same; global peering charges if cross-region | Delete only new named child |
| New PoC private-zone links to existing VNet | Link resources in PoC RG, target existing VNet | Changes DNS view, possible existing workspace name shadowing | Delete only new links; re-test baseline |
| Conditional forwarders, if custom DNS | Existing resolver scope, not yet identified | Shared DNS effects | Restore exact approved delta, not whole config |
| Existing NSG/UDR/proxy/firewall changes, only if needed | Existing owners | May affect other workloads | **Not currently proposed/approved**; enumerate rule-level delta first |

New resources attached to existing infrastructure still count as affecting it. Deleting the PoC RG does not remove the existing-side peering children automatically as an assured cleanup guarantee. No read-only inspection result or approval currently exists for these changes.

## Approximate cost envelope (USD, planning only)

No live KRC price quote obtained. These rough magnitudes are not a budget commitment; use the [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/) and actual agreement rates before approval. Assumes 730 h/month; compute mostly off.

| Item | Rough order of magnitude | Notes |
| --- | --- | --- |
| Three private endpoints | About $22/month if illustrative $0.01/endpoint-hour | KRC rate/data processing must be checked; shared UI/API role does not double endpoint count |
| Two private DNS zones | About $1/month plus queries | Global DNS billing |
| Standard Key Vault software operations | Usually cents–low dollars for small PoC | Transactions/logging; no HSM reserved cost proposed |
| LAW | Roughly $3–5/GB ingest assumption | Regional rates/retention/alerts can differ |
| Explicit filtered firewall | Often hundreds to >$1,000/month if always on | SKU determines cost; optional fallback NAT ~$30–50/month is **not** equivalent filtering or preapproved |
| Optional DNS Private Resolver inbound | Often low hundreds/month | Add only for demonstrated custom-DNS need; obtain quote |
| Short-lived classic compute | VM + Premium DBU hourly charges | Selected node type/count/runtime unknown; quote after KRC SKU check; auto-terminate |
| Peering/egress/storage/public egress IP | Usage-based, plus managed storage/disks | Cross-region VM peering may cost more; no assumed free service |

Illustrative three-day network baseline: endpoints about $2.16 plus small DNS/vault/LAW charges; firewall may add tens to >$100, resolver tens, and compute/transfer additional. A minimal no-firewall baseline is cheaper but does not meet strict outbound isolation without a separately approved dependency design. No spend is currently authorized.

## Future reproducibility deliverables (not yet implemented)

Pinned modules for networking, workspaces, endpoints/DNS, vault/diagnostics, scoped RBAC and separately approved peerings; ignored local parameter template; approval-enforcing deploy orchestration; state/API/CMK validators; manifest-based cleanup. Use `az deployment group what-if` only after templates exist and preflight review (it invokes server-side evaluation; do not confuse it with offline lint). Exact tested provisioning commands will be recorded in the actual deployment guide, not fabricated in Phase 1.
