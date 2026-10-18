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

No serverless data connectivity, DBFS-root CMK, disk CMK, public test VM or extra cluster pool is proposed in the original plan. A minimal classic cluster is a later short-lived validation workload, after KRC node SKU/quota/budget review. Prefer single-node if policy/runtime supports the required test, otherwise smallest approved topology with auto-termination. **NCC was not in the original plan; it was added as a user-requested test, see the staged plan below.**

## Staged plan after the control experiment (2026-10-18)

Written **before** any NCC or IP-allowlist change. **Execution status (updated 2026-10-18): Stage 0 done; Stage 1 executed and failed as expected; Stage 2 approved but BLOCKED by a management-group Azure Policy that forces Key Vault public network access to Disabled; Stage 3 pending the user's decision.** Each stage ends with evidence and a decision; a stage is not skipped because the previous one "should" fail.

| Stage | Action | Vault settings during the stage | Who | Evidence and pass criterion | Rollback |
| --- | --- | --- | --- | --- | --- |
| 0 | Update README, feasibility, plan, test plan, results (this change) | `publicNetworkAccess=Disabled`, bypass `None`, default Deny, no IP rules (restored 2026-10-18) | Assistant | Docs consistent with the audit and vault reads | None needed |
| 1 | **NCC test.** Create an NCC in the Databricks account console (Korea Central), attach it to the target workspace (wait about 10 minutes), add a private endpoint rule to the vault (sub-resource `vault`), approve the pending connection on the vault, wait for `ESTABLISHED`. Create a new key version over the VM's private endpoint and apply it with `Deploy-Poc.ps1 -Stage Cmk -KeyVersion <new> -VaultBypass None` | Unchanged from Stage 0 | **Databricks account admin** for the console steps; vault owner approves; assistant runs the deployment and reads the audit | Test CMK-NCC-01. Pass: `KeyGet` and `KeyUnwrap` return 200 with bypass `None`, `CallerIpAddress` no longer the control plane NAT address, no `TrustedService` label. Fail: same 403 `ForbiddenByConnection` | Delete the NCC private endpoint rule (it bills hourly while it exists) and detach the NCC. Vault is unchanged |
| 2 | **NAT IP allowlist test**, only if Stage 1 fails and you approve the deviation. Read the fresh `CallerIpAddress` from the Stage 1 failure, confirm it against Microsoft's control plane NAT list, then set the vault: public network access Enabled from selected networks, default action Deny, bypass `None`, one IP rule for that address. Re-run the CMK stage | `publicNetworkAccess=Enabled` (selected networks), `defaultAction=Deny`, bypass `None`, `ipRules=[<one address>]`, no VNet rules | Assistant (a new script that changes only these properties, logging before and after, will be added at that point) | Test CMK-IP-01. Pass: `KeyGet` and `KeyUnwrap` 200 with `IsAddressAuthorized=true`, no `TrustedService` label. Also test from an external network that the vault refuses other addresses | Set `publicNetworkAccess=Disabled` and remove the IP rule with the same script |
| 3 | Decide the final posture, restore Disabled and `None` unless you decide otherwise, update the classification and the support question | Per decision | You | Documented decision and the final vault read | Same script |

Rules that apply to every stage:

- The Key Vault setting changes are limited to the properties named in the table. Each change logs the vault's network settings before and after.
- Existing infrastructure outside the PoC resource group is not changed by these stages. The NCC lives in the Databricks account, not in Azure.
- Stage 2 is not started without your explicit go-ahead, because it ends the "public access Disabled" posture.
- The workspace carries the key already and keeps working on Databricks's cached key while the vault blocks the control plane; it may degrade when the cache expires (interval not documented). That is acceptable for these tests but is recorded as a risk.
- Any result, positive or negative, is recorded as observed. A pass in Stage 2 does not become "private endpoint only".

Approximate cost: NCC private endpoint rule is billed hourly by Azure while it exists (small; delete after the test). Stage 2 has no extra Azure resource cost.

### Stage 1 result and a correction (2026-10-18)

Stage 1 was executed. Result: **failed** (same 403 `ForbiddenByConnection`, same caller address, workspace `Failed` with its earlier key version). Details and limits are in [results](results.md). **Correction:** the pass criteria in the table above that mention "no `TrustedService` label" are withdrawn. The label appeared on the denied requests too. The discriminators are HTTP status 200 and `IsRbacAuthorized` / `IsAddressAuthorized`.

**Stage 2 approval and an implementation constraint.** The user approved Stage 2 after Stage 1 failed. The CMK stage redeploys the vault template, which previously hard-coded public access Disabled and no IP rules and would have undone the Stage 2 vault setting. The vault template now takes the public network access value and an allowed-address list as parameters (defaults keep the lab posture: Disabled, none), and a new script changes only those properties with a before/after log.

