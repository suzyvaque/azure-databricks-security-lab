# Deployment walkthrough and actual execution record

> **Final follow-up completed (2026-10-19 local date):** owner-approved PoC NSP deletion verified. CMK retried with public Disabled / bypass `None` / Deny and one stored control-plane vault IP rule; the new-version update failed with 403 `ForbiddenByConnection` at 2026-10-18 23:54 UTC. Workspace provisioning now `Failed`, prior CMK retained. The earlier successful NSP state below is historical. A stored IP rule does not grant public access with PNA Disabled. No public-enable write, bypass change, automatic recovery or wider cleanup was performed.

## Initial Phase 1 chronology (historical)

The entries in this table predate Azure deployment and describe the initial read-only phase. They are retained as history; the actual deployment record and latest state follow.

| Step | What / why | How | Actual values / dependencies | Verification / outcome |
| --- | --- | --- | --- | --- |
| 1 | Read initial project so work stays in existing repository | Editor file read/list | README and Git directory existed | Verified through file access; Git status/history not executed |
| 2 | Attempt environment inspection before architecture choices | Two foreground read-only terminal requests | CLI/Git/clock checks; no credentials requested | Only prompt returned; no executed-command evidence |
| 3 | Review official architecture before spending | Microsoft Learn retrieval and read-only research | References in feasibility document | Control-plane CMK route not documented; no runtime inference |
| 4 | Start learning/safety records immediately | Local editor file edits | Dashboard, progress, journal, ignore rules and proposal | Files exist; no Azure resources created |
| 5 | Prepare reproducible read-only inspection | Authored preflight PowerShell script | Location accepts only koreacentral; explicit optional VM ID; ignored local evidence | Not executed; terminal blocker persists |
| 6 | Diagnose terminal without Azure calls | Background harmless marker/clock request | No Azure commands | Repeated prompts, no marker/time; background terminal successfully terminated |
| 7 | Respond to authorization to create new resources | Acknowledged new-resource approval; inspected manually run CLI help; attempted terminal check and standalone account-state query | No IDs/tokens requested for console output; only read-only checks | CLI presence confirmed from manual help, but assistant requests still return prompts; login and KRC prerequisites unknown; no provisioning |

These are the Phase 1 steps. The actual deployment record follows the table below. The later "Future walkthrough" table is the original plan; where it differs from the record, the record is correct.

## Actual deployment record (2026-10-17 to 2026-10-18)

