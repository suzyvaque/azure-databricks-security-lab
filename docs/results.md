# Test execution and findings

## Current outcome

**Two results, to be read together.**

1. **The requested configuration (public access Disabled, trusted-services bypass `None`, private endpoint only): 3 — Unsupported or not configurable, as observed in one experiment. Official support is unconfirmed.**
2. **The documented trusted-service configuration (public access Disabled, bypass `AzureServices`): functionally validated.** The only change was the vault's bypass, and the same CMK deployment then succeeded.

With the vault set to public access Disabled, trusted-services bypass `None` and private-endpoint-only access, applying Managed Services CMK to the workspace **failed**. The Databricks control plane's first request to the vault (a `KeyGet`) was rejected with HTTP 403 `ForbiddenByConnection`. The vault audit log records the caller as the AzureDatabricks application, classified by the vault as the trusted service `AzureDatabricks`, calling from a **public Azure address**, not through any customer private endpoint. No `KeyWrap` or `KeyUnwrap` was attempted because `KeyGet` failed first.

This agrees with the documentation review: the managed-services CMK configuration takes only a vault URI, key name and key version, with no field that selects a private route.

**Limits of this conclusion:** one attempt, one workspace, one region; Microsoft/Databricks have not been asked; the audit record shows the request source, which is evidence about the path but not a statement of design intent. It supports "not configurable under these exact settings", not "impossible in any configuration".

### Control experiment (2026-10-18, user-approved)

#### Side-by-side comparison: bypass `None` vs bypass `AzureServices`

Everything in the first group of rows was identical in both runs; only the bypass differs. Audit values come from the vault's `AZKVAuditLogs` table (resource-specific). Times are UTC from `TimeGenerated`.

| Item | Run 1: bypass `None` (requested posture) | Run 2: bypass `AzureServices` (control experiment) |
| --- | --- | --- |
| **Vault `publicNetworkAccess`** | Disabled | Disabled (unchanged) |
| **Vault default action** | Deny | Deny (unchanged) |
| **Vault IP and VNet rules** | None | None (unchanged) |
| **Vault private endpoints** | Two, both Approved | Same (unchanged) |
| **Role for the AzureDatabricks service principal** | Key Vault Crypto Service Encryption User on the vault | Same (unchanged) |
| **Key and pinned version** | `cmk-managed-services`, same version | Same (unchanged) |
| **Setting that differs: trusted-services `bypass`** | **`None`** | **`AzureServices`** |
| **Deploy command** | `Deploy-Poc.ps1 -Stage Cmk -KeyVersion <version>` | Same plus `-VaultBypass AzureServices` |
| **Workspace result** | Update failed with `PERMISSION_DENIED`; workspace left in `Failed`; no encryption block applied | Update succeeded; workspace `Succeeded`; encryption block applied (vault URI, key name, pinned version) |
| **Audit time (first control-plane request)** | 2026-10-18 05:44 UTC | 2026-10-18 06:50 UTC |
| **Audit `OperationName`** | `KeyGet` only (no wrap or unwrap attempted) | `KeyGet` x3, then `KeyUnwrap` x1 |
| **Audit `HttpStatusCode` / `ResultSignature`** | `403` / `Forbidden` | `200` / `OK` |
| **Audit `ResultDescription`** | `Connection is not an approved private link and caller was ignored because bypass is not set to 'AzureServices' and PublicNetworkAccess is set to 'Disabled'.` (inner code `ForbiddenByConnection`) | Empty |
| **Audit `IsRbacAuthorized`** | **Empty** (permission check not reached) | **`true`** |
| **Audit `IsAddressAuthorized`** | Empty | Empty |
| **Audit `TrustedService`** | `AzureDatabricks` | `AzureDatabricks` |
| **Audit `CallerIpAddress`** | An address in Microsoft's `AzureDatabricks` service tag range (not private) | The same address |
| **Audit `ClientInfo`** | Java Azure Key Vault SDK on Linux (the control plane) | Same |
| **Customer private endpoint used?** | No | No |

**Reading the table.** The only configuration difference is the bypass. With `None` the vault refused the control plane before it checked permissions (`IsRbacAuthorized` empty). With `AzureServices` the same caller, from the same address, was admitted and the permission check passed (`IsRbacAuthorized=true`). In neither run did the request use a customer private endpoint.

**Confounder.** Between the two runs the target workspace was recovered from `Failed` by redeploying the Baseline stage (without CMK). The vault was not touched in between except for the bypass change. This is one before/after pair, not a repeated trial.

#### Details