**Stage 2 outcome: blocked (2026-10-18).** The script added the IP rule, but public network access could not be set to Enabled: a management-group Azure Policy (`KeyVault_PublicNetwork_Modify`, effect `modify`) rewrites it to Disabled on every write, and three write paths all reported success while the value stayed Disabled. The vault was restored to the lab posture (verified: public Disabled, default Deny, bypass `None`, 0 IP rules). The CMK stage was not re-run. No exemption or governance change was attempted. Details are in [results](results.md).

**Recovery note.** The workspace is `Failed` with its earlier key version. A CMK-free Baseline redeploy is not a safe recovery now, because the workspace already has a managed-services key and the Baseline template sends no encryption block; its effect is untested. The known-good way to return the workspace to `Succeeded` is a successful CMK update.

### Stage 2b: network security perimeter (NSP), then the selected-networks IP test (2026-10-18)

Written **before** execution. Stage 2 was blocked by the management-group policy `KeyVault_PublicNetwork_Modify`, whose display name says it excludes Key Vaults configured with an NSP. The user asked to try NSP first and then the selected-networks test.

**What Microsoft documents** (NSP concepts page updated 2026-10-02; Key Vault network security page updated 2026-06-16; NSP CLI quickstart):

- Key Vault is an NSP-supported resource (generally available). The perimeter, a profile, an access rule and a resource association are separate resources.
- Two access modes. **Transition** (the default, formerly Learning) only logs traffic that would have been denied. **Enforced** denies all traffic except intra-perimeter traffic and traffic allowed by an access rule. For Key Vault, in Enforced mode the `publicNetworkAccess` setting "is overridden by the network security perimeter rules".
- **Private endpoint traffic is not subject to NSP rules**, so the VM's private path to the vault keeps working.
- Inbound access rules can be public IP address prefixes or subscriptions. Key Vault has no outbound concept.
- "Switching Public Network Access to Secure by perimeter, then forbids trusted services even if configured to allow trusted services."
- Audit logs: for PaaS resource logs use a Log Analytics workspace in the **same perimeter**. A workspace in Enforced mode would block queries from this VM's public address, so the workspace is associated in **Transition** mode only.
- Removing an association while `publicNetworkAccess` is `SecuredByPerimeter` locks the resource down.
- The Azure CLI needs the `nsp` extension (`az network perimeter ...`).