| Step | What and why | How | Key values | Dependencies | Verification |
| --- | --- | --- | --- | --- | --- |
| D1 | Create the isolation boundary: one new resource group in Korea Central | `Deploy-Poc.ps1` (`az group create`), tagged | Run ID and non-overlapping /24 ranges chosen automatically from 10.200-250.x.x and saved to ignored local state | Login; no existing group reused | Group exists in koreacentral with the run tag |
| D2 | Network first: two VNets, delegated subnets, NSGs, NAT gateway | `infra/modules/network.bicep` | Workspace VNet: host and container /26 delegated to `Microsoft.Databricks/workspaces`, PE /27. Transit VNet: auth subnets /27, PE /26. New VNets have no default outbound access, so a NAT gateway provides explicit outbound | None | Module Succeeded; delegation and NSGs attached |
| D3 | Key Vault locked down from creation, plus logging | `infra/modules/keyvault.bicep` | Public access Disabled, bypass None, default Deny, RBAC, purge protection, 7-day soft delete; AuditEvent to a new Log Analytics workspace | None | Module Succeeded. **The first attempt failed** because creating the key through ARM was refused by the private-only vault (observation O-1). The key was removed from the template |
| D4 | Two private-only workspaces, deployed only after the network exists | `infra/modules/workspaces.bicep` | Premium; custom VNet and subnet names; `enableNoPublicIp=true`; public access Disabled; `NoAzureDatabricksRules`; target has no CMK yet | D2 | Both `Succeeded`; properties read back |
| D5 | Private endpoints and DNS | `infra/modules/privatelink.bicep` | One `databricks_ui_api` endpoint (front-end and back-end roles), one `browser_authentication` endpoint, one vault endpoint in the workspace VNet; zones linked to both new VNets | D2, D3, D4 | All Approved/Succeeded |
| D6 | **Redeploy failed** with `ConflictWithNetworkIntentPolicy` | Found in the deploy output | Once the workspace exists, Databricks attaches network intent policies that require three outbound rules; my template re-applied the NSGs without them | D2 | Fixed by adding the SQL 3306, Storage 443 and EventHub 9093 rules to both NSGs; the network module then succeeded |
| D7 | Private path for this VM to the vault (requested by the user) | `infra/modules/vmaccess.bicep` | Endpoint in the VM's existing subnet; a vault-specific private DNS zone linked only to the VM's VNet, so no peering and no multi-IP DNS | D3 | Endpoint Approved; vault name resolves to a private address from the VM |
| D8 | Create the CMK key over the private path | `scripts/deploy/New-CmkKey.ps1` | Requires a private DNS answer first; grants Key Vault Crypto Officer on this vault only; creates an RSA 2048 software key | D7; RBAC propagation | Key created and enabled; version saved to ignored local state |
| D9 | Verify vault state | `scripts/validate/Get-VaultStatus.ps1` | Reads network flags, endpoint states, DNS privacy from the VM, key enablement | D8 | Public Disabled, bypass None, both endpoints Approved, DNS private, key enabled |
| D10 | Peer the existing VM VNet with both new VNets and link the Databricks private DNS zone | `scripts/deploy/Connect-VmPeering.ps1` | Two direct peering pairs; no gateway transit or forwarded traffic; no VM/NIC/NSG/route edits | Explicit user approval | Four peering resources Connected; private DNS zone link created |
| D11 | Validate VM private reachability | `scripts/validate/Test-WorkspaceConnectivity.ps1` | Workspace and browser-auth hostnames; DNS, TCP, TLS and HTTPS checks | D10 | Both resolve/connect privately; TLS validates; HTTPS returns 303 to sign-in. Authenticated API and actual browser login not tested |
| D12 | Run Managed Services CMK and network-policy experiments | `scripts/deploy/Deploy-Poc.ps1 -Stage Cmk`, audit queries, bypass/IP/NSP scripts | Bypass comparison, NCC attempt, policy-blocked selected-networks attempt, Enforced NSP and CMK-NSP-03 A/B; details in [results](results.md) | Key created through VM PE; correct AzureDatabricks crypto role; user approvals recorded | Final workspace `Succeeded` with CMK; final vault PNA Disabled, bypass None, Deny, no Key Vault IP rules; Enforced NSP association with one inbound rule. A without rule failed `ForbiddenByNsp`; B with rule succeeded. Public control-plane path, not PE |

### Concepts shown by this record

- **Network intent policy:** Databricks attaches rules to the delegated subnets after the workspace exists. A later deployment that rewrites the NSG must keep those rules.
- **Private-only vault and ARM:** with public access disabled and bypass None, even Azure Resource Manager cannot create a key. Key authoring needs a client with a private path.
- **Vault-specific DNS zone:** a zone named `<vault>.privatelink.vaultcore.azure.net` linked to one VNet makes that VNet resolve the vault to its own endpoint, while the shared zone serves the other VNets. The most specific zone wins.

### Current work remaining

Authenticated API access and browser sign-in from the VM; classic-cluster/back-end Private Link; external-network public-denial tests; verify Databricks-managed resource group locations; ask Microsoft/Databricks about Managed Services CMK private/NSP support; delete the account-level NCC rule when approved; decide to retain or safely remove the NSP; secret/history review and local commit; approved cleanup. The classic selected-networks test remains blocked by the management-group modify policy. See [results](results.md) and [progress](progress.md).

## Concept primer

- **VNet Injection:** classic compute runs in your newly created host/container subnets. It does not move the managed control plane into your network. “Public subnet” is a legacy host-subnet label; SCC keeps node NICs private.
- **Subnet delegation:** grants the Databricks service authority to manage required subnet integration/NSG rules. Reserve both subnets for one workspace.
- **Private Endpoint:** a private NIC for access **to** a specific supported service subresource. It does not give arbitrary service code a reverse route **from** that service to your VNet.
- **Front-end vs back-end:** front-end is VM/browser/API client→Databricks; back-end is classic cluster→control plane/SCC relay. The proposed shared `databricks_ui_api` PE serves both roles; tests must prove each role independently.
- **Private DNS:** maps the normal service hostname to the endpoint's private IP in linked networks while preserving TLS hostname checks. DNS resolution is not a packet-path or authenticated-access proof.
- **Peering:** direct private routes between two VNets, potentially across regions. It is directional in configuration and nontransitive. It does not copy DNS settings. Existing VNet peering children require approval.
- **CMK encryption:** authorization and network reachability are separate. A crypto role cannot override a network denial; a PE cannot grant identity permissions. Service key caching complicates runtime proof.