**Hypothesis:** the first failure was caused only by the vault's trusted-services bypass being `None`, so changing only that setting to `AzureServices` should make the same deployment succeed.

**Result: confirmed.** `Set-VaultBypass.ps1 -Bypass AzureServices` changed exactly one property. Its own log: before `{Public Disabled, bypass None, default Deny, 0 IP rules}`, after `{Public Disabled, bypass AzureServices, default Deny, 0 IP rules}`. The same CMK stage was then re-run with the same key version. The target workspace reached `Succeeded` with the managed-services key (vault URI, key name, pinned version) applied. The vault audit log now shows the Databricks control plane's requests succeeding: three `KeyGet` (200) and one `KeyUnwrap` (200), each with `IsRbacAuthorized=true`, caller classified `TrustedService=AzureDatabricks`, from the **same public Azure address** as the earlier denial.

**What this proves.** The earlier 403 was purely the network policy. Permissions were already correct: the role passed as soon as the network layer admitted the request. So the answer to "is the permission wrong?" is now settled by observation, not inference.

**What this does not prove.** The successful path is **not** a private endpoint. The control plane still arrives from a public Azure address and is admitted because it is a trusted service. Therefore the requested outcome (Databricks reaching the vault **through a private endpoint**) was not achieved in either run. No `KeyWrap` was observed, only `KeyUnwrap`; wrapping normally happens when new data keys are created, and the log window was short.

**Confounder, disclosed.** Between the two attempts the target workspace was recovered from `Failed` by redeploying the Baseline stage, and the CMK stage was re-run. The vault change is the only change to the vault, and the failure message named the bypass setting, but this is one before/after pair, not a repeated trial.

**Consequence for the lab.** The vault is now at bypass `AzureServices`, which deviates from the requested posture. Public access is still Disabled. Managed Services CMK cannot be disabled once enabled, and the workspace now depends on this vault. Restoring `None` is expected to make the control plane's key requests fail again once its cached key expires (the cache interval is not documented). Decision pending.

**Consequence:** the workspace was left in provisioning state `Failed` with no encryption configuration after the first attempt. Nothing was enabled to work around the failure at that point, and the vault settings were re-read afterwards and were unchanged. The control experiment below was run later, on explicit instruction.

All test preconditions/procedures/expected results are defined in the [test plan](test-plan.md). The register below records **actual results only**. Inconclusive means untested or insufficient evidence, not failed infrastructure. "Pass (configuration)" means the Azure resource properties were read and match; it does not mean traffic was tested.