| Step | Action | Vault state | Expected outcome (stated in advance) | Rollback |
| --- | --- | --- | --- | --- |
| B1 | Create the perimeter and a profile; associate the vault **and** the Log Analytics workspace in **Transition** mode. Read the vault. Then attempt to set public network access Enabled again | bypass `None`, default Deny | Unknown whether the policy treats a Transition-mode association as NSP-configured. Observe: does the vault's `publicNetworkAccess` change, and does an Enabled write now stick? | Delete the associations, profile and perimeter |
| B2 | **Selected networks test (the user's second request).** If B1 let public access become Enabled: vault public network access Enabled for selected networks, default Deny, bypass `None`, one IP rule for the control plane address from the audit log; re-run `-Stage Cmk` with `-VaultBypass None -VaultPublicNetworkAccess Enabled -VaultAllowedIps <address>` | As stated | If Enabled sticks, the control plane request should be admitted by the IP rule: `KeyGet`/`KeyUnwrap` 200 with `IsAddressAuthorized=true`. That would be a pass for a selected-networks variant, never for private-endpoint-only | `Set-VaultIpAllowlist.ps1 -Restore`, then remove the perimeter |
| B3 | Only if B1 did not let public access become Enabled: **NSP-native variant.** Add an NSP inbound access rule for the same address and switch the vault association to **Enforced**; re-run the CMK stage | Vault association Enforced, workspace association stays Transition | Uncertain. The docs say Enforced overrides the public access setting, but the Key Vault page ties perimeter control to `SecuredByPerimeter`. Whether a vault left at `Disabled` honors the NSP rule is exactly what this step tests | Switch the association back to Transition and delete the perimeter |

**Risks.** The vault is reachable from one shared Databricks control plane address during the tests; RBAC remains the real boundary and the window is short. A failed CMK update leaves the workspace `Failed` with its earlier key version (a successful update would also return it to `Succeeded`). Enforcing on the vault could hide the vault's diagnostic logs if the workspace were not in the perimeter, which is why it is associated.

**Limits of what B2 and B3 can show.** Both depend on the address staying the same; Microsoft warns that control plane addresses change. A pass is evidence for that address at that time.

### Stage 1 runbook (NCC test)

Placeholders: `<vault resource ID>` is the PoC vault's Azure resource ID (read it with `az keyvault list -g <PoC resource group> --query "[0].id" -o tsv`); `<workspace>` is the target workspace. Identifiers are kept in local evidence, not in this repository.

**Baseline captured before any NCC change (2026-10-18 08:17 UTC, [Get-NccTestStatus.ps1](../scripts/validate/Get-NccTestStatus.ps1)).** Vault: public access Disabled, bypass `None`, default Deny, 0 IP rules. Vault connections: only our two endpoints, both Approved, no foreign connection. Target workspace: `Succeeded`, public access Disabled, CMK applied. Last control-plane key requests: 2026-10-18 06:50 UTC, four requests, all 200, trusted service `AzureDatabricks` (from the control experiment). No control-plane key request since the bypass was restored.

#### Part A \u2014 Databricks account admin (account console, cannot be automated from Azure)

1. Sign in at the Azure Databricks account console (`accounts.azuredatabricks.net`) with a Microsoft Entra account that is a Databricks **account admin**. If no one has the role, an Entra Global Administrator can sign in first and then grant it. If you cannot sign in, stop and report; do not use another account.
2. **Create the NCC.** Security \u2192 Network connectivity configurations \u2192 Add network configuration. Name: `ncc-dbxcmk-krc-test`. Region: **Korea Central**. If Korea Central is not offered, stop and report; do not choose another region. Select Add.
3. **Attach the NCC to the target workspace.** Workspaces \u2192 the target workspace (its numeric workspace ID is in the workspace URL `adb-<id>.<n>.azuredatabricks.net`) \u2192 Update workspace \u2192 Network connectivity configurations \u2192 select the NCC \u2192 Update. If the NCC is not listed, confirm that the workspace and the NCC are in the same region.
4. Wait about 10 minutes for the attachment to take effect.
5. **Add the private endpoint rule.** Open the NCC \u2192 Private endpoint rules \u2192 Add private endpoint rule. Destination Azure resource ID: `<vault resource ID>`. Azure subresource ID: `vault`. Select Add. The rule shows `CREATING`, then `PENDING`.
6. Tell the assistant when the rule shows `PENDING`.

#### Part B \u2014 vault owner (Azure; can be done by the assistant on request)

- **Step 7.** Azure portal \u2192 the Key Vault \u2192 Networking \u2192 Private endpoint connections \u2192 Private access tab. A new connection created by Databricks should appear as **Pending**. Select it \u2192 Approve. Alternatively ask the assistant to run `./scripts/validate/Get-NccTestStatus.ps1` to see the connection name, then `./scripts/deploy/Approve-VaultConnection.ps1 -ConnectionName <name>`. The script approves only the named, currently Pending connection and refuses our own endpoints.
- **Step 8.** Back in the account console, refresh the NCC until the rule shows `ESTABLISHED`. If it shows `REJECTED`, `DISCONNECTED`, `EXPIRED` (14 days) or `CREATE_FAILED`, record the state and the error text and stop.

#### Part C \u2014 assistant (the test itself, vault still bypass `None` and public Disabled)

- **Step 9.** Record the current key version, then create a new key version over the VM's private endpoint: `Copy-Item .local/deploy/key.json .local/deploy/key-before-ncc.json; ./scripts/deploy/New-CmkKey.ps1`. The old version stays in the vault and must not be deleted for 24 hours.
- **Step 10.** Apply the new version with the vault bypass left at `None`: `$kv = (Get-Content -Raw .local/deploy/key.json | ConvertFrom-Json).KeyVersion; ./scripts/deploy/Deploy-Poc.ps1 -Stage Cmk -KeyVersion $kv -VaultBypass None`. The workspace update has taken a long time in earlier runs (duration not measured).
- **Step 11.** Read the result with `./scripts/validate/Get-NccTestStatus.ps1 -SinceUtc <time of step 10>` and record it as test CMK-NCC-01.

**Interpretation, decided in advance.**

- **Pass:** the update succeeds with bypass `None` and the audit shows `KeyGet` and `KeyUnwrap` 200 with no `TrustedService` label and a changed caller address. That would be undocumented behavior and needs vendor confirmation before anyone relies on it.
- **Fail:** the same 403 `ForbiddenByConnection` and `IsRbacAuthorized` empty. NCC does not carry the control plane's CMK requests. This is the expected result.
- **Not conclusive:** the rule never reaches `ESTABLISHED`, or the update fails for a different reason. Record the exact error.

**Risk.** A failed update leaves the workspace in provisioning state `Failed`. The workspace keeps its existing key version, and a Baseline redeploy (no CMK change) is the known way to recover it. While the vault blocks the control plane, the workspace runs on Databricks's cached key and may degrade when the cache expires (interval not documented).

**Rollback after the test.** Delete the NCC private endpoint rule (Azure keeps billing it hourly while it exists), then detach or delete the NCC. Reject or delete the corresponding connection on the vault if it remains. Databricks may keep the endpoint on the vault for one day after the rule is removed. Re-run `Get-NccTestStatus.ps1` and confirm the vault is back to only our two connections.

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