## Original planned walkthrough (reference; superseded where executed)

| Order | What and why | Intended method / key configuration | Dependencies | Required verification |
| --- | --- | --- | --- | --- |
| A | Establish subscription/VM/KRC feasibility | Read-only preflight and manual DNS/policy/support review | Working terminal, locally supplied VM ID | No unresolved mandatory feature, permission, quota or route gap |
| B | Create new isolation boundary | Future approved orchestration; RG location koreacentral; ownership tags | Plan approval; fresh RG name | RG existence/location and recorded ownership, no existing-name takeover |
| C | Create both new VNets and dependencies first | Future Bicep network module; two delegated `/26` subnets per workspace, separate PE subnets; new NSGs/routes | Nonoverlap review, explicit egress allowlist/SKU approval | All subnets/NSGs/routes provisioned before workspace PUT |
| D | Create target and auth workspaces | Future Bicep using workspace property contract in deployment plan | Stage C passed | Premium, correct custom VNet/subnet IDs, SCC true, PNA Disabled, NoAzureDatabricksRules, only KRC regional resources |
| E | Create/approve PEs and DNS | UI/API shared PE, browser-auth PE; new zone; derive DNS metadata from resources | New workspaces; exact private-link groups supported | Approved/Succeeded; correct IPs, workspace/relay/auth records |
| F | Connect existing VM safely | Two direct peering pairs plus new-zone links or approved custom-DNS forwarding | Explicit rule-level existing-network approval | Both pairs Connected; expected effective routes; original infrastructure intact |
| G | Create vault, PE, diagnostics and RSA key | Future vault/observability modules; PNA Disabled, bypass None, RBAC, purge protection; create key from VM through PE | Private client path; temporary least-privilege authoring rights | Vault config snapshot, authenticated private key admin, audit ingestion before CMK |
| H | Validate private workspace baseline | Future validators: DNS, TCP/TLS peer IP, authenticated API, browser SSO and classic workload | Private DNS/path; authorized identity; approved compute budget | Runtime evidence for each source role, not DNS alone |
| I | Attempt Managed Services CMK | Pinned URI/name/version update only after route support or negative-test approval | Exact crypto principals, logs and strict network policy verified | Get/Wrap/Unwrap attribution and path evidence, or explicit recorded failure |
| J | Validate public denials / negative controls | External approved test client; bounded disposable key/RBAC tests | No production changes; separate disruptive-test permission | Network-specific denial, not mere 401 or timeout; private path remains healthy |
| K | Report, then optionally clean up | Human-reviewed classification and manifest-based future cleanup script | Separate cleanup approval | RG/managed-RG/cross-boundary checks; vault-retention residue documented |

## Command and script references

- Exact read-only CLI argument arrays: [Invoke-ReadOnlyPreflight.ps1](../scripts/validate/Invoke-ReadOnlyPreflight.ps1).
- Intended ARM properties and dependency ordering: [deployment plan](deployment-plan.md).
- Infrastructure templates and deployment commands are implemented under `infra/` and `scripts/deploy/` and were used for the PoC. Cleanup has a documented approval-gated procedure but no executable cleanup automation. See the execution record above; do not substitute the original planned walkthrough for as-built state.
- Actual configuration values/raw evidence live under ignored local storage. This guide and related documents summarize sanitized outcomes; never copy raw evidence here.

## Initial terminal troubleshooting (resolved)

During the initial read-only phase, terminal requests returned prompts without command output. The user later confirmed login and restored a working PowerShell extension/terminal; preflight and authorized Azure operations then ran successfully. This historical blocker is resolved and is not the current state. The existing VM was identified and inspected read-only before peering approval. The CMK documentation URL correction remains recorded in the feasibility references.