| Test ID / objective | Preconditions and exact test-time config | Actual procedure | Expected result | Actual result | Verdict | Evidence / interpretation / uncertainty |
| --- | --- | --- | --- | --- | --- | --- |
| ENV-01 — KRC readiness | Logged-in subscription, user-run preflight | Read providers, SKUs, usage, policies, permissions | Required features available in Korea Central | Subscription enabled; 7 providers registered; Databricks lists Korea Central; Standard_D4s_v3 unrestricted; only Defender policies assigned; Owner-level permissions; **only 8 regional vCPUs free** | Pass (with quota caveat) | Preflight evidence kept locally; feature-combination availability confirmed only by the successful deployment |
| NET-01 — VNet Injection | Target workspace deployed into new VNet | Read workspace properties | Custom VNet, new subnets, no public node IPs | Custom VNet and both new subnets set; `enableNoPublicIp=true`; NSGs carry the three required rules | Pass (configuration) | No cluster started, so node NICs and addresses untested; the CMK-experiment cluster is not yet created |
| PL-FE-01 — front-end PL | PE Approved, workspace public Disabled, VM VNet peered to the workspace VNet, VM VNet linked to the Databricks private DNS zone | From the VM: resolve, open TCP, TLS with the real hostname, HTTPS request (scripts/validate/Test-WorkspaceConnectivity.ps1) | Private path to the workspace | Resolves to a private address; TCP peer address private; TLS validates; HTTPS returns 303 (redirect to sign-in) | Pass (reachability); authenticated API access untested | An unauthenticated 303 proves the endpoint answers over the private path. It does not prove API authentication. The test does not show that the public path is blocked |
| PL-BE-01 — back-end PL | Same endpoint, role shared | Not run | Healthy workload plus private API/relay path | None | Inconclusive | Cluster-to-control-plane path untested |
| AUTH-01 — browser auth | Auth workspace and PE deployed; VM VNet peered to the transit VNet | Same reachability test against `koreacentral.pl-auth.azuredatabricks.net` | Private callback success | Resolves privately; TCP peer private; TLS validates; HTTPS 303 | Partial (reachability) | An actual browser sign-in was not performed |
| VM-01 — VM private access | VM VNet had Azure DNS and no peerings; user approved peering | Two peering pairs (no gateway transit, no forwarded traffic) and one DNS zone link | Private path and original baseline intact | All four peerings Connected; workspace and auth reachable privately; vault reachable privately | Pass (network path) | Existing-VNet changes: two peering links and one DNS link. VM, NIC, NSG and routes untouched. Effective routes and NSG on the VM were not re-inspected |
| PUB-DBX-01 — workspace public denial | Public access Disabled | Read property only | Network-specific denial from a public network | Property is Disabled | Inconclusive | No external test client used |
| KV-PRIVATE-01 — VM vault control | Vault private-only, PE Approved | From the VM: resolved vault name, created key, listed key | Authorized VM private data-plane access | Resolved to a private address; key created; key enabled | Pass | Proves the VM path only; not managed-services CMK |
| PUB-KV-01 — vault public denial | Vault private-only | See observation O-1 | Network-specific denial from a public network | Before any PE existed, ARM key creation was refused with `ForbiddenByConnection` | Inconclusive | O-1 is a Microsoft first-party service, not an external client; no external vantage tested |
| KV-BYPASS-01 — bypass None | Vault deployed with strict flags | Read vault properties | Strict flags retained | Public Disabled, bypass None, default Deny, 0 IP rules during the first CMK attempt. **Later changed to bypass `AzureServices` for the control experiment** | Pass for the first attempt; **requirement no longer met since the control experiment** | Public access is still Disabled and default action Deny. Restore with Set-VaultBypass.ps1 -Bypass None |
| CMK-CONFIG-01 — managed-services CMK | Key exists and is enabled; vault private-only (public Disabled, bypass None, default Deny); AzureDatabricks app granted Crypto Service Encryption User on the vault | `Deploy-Poc.ps1 -Stage Cmk -KeyVersion <version>`, a workspace update with the key URI, name and pinned version | Successful exact managedServices update | **Failed.** Workspace `PERMISSION_DENIED`: Databricks could not use the key; the wrapped vault error is 403 `ForbiddenByConnection` (not an approved private link; bypass is not `AzureServices`; public access Disabled). Workspace left in `Failed` with no encryption block | **Fail** | Databricks reports this as a missing-permission error, but the vault's own message and the audit record point to the network policy. See CMK-RBAC-01 for what is and is not proven about RBAC. Evidence: deploy output and workspace state kept locally |
| CMK-OPS-01 — key operations | Same | Queried vault audit logs after the failure | Real service-principal Get/Wrap/Unwrap | One `KeyGet` by the AzureDatabricks application, HTTP 403 / `Forbidden`; no `KeyWrap`/`KeyUnwrap` | Fail (denied) | The audit `ResultType` column says `Success` for this denied request; trust `HttpStatusCode` and `ResultSignature`, not `ResultType` |
| CMK-RBAC-01 — was the 403 a permission problem? | Vault in RBAC mode (access policies not in use) | Read role assignments on the vault, the AzureDatabricks service principal, the workspace identities and the audit authorization fields | The AzureDatabricks principal holds the documented role at the vault; the denial is not an RBAC denial | See the evidence list below | **Pass** | The first denial happened before RBAC was evaluated. The control experiment later settled it: with the network layer open, RBAC passed (`IsRbacAuthorized=true`) |
| CMK-CONFIG-02 — control experiment, bypass `AzureServices` | Same vault, only bypass changed (public Disabled, default Deny, 0 IP rules) | `Deploy-Poc.ps1 -Stage Cmk -KeyVersion <version> -VaultBypass AzureServices` | Successful managedServices update | Deployment completed; target workspace `Succeeded`; encryption block present with the vault URI, key name and pinned version | **Pass (functional)** | Matches the documented trusted-service design; not a private-endpoint path |
| CMK-OPS-02 — key operations, control experiment | Same | Queried vault audit logs for non-CLI callers | Real control-plane Get/Wrap/Unwrap | Three `KeyGet` and one `KeyUnwrap`, all HTTP 200, `IsRbacAuthorized=true`, `TrustedService=AzureDatabricks`; no `KeyWrap` seen in the window | **Pass (Get/Unwrap); Wrap not observed** | Window is short; caching means later operations may not hit the vault. Raw logs kept locally |
| CMK-PATH-02 — private path in the control experiment | Same | Read the audit record fields | Operation attributable to the intended private endpoint | Caller is a **public Azure address** classified `TrustedService=AzureDatabricks`; `IsAddressAuthorized` empty; no private endpoint involved | **Fail (not private)** | The success depended on the trusted-service bypass, not on the private endpoint |
| CMK-PATH-01 — CMK private path | Same | Read the audit record fields | Control-plane operation attributable to the intended PE | The caller arrived from a **public Azure address**, classified `TrustedService=AzureDatabricks`, using a Java SDK client on Linux (the control plane). The address is inside Microsoft's published `AzureDatabricks` service tag range (checked against the service tag data for Korea Central, change number 234; it is also inside an `AzureCloud` block registered to East US 2, which is address registration, not proof of where the workload runs). The audit log itself carries no such tag, only `CallerIpAddress`. It did not use the customer private endpoints | Fail (no private path) | Consistent with the documented trusted-service model. One observation; vendor confirmation pending |
| NEG-ID-01 — identity denial | No disposable key/test identity | Not run | Identity-specific rejection | None | Inconclusive | No grants changed |
| NEG-NET-01 — network denial | No disposable path | Not run | Network-specific rejection without widening rules | None | Inconclusive | No firewall changed |
| NEG-CMK-01 — cached CMK enforcement | No disposable CMK workspace; no downtime approval | Not run | Cache-aware denial and recovery | None | Inconclusive | No key disabled/revoked |
| CLEAN-01 — complete cleanup | Resources now exist; no cleanup approval | Not run | Owned artifacts absent and original infra intact | Not run | Inconclusive | No deletion attempted |

## Was the 403 a permission problem? (CMK-RBAC-01 evidence, 2026-10-18)

| Check | Finding |
| --- | --- |
| Vault authorization mode | RBAC (access policies not used) |
| AzureDatabricks service principal | Enabled; its object ID equals the `oid` in the token claim recorded on the denied request, so the vault saw the intended identity |
| Role on the vault | **Key Vault Crypto Service Encryption User** assigned to that principal at the vault scope. This role includes the Get, Wrap and Unwrap key operations the documentation requires |
| Other role assignments on the vault | Only my own Key Vault Crypto Officer (used to create the key) plus inherited subscription-level roles. Nothing that denies access |
| Key | Enabled; the key version in the denied request URI is the version we pinned |
| Workspace storage-account identity | The documentation also mentions granting the role to this identity. The workspace has none (`prepareEncryption` is false, no storage identity exists), so there is no principal to grant. It is not the identity in the denied request |
| Audit fields on the denied `KeyGet` | `IsAddressAuthorized` and `IsRbacAuthorized` are **both empty**, and the status text names the network rule |
| Audit fields on my VM's key operations over the private endpoint | `IsRbacAuthorized` = true for the key create and list |

**Conclusion.** The permissions were granted correctly to the right principal at the right scope, and the vault side needs nothing further. The 403 was a network denial. The vault stopped the request at the network layer before it evaluated RBAC, which is why the RBAC field is empty. **Update:** the later control experiment confirmed this by observation: once the bypass admitted the request, the same principal's `KeyGet` and `KeyUnwrap` were authorised (`IsRbacAuthorized=true`).

## Supported documentation versus observation

- **Documented:** Databricks supports VNet Injection, Premium Private Link/SCC and Managed Services CMK; Korea Central is a listed region. Key Vault supports private endpoints and public-access restriction; bypass must be None to exclude trusted-service exemption.
- **Not established:** subscription/KRC feature-combination availability, exact supported control-plane CMK PE route, successful private-only CMK configuration, runtime public denials or private connectivity.
- **Observed in Azure:** the Baseline deployment succeeded; both workspaces are Premium, private-only, with Approved endpoint connections; the vault is locked to private-only access with bypass None; the VM resolves the vault privately and created and listed the key over the endpoint; ARM key creation was refused before any endpoint existed (O-1).
- **Observed locally:** the assistant terminal returned unreliable output throughout; results were gathered through detached scripts writing to files. Raw evidence stays in ignored local storage.
- **CMK operation logs:** the vault audit log holds one denied `KeyGet` by the AzureDatabricks application and no `KeyWrap` or `KeyUnwrap`. Raw logs stay in ignored local storage; this document carries sanitized summaries only.

## Per-test execution record template

When executing, add a dated entry for each run: test ID/objective; UTC start/end; approved preconditions; exact local config snapshot reference and sanitized summary; actual steps/commands/script revision; expected result; actual statuses/errors; Pass/Fail/Inconclusive; real evidence aliases/checksums retained locally; identity/network attribution; technical interpretation; unresolved uncertainty; next action. Keep unsuccessful attempts, not only the latest success.
