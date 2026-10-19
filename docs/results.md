# Test execution and findings

## Current outcome

### Latest completed tests — 2026-10-19

These verified results supersede the older blocked/incomplete/recovery snapshots below.

| Test | Exact test-time network posture | Deployment and version result | Audit evidence | Verdict |
| --- | --- | --- | --- | --- |
| CMK-IP-03 | Vault public **Enabled**, default Deny, bypass **None**, one approved public control-plane IP, zero VNet rules; NSP absent; owner policy-exclusion tag retained | New version created over VM PE; workspace-only CMK deployment 01:18:23–01:21:01 UTC succeeded; workspace `Succeeded`, attempted version applied, vault tags preserved | Three `KeyGet` and one `KeyUnwrap` at 01:19:53–01:19:56 UTC, all 200/OK; `IsRbacAuthorized=true`, `IsAddressAuthorized=true`, `TrustedService=AzureDatabricks`; public caller matches approved IP | **Pass (functional, public selected-IP path)** |
| CMK-NSP-TAG-01 | Vault public **Disabled**, Deny, bypass **None**, zero vault IP/VNet rules; new isolated NSP vault association Enforced, Log Analytics Learning/Transition; single native Inbound `serviceTags=[AzureDatabricks]`, zero address prefixes | Native tag rule accepted and read back `Succeeded`; new version created over VM PE; target-only deployment started 01:29:16 UTC and final verification completed 01:31:27 UTC; workspace `Succeeded`, new version applied, vault tags preserved | `KeyUnwrap` at 01:30:18 UTC, 200/OK, RBAC true, public caller, `TrustedService=AzureDatabricks`, address-authorization field empty. No `KeyGet`/`KeyWrap` observed in this queried window | **Pass (functional, native NSP service-tag variant)** |

**Current state:** target workspace `Succeeded`, public access Disabled and new Managed Services CMK version applied; vault public Disabled / bypass None / Deny / zero IP/VNet rules, associated with the Enforced service-tag NSP. The LAW association remains Learning/Transition. The owner-supplied policy-exclusion tag remains unchanged. Existing two PoC vault PEs and the third Databricks/NCC connection remain Approved. All prior key versions are retained. No full cleanup, commit or push was performed.

**Conclusion and limits:** both requested variants succeeded functionally, but neither demonstrates customer Private Endpoint routing for the Databricks CMK client. They admit a public service source. NCC remained present throughout (NCC alone failed earlier), no tag-rule removal negative control or genuine external-denial test was run, and only one successful new-version trial per variant is recorded. Official Managed Services CMK support for this NSP topology remains unconfirmed. Key caching and audit ingestion can change observed operation counts; do not infer all operations from deployment status alone.

**Service-tag scope and documentation discrepancy:** `AzureDatabricks` is documented as not regionally scoped: its published service-wide cloud ranges are not a Korea Central-only, tenant-only, workspace-only or CMK-only identity. Do not invent `AzureDatabricks.KoreaCentral`. Native tag-rule acceptance was observed even though the CLI/ARM property descriptions say “currently unavailable”; the NSP concepts table calls service-tag rules Preview. Actual acceptance in this subscription is not a GA/support guarantee. Sources: [NSP rule types](https://learn.microsoft.com/en-us/azure/private-link/network-security-perimeter-concepts#supported-access-rule-types), [CLI rule reference](https://learn.microsoft.com/en-us/cli/azure/network/perimeter/profile/access-rule), [ARM rule properties](https://learn.microsoft.com/en-us/azure/templates/microsoft.network/networksecurityperimeters/profiles/accessrules), [service-tag scope](https://learn.microsoft.com/en-us/azure/virtual-network/service-tags-overview).

### Historical snapshots before the latest completed tests

**Workspace recovery completed — 2026-10-19 00:55:28 UTC:** target-only deployment started 00:39:43 UTC and returned the workspace from `Failed` to **`Succeeded`**, reapplying its existing enabled pinned CMK version. Read-back verified the same version, vault tags and network ACLs preserved, and workspace public access Disabled. Vault remains Enabled / Deny / bypass None / one IP / zero VNet rules; no key version, vault, or network resource was created by this recovery. UI new-version rotation is a separate user action and has not been performed by the assistant. Recovery may have used cached key material, so this provisioning success alone does not establish fresh KeyGet/Unwrap or complete CMK-IP-03. Earlier Failed-state/incomplete-test snapshots below are historical. Private endpoint reachability checks also passed (private DNS/TCP, valid TLS, HTTPS 303); authenticated browser/API access is still separate.

**Policy-tagged selected-IP retry (2026-10-19): configuration achieved, CMK test incomplete.** The owner applied a policy-exclusion tag. The vault now reads **Enabled / Deny / bypass None / one control-plane IP / zero VNet rules**, with PoC NSP absent. The earlier policy blocker no longer prevents the configuration. The new workspace-only helper stopped in preflight while handling the empty NSP list (`name` property error), before key creation or a workspace deployment. Earlier local helper-name shadowing and unsupported CLI argument errors also stopped before mutation. No new CMK success or service denial occurred; workspace remains `Failed` with its previous CMK version from CMK-IP-02. All owner tags remain unchanged; the vault template was not redeployed. Bicep workspace-only template compiled with exit code 0; that is syntax validation, not CMK execution. Further helper repair/test continuation needs user direction after repeated local runtime errors.

### Clarified selected-networks retry (2026-10-19)

The owner clarified that “selected networks” means **Allow public access from specific virtual networks and IP addresses**: `publicNetworkAccess=Enabled`, `defaultAction=Deny`, bypass `None`, one control-plane IP rule, no additional VNet rules. This supersedes the earlier interpretation that PNA must remain Disabled. With the PoC NSP already removed, `Set-VaultIpAllowlist.ps1` explicitly attempted Enabled and read the vault back. Before and after: **Disabled / None / Deny / one IP rule / zero VNet rules**. The script stopped with “Stage 2 posture not reached.” Follow-up read-back at 2026-10-19 00:01:21 UTC confirmed Disabled and workspace `Failed`, previous key retained. **Verdict: intended selected-network CMK test blocked at configuration, not executed.** The earlier CMK-IP-02 failure is only the Disabled-PNA negative test, not evidence that active selected networks fails. Previously verified management-group `KeyVault_PublicNetwork_Modify` rewrites Enabled to Disabled; no policy exemption or assignment change was made. An active selected-networks CMK test requires the policy owner to permit Enabled, followed by read-back verification and a separate CMK attempt. No additional key version or CMK update was issued after this blocked retry.

**Latest result — CMK-IP-02, 2026-10-19 local date:** PoC NSP removed and absence verified. Vault public Disabled / bypass `None` / default Deny with one stored control-plane IP firewall rule. A new key version was created privately and applied; the update failed with wrapped HTTP 403 `ForbiddenByConnection`. Workspace provisioning is now `Failed`, prior CMK version retained. No public-enable write, bypass change, NCC deletion or NSP recreation was performed. The six earlier attempts below are historical outcomes.

### Final no-NSP test (CMK-IP-02)

- **Owner authorization:** remove the PoC NSP; retain public access Disabled and bypass `None`; add only the previously observed control-plane address to the vault IP firewall; retry CMK.
- **Verified changes:** PoC perimeter absent at 2026-10-18 23:48:22 UTC; vault properties remained Disabled / None / Deny with exactly one stored IP rule and no VNet rules. Owned vault PEs and the foreign Databricks/NCC connection remained Approved.
- **Procedure/outcome:** new key version created through the VM PE; CMK deployment preserved the IP rule explicitly via `VaultAllowedIps`. The stage ran 23:51:10–23:54:05 UTC and failed. The workspace returned `Failed`, retaining its prior key version rather than the attempted version. Read-back completed at 23:54:08 UTC.
- **Exact denial:** Databricks `PERMISSION_DENIED` wrapped Key Vault HTTP 403, inner code `ForbiddenByConnection`: the connection is not an approved private link, bypass is not `AzureServices`, and public access is Disabled. The service-specific network reason—not the outer missing-permission wording—identifies this denial. Audit ingestion is checked separately; do not invent request rows or authorization fields absent from the query.
- **What was tested:** the exact Disabled / None configuration with NSP removed and one stored firewall IP rule. It failed as predicted.
- **What cannot be tested under these constraints:** active classic selected-network IP admission. Key Vault public access Disabled rejects public configurations; a stored IP rule is not an override. Active selected networks requires public access Enabled with default Deny. The user explicitly retained Disabled in this follow-up, and earlier tests also showed a management-group modify policy rewriting Enabled to Disabled. No policy exception or broader write was attempted.
- **Final state/risk:** NSP remains deleted; one inactive IP rule remains stored; bypass None and public Disabled remain; workspace provisioning `Failed` with previous CMK retained. No automatic recovery. Cached-key runtime effects are not measured and the cache interval is undocumented. Obtain approval before recreating NSP or changing bypass/public access.

Source: [Microsoft Key Vault network security — public access disabled](https://learn.microsoft.com/en-us/azure/key-vault/general/network-security#public-access-disabled-private-endpoint-only). Full identifiers, the IP, key versions and raw deployment evidence remain in ignored local storage.

**Earlier six CMK attempts, to be read together with the final seventh attempt above.**

1. **The requested configuration (public access Disabled, trusted-services bypass `None`, private endpoint only): failed in the tested attempt with 403 `ForbiddenByConnection`.** This is a runtime result for this setup, not a vendor-confirmed unsupported classification; the supported route remains unconfirmed.
2. **The documented trusted-service configuration (public access Disabled, bypass `AzureServices`): functionally validated.** The only change was the vault's bypass, and the same CMK deployment then succeeded.
3. **Bypass `None` with a Databricks NCC private endpoint rule to the vault (Approved on the vault): failed in the same way as run 1** (403 `ForbiddenByConnection`, same caller address). NCC did not change the control plane's path. See the NCC section below.
4. **Bypass `None`, vault inside an Enforced network security perimeter with one inbound address rule: succeeded.** The workspace update succeeded; the control plane's `KeyGet` and `KeyUnwrap` returned 200 with `IsRbacAuthorized=true`. The caller was the same public address, which is the address the perimeter rule allows. Not a private endpoint path. See the NSP section below.
5. **CMK-NSP-03 phase A: the perimeter rule was removed, with the vault association still Enforced; the CMK update failed with `ForbiddenByNsp`.**
6. **CMK-NSP-03 phase B: the rule was restored and another new key version applied; the update succeeded.** Current workspace state is `Succeeded` with CMK configured.

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

#### NCC test (2026-10-18, test CMK-NCC-01): bypass `None` plus an approved NCC private endpoint rule

**Setup (what was and was not verified).** A Databricks account admin created an NCC and a private endpoint rule to the vault (sub-resource `vault`) in the Databricks account console. **Verified by us from Azure:** the vault gained a third private endpoint connection that is not ours, created by Databricks (its name starts with `databricks-`), with status **Approved**; the vault was still public access Disabled, bypass `None`, default Deny, no IP rules; our two own connections were unchanged. **Not verified by us:** the NCC rule status in the account console (`ESTABLISHED`), that the NCC is attached to this workspace, and who approved the connection. No serverless compute was started, so we did not test whether serverless traffic uses this endpoint.

**Procedure.** A new version of the existing key was created over the VM's private endpoint, then `Deploy-Poc.ps1 -Stage Cmk -KeyVersion <new version> -VaultBypass None` was run with the vault unchanged. Test start 08:46 UTC.

**Result: failed.** The workspace update ended in `PERMISSION_DENIED` wrapping the same vault error as run 1: 403 `ForbiddenByConnection`, "Connection is not an approved private link and caller was ignored because bypass is not set to 'AzureServices' and PublicNetworkAccess is set to 'Disabled'". The audit log shows one control-plane `KeyGet` at 08:48 UTC: 403 `Forbidden`, `IsRbacAuthorized` empty, `IsAddressAuthorized` empty, `TrustedService=AzureDatabricks`, caller **the same public address as in runs 1 and 2**, same Java SDK client. The workspace was left in provisioning state `Failed` and still carries the earlier key version.

**Interpretation.** With an approved NCC connection present, the control plane's key request still arrived from the same public address and was denied at the network layer. So NCC did not carry the Managed Services CMK request. This agrees with Microsoft documenting NCC for serverless compute only. **Limits:** one attempt; NCC rule status and workspace attachment not read by us; the NCC connection may need time or a serverless restart to take effect (Microsoft says up to 10 minutes, and restart serverless resources), and we waited only for the attachment steps the admin reported; a different account configuration is not excluded. The result supports "NCC does not change this path in this setup", not "NCC can never apply".

#### Summary of the CMK runs

| Run | Vault bypass | Other vault settings | NCC rule | Control-plane `KeyGet` | `IsRbacAuthorized` | Workspace result |
| --- | --- | --- | --- | --- | --- | --- |
| 1 (05:44 UTC) | `None` | Public Disabled, Deny, no IP rules | No | 403 `Forbidden` | empty | Update failed; workspace `Failed` |
| 2 (06:50 UTC) | `AzureServices` | Same | No | 200 `OK` (x3), then `KeyUnwrap` 200 | `true` | Update succeeded; `Succeeded`; key applied |
| 3 (08:48 UTC) | `None` | Same | Yes (connection Approved on the vault) | 403 `Forbidden` | empty | Update failed; workspace `Failed`, earlier key version retained |
| 4 (09:51 UTC) | `None` | Vault property still public Disabled, Deny, no vault IP rules; **vault association in an Enforced network security perimeter with one inbound address rule** | Yes (connection still Approved) | 200 `OK` (`KeyGet`), then `KeyUnwrap` 200 | `true` | Update succeeded; workspace `Succeeded`; new key version applied |
| 5 / CMK-NSP-03 A (10:06:56–10:09:52 UTC) | `None` | Same as run 4 **except the perimeter inbound rule was removed**; vault association remained Enforced | Yes (connection still Approved) | Deployment error: wrapped 403, inner code **`ForbiddenByNsp`**; matching vault audit row was not available when queried | not available | Update failed; workspace temporarily `Failed`; prior CMK version retained |
| 6 / CMK-NSP-03 B (10:29:24–10:46:19 UTC) | `None` | Same as run 4, with the inbound perimeter rule restored; vault PNA Disabled, default Deny, no vault IP rules | Yes (connection still Approved) | `KeyGet` 200 (x3) and `KeyUnwrap` 200 in the follow-up audit query | `true` | Update succeeded; workspace `Succeeded` with the new CMK version |

The first three establish: **bypass off failed, bypass on succeeded, and bypass off with an approved NCC connection failed.** Run 4 adds that **bypass off with an Enforced perimeter and one inbound address rule succeeded**. CMK-NSP-03 strengthens the attribution: **removing that rule failed with `ForbiddenByNsp`; restoring it and applying a different new key version succeeded**. The final workspace state is `Succeeded`. The caller remained a public address and the vault labelled it `TrustedService=AzureDatabricks`; that label describes caller classification, not admission or route.

**Correction to an earlier statement.** Earlier plan text said a pass would show "no `TrustedService` label". That was wrong: the label was present on both denied runs. The real discriminators are the HTTP status and `IsRbacAuthorized` / `IsAddressAuthorized`.

#### Stage 2: IP allowlist test (blocked)

**Approval and intent.** After the NCC test failed, the user approved Stage 2: vault public network access Enabled from selected networks, default action Deny, bypass `None`, one IP rule for the control plane address from the audit log, and then re-apply the CMK. This is a deliberate deviation from the public-access-Disabled requirement.

**What was done (all on the PoC vault only).**

1. A new script, `Set-VaultIpAllowlist.ps1`, added one IP rule (a /32 for the audit-log address). Its own before/after log: before `{public Disabled, bypass None, default Deny, 0 IP rules}`, after `{public Disabled, bypass None, default Deny, 1 IP rule}`. The script then stopped by design because public access had not become Enabled.
2. `az keyvault update --public-network-access Enabled`: exit code 0, vault still `Disabled`.
3. `az resource update --set properties.publicNetworkAccess=Enabled`: exit code 0, vault still `Disabled`.
4. A deployment of our vault Bicep module with `publicNetworkAccess=Enabled` and the allowed address: deployment `Succeeded`, vault still `Disabled`, IP rule present.

**Cause.** Policy compliance records for the vault list a `modify`-effect policy, `KeyVault_PublicNetwork_Modify`, in the policy set `MCAPSGovDeployPolicies`, assigned at the tenant's management group with enforcement mode `Default`. Its display name is "SFI-NS2.2.1 Secure PaaS Resources - Key Vaults (excluding NSP configured resources)". Its modify operation is `AddOrReplace` on `Microsoft.KeyVault/vaults/publicNetworkAccess` for API versions from 2021-10-01. The activity log records `Microsoft.Authorization/policies/modify/action` on the vault at the times of our writes. A `modify` policy rewrites the value during the write, so every path that writes the property ends with `Disabled` while still reporting success. Other assignments seen are audit-only and cannot change settings.

**What this means.**

- On this subscription the vault's public network access cannot be set to `Enabled` by us, so the "selected networks plus IP allowlist" design **cannot be tested here as written**. The vault firewall's IP rules apply only while public network access is not `Disabled`, so the one IP rule that exists does nothing now.
- This is a finding about the environment, not about Databricks. It is also evidence that the organisation enforces private-only Key Vault access, so any design that depends on public access Enabled would fail the same governance control.
- The `modify` policy excludes resources configured with a network security perimeter (NSP), per its display name. **Correction (2026-10-18):** this entry originally said an NSP "is not expected to help". That was wrong: the NSP test below succeeded. The reasoning had been that an NSP overrides the trusted-services bypass, which is true, but it ignored that a perimeter inbound rule can admit the control plane's address itself.

**Not done, on purpose.** No policy exemption, assignment edit, remediation or other change to organisational governance was attempted. Those are outside the approved scope and belong to the policy owner.

**Rollback.** The vault was restored with `Set-VaultIpAllowlist.ps1 -Restore` (public Disabled, default Deny, bypass `None`, IP rules removed). See the journal for the verified state.

#### NSP test (2026-10-18): tests CMK-NSP-01 and CMK-NSP-02

**Why NSP.** The policy that blocked Stage 2 excludes Key Vaults configured with a network security perimeter. The user asked to try NSP first, then the selected-networks test. Microsoft's documentation and the pre-stated expectations are in the [deployment plan](deployment-plan.md).

**Setup (all in the PoC resource group).** A perimeter, one profile, and two associations in Transition (log-only) mode: the Key Vault, and the Log Analytics workspace (so audit queries from this VM keep working). One diagnostic setting on the perimeter sends its logs to that workspace.

**CMK-NSP-01: Transition association, then public network access Enabled. Not reached.** After the association, the Enabled write was retried with the same script. It again reported success while the vault stayed `Disabled`. A Transition-mode association does not stop the management-group policy from rewriting the value. So the selected-networks test as originally defined (a classic vault firewall IP rule) **stays untestable** in this subscription. The IP rule was removed again.

**CMK-NSP-02: Enforced association with one inbound access rule. Passed (functional).**

1. One inbound perimeter access rule for the single control plane address (a /32, the address seen in our audit log) was added.
2. Only the vault's association was switched to **Enforced**. The workspace association stayed Transition. Read back: association Enforced, provisioning succeeded, no provisioning issues.
3. The vault's own properties stayed public `Disabled`, bypass `None`, default Deny, no IP rules (re-read 09:52 UTC).
4. The same CMK stage was run with `-VaultBypass None` and the same new key version as the failed NCC run (test start 09:36 UTC).
5. The workspace passed through `Accepted` and then `Succeeded` with the new key version applied. The CMK stage reported completion.
6. Vault audit log, 09:51 UTC: after the usual 401 authentication challenges, `KeyGet` 200 and `KeyUnwrap` 200, `IsRbacAuthorized=true`, `TrustedService=AzureDatabricks`, caller the same public address as in runs 1 to 3, same Java key vault SDK client on Linux.

**What this shows.** With the vault at bypass `None`, the control plane's key requests were admitted once the vault sat in an Enforced perimeter with an inbound rule for the control plane's address. That is the closest working equivalent of "selected networks with only the control plane address approved while trusted services bypass is disabled", implemented with a perimeter instead of the vault firewall.

**What this does not show.**

- **Not a private endpoint path.** The caller is still a public address, admitted by an IP rule.
- **Attribution is by elimination, not by a log.** The perimeter access log table exists but had no entries when read. It was enabled shortly before the request and may lag, so "no entry" is not evidence either way. The vault audit's network-ACL column was not read. The conclusion rests on the perimeter rule being the only functional change since the failed NCC run (run 3), with the same key version and the same bypass.
- **Confounder.** The NCC connection from run 3 was still Approved on the vault. NCC alone failed (run 3), so it is unlikely to be the cause, but it was not removed for this test.
- **Initial attempt followed by a negative control and repeat.** CMK-NSP-03 phase A removed only the perimeter inbound rule and failed with `ForbiddenByNsp`; phase B restored the rule and succeeded (details below).
- **Address stability.** Microsoft warns that control plane addresses change; this is evidence for that address at that time.
- **Support.** Microsoft does not document Managed Services CMK with a perimeter. Official support is unconfirmed.

**Documented behavior that fits.** In Enforced mode the perimeter rules override the vault's `publicNetworkAccess` setting, trusted-services bypass is overridden for a perimeter-secured vault, and private endpoint traffic is exempt from perimeter rules (so the VM's private path is unaffected).

**Current state and risk.** The vault is inside the Enforced perimeter with the inbound rule, and is reachable from one shared Databricks control-plane address. RBAC remains the identity boundary. Phase A confirmed that removing the rule blocks a new CMK update; the interval before any cached-key impact is still undocumented.

#### Negative control and repeat (CMK-NSP-03)

The design and expectations were written in the [deployment plan](deployment-plan.md) **before** running.

**Phase A: remove only the inbound rule. Result: failed, as expected.**

1. The inbound rule was deleted; the perimeter, profile, Enforced vault association and every vault setting were unchanged (status read-back: associations unchanged, no rule).
2. After a pause, a new key version was created over the VM's private endpoint (the vault name resolved to a private address; creating the key worked, confirming private endpoint traffic is exempt from the perimeter).
3. `Deploy-Poc.ps1 -Stage Cmk -VaultBypass None` was run with that new version (start 10:06:56 UTC).
4. The workspace went to `Updating` and then `Failed` and kept the earlier key version `...ecab51`.
5. **The platform error names the perimeter.** The wrapped vault message reads: "Connection is not an approved private link, the request was blocked by NSP rules and PublicNetworkAccess is set to 'Disabled'", with the caller identified as the AzureDatabricks application, and inner code **`ForbiddenByNsp`**. The earlier failures (runs 1 and 3) carried the different inner code `ForbiddenByConnection` and a message about the bypass.

**What this supports.** With the same vault and bypass posture, removing the only inbound perimeter rule produced a `ForbiddenByNsp` denial; restoring it, then applying a different new key version, succeeded. This is a controlled negative/repeat pair supporting the perimeter rule as the admission condition. **Limits:** the matching vault audit row for phase A was not available when queried, so there are no audit authorization columns for that denial; the NCC connection remained Approved throughout (it failed to admit the request in run 3); the perimeter access-log table had no rows when checked. It is strong controlled evidence, not an NSP-log-level correlation or vendor confirmation.

**Phase B: restore the rule, new key version, apply. Result: succeeded.** The inbound rule was restored and read back; a separate new key version was created through the VM's private endpoint. The CMK deployment ran from 10:29:24 to 10:46:19 UTC and completed. Final read-back at about 10:54 UTC showed the workspace `Succeeded` with CMK configured. The audit query returned three `KeyGet` and one `KeyUnwrap` operations, all HTTP 200, `IsRbacAuthorized=true`, `TrustedService=AzureDatabricks`, from the same public control-plane caller. The NCC connection remained Approved. This restores service after phase A and reproduces the functional success with the perimeter rule present.

#### Details

**Hypothesis:** the first failure was caused only by the vault's trusted-services bypass being `None`, so changing only that setting to `AzureServices` should make the same deployment succeed.

**Result: confirmed.** `Set-VaultBypass.ps1 -Bypass AzureServices` changed exactly one property. Its own log: before `{Public Disabled, bypass None, default Deny, 0 IP rules}`, after `{Public Disabled, bypass AzureServices, default Deny, 0 IP rules}`. The same CMK stage was then re-run with the same key version. The target workspace reached `Succeeded` with the managed-services key (vault URI, key name, pinned version) applied. The vault audit log now shows the Databricks control plane's requests succeeding: three `KeyGet` (200) and one `KeyUnwrap` (200), each with `IsRbacAuthorized=true`, caller classified `TrustedService=AzureDatabricks`, from the **same public Azure address** as the earlier denial.

**What this proves.** The earlier 403 was purely the network policy. Permissions were already correct: the role passed as soon as the network layer admitted the request. So the answer to "is the permission wrong?" is now settled by observation, not inference.

**What this does not prove.** The successful path is **not** a private endpoint. The control plane still arrives from a public Azure address and is admitted because it is a trusted service. Therefore the requested outcome (Databricks reaching the vault **through a private endpoint**) was not achieved in either run. No `KeyWrap` was observed, only `KeyUnwrap`; wrapping normally happens when new data keys are created, and the log window was short.

**Confounder, disclosed.** Between the two attempts the target workspace was recovered from `Failed` by redeploying the Baseline stage, and the CMK stage was re-run. The vault change is the only change to the vault, and the failure message named the bypass setting, but this is one before/after pair, not a repeated trial.

**Historical consequence after the control experiment.** At that point the vault was temporarily at bypass `AzureServices`, which deviated from the requested posture. It was later restored to `None` for the NCC and NSP experiments. **Current posture:** public access Disabled, bypass `None`, Enforced NSP association with one inbound rule; the target workspace is `Succeeded` with CMK. The NSP rule-removal negative control failed with `ForbiddenByNsp`; the effect of cached-key expiry remains undocumented. The key cannot be disabled from the workspace once Managed Services CMK is enabled.

**Historical consequence:** the first strict attempt left the workspace in provisioning state `Failed` without encryption configuration. The later control experiment and NSP repeat each succeeded; current state is `Succeeded` with CMK. Do not mistake the earlier failure state for current status.

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
| KV-BYPASS-01 — bypass None | Vault deployed with strict flags | Read vault properties | Strict flags retained | Public Disabled, bypass None, default Deny, 0 IP rules during the first CMK attempt. **Changed to bypass `AzureServices` for the control experiment, then restored to `None` (confirmed by the script's before/after log and a later vault read)** | Pass for the first attempt; requirement met again after the restore | Restore was done to test an NCC path; the workspace keeps working on a cached key until the cache expires |
| CMK-CONFIG-01 — managed-services CMK | Key exists and is enabled; vault private-only (public Disabled, bypass None, default Deny); AzureDatabricks app granted Crypto Service Encryption User on the vault | `Deploy-Poc.ps1 -Stage Cmk -KeyVersion <version>`, a workspace update with the key URI, name and pinned version | Successful exact managedServices update | **Failed.** Workspace `PERMISSION_DENIED`: Databricks could not use the key; the wrapped vault error is 403 `ForbiddenByConnection` (not an approved private link; bypass is not `AzureServices`; public access Disabled). Workspace left in `Failed` with no encryption block | **Fail** | Databricks reports this as a missing-permission error, but the vault's own message and the audit record point to the network policy. See CMK-RBAC-01 for what is and is not proven about RBAC. Evidence: deploy output and workspace state kept locally |
| CMK-OPS-01 — key operations | Same | Queried vault audit logs after the initial failure | Real service-principal Get/Wrap/Unwrap in this attempt | One `KeyGet` by the AzureDatabricks application, HTTP 403 / `Forbidden`; no `KeyWrap`/`KeyUnwrap` in this failed attempt | Fail (denied) | The audit `ResultType` column says `Success` for this denied request; trust `HttpStatusCode` and `ResultSignature`, not `ResultType`. Later successful operations are captured in CMK-OPS-02 and CMK-NSP-03 |
| CMK-RBAC-01 — was the 403 a permission problem? | Vault in RBAC mode (access policies not in use) | Read role assignments on the vault, the AzureDatabricks service principal, the workspace identities and the audit authorization fields | The AzureDatabricks principal holds the documented role at the vault; the denial is not an RBAC denial | See the evidence list below | **Pass** | The first denial happened before RBAC was evaluated. The control experiment later settled it: with the network layer open, RBAC passed (`IsRbacAuthorized=true`) |
| CMK-CONFIG-02 — control experiment, bypass `AzureServices` | Same vault, only bypass changed (public Disabled, default Deny, 0 IP rules) | `Deploy-Poc.ps1 -Stage Cmk -KeyVersion <version> -VaultBypass AzureServices` | Successful managedServices update | Deployment completed; target workspace `Succeeded`; encryption block present with the vault URI, key name and pinned version | **Pass (functional)** | Matches the documented trusted-service design; not a private-endpoint path |
| CMK-OPS-02 — key operations, control experiment | Same | Queried vault audit logs for non-CLI callers | Real control-plane Get/Wrap/Unwrap | Three `KeyGet` and one `KeyUnwrap`, all HTTP 200, `IsRbacAuthorized=true`, `TrustedService=AzureDatabricks`; no `KeyWrap` seen in the window | **Pass (Get/Unwrap); Wrap not observed** | Window is short; caching means later operations may not hit the vault. Raw logs kept locally |
| CMK-PATH-02 — private path in the control experiment | Same | Read the audit record fields | Operation attributable to the intended private endpoint | Caller is a **public Azure address** classified `TrustedService=AzureDatabricks`; `IsAddressAuthorized` empty; no private endpoint involved | **Fail (not private)** | The success depended on the trusted-service bypass, not on the private endpoint |
| CMK-NCC-01 — bypass `None` plus approved NCC private endpoint rule to the vault | Vault Disabled/`None`/Deny/no IP rules; Databricks-created vault connection Approved; new key version created over the VM private endpoint; account-console NCC rule status and workspace attachment not read by us | `Deploy-Poc.ps1 -Stage Cmk -KeyVersion <new> -VaultBypass None`, then read the audit | Control-plane requests succeed without the bypass if NCC carries them | Update failed `PERMISSION_DENIED` (403 `ForbiddenByConnection`); audit: one `KeyGet` 403, `IsRbacAuthorized` empty, same public caller address; workspace `Failed`, earlier key version retained | **Fail** | NCC is documented for serverless compute only; consistent with that. One attempt. See the NCC section above for limits |
| CMK-IP-01 — selected networks with the control plane address allowed, bypass `None` | Approved by the user; vault posture could not be reached | `Set-VaultIpAllowlist.ps1`, CLI update, resource update and Bicep module deployment | Control plane admitted by IP rule, `IsAddressAuthorized=true` | Public network access stayed `Disabled` on all paths because a management-group `modify` policy rewrites it | **Blocked (not tested)** | Environment constraint. The CMK was not re-applied because the vault could not reach the intended posture. See the Stage 2 section |
| CMK-PATH-01 — CMK private path | Same | Read the audit record fields | Control-plane operation attributable to the intended PE | The caller arrived from a **public Azure address**, classified `TrustedService=AzureDatabricks`, using a Java SDK client on Linux (the control plane). The address is inside Microsoft's published `AzureDatabricks` service tag range (checked against the service tag data for Korea Central, change number 234; it is also inside an `AzureCloud` block registered to East US 2, which alone is address registration. Microsoft's published control plane address list names this address under the **East US 2** Control Plane NAT, not under Korea Central, so this Korea Central workspace's key request appears to have come through the East US 2 control plane NAT. Caveat: Microsoft says the NAT values apply when secure cluster connectivity is disabled, and this workspace has it enabled, so matching the table is an observation, not a documented guarantee). The audit log itself carries no such tag, only `CallerIpAddress`. It did not use the customer private endpoints | Fail (no private path) | Consistent with the documented trusted-service model. One observation; vendor confirmation pending |
| NEG-ID-01 — identity denial | No disposable key/test identity | Not run | Identity-specific rejection | None | Inconclusive | No grants changed |
| CMK-NSP-01 — vault in a perimeter (Transition), then public Enabled with one IP rule, bypass `None` | Perimeter, profile and two Transition associations created; user-approved | Retried `Set-VaultIpAllowlist.ps1` after the association | Enabled sticks, so the vault IP rule can be tested | Reported success; vault stayed `Disabled`; the policy rewrote the value | **Not reached** | Transition mode does not escape the management-group `modify` policy. The classic selected-networks test remains untestable here |
| CMK-NSP-02 — vault association Enforced with one inbound address rule, bypass `None` | Vault property public Disabled, bypass `None`, no vault IP rules; one perimeter inbound rule; workspace association Transition; same new key version as the failed NCC run | `Deploy-Poc.ps1 -Stage Cmk -KeyVersion <new> -VaultBypass None`, then audit | Control plane admitted by the perimeter rule | Workspace `Succeeded` with the new key version; `KeyGet` 200 and `KeyUnwrap` 200, `IsRbacAuthorized=true`, same public caller address | **Pass (functional)** | Not a private endpoint path. CMK-NSP-03 later strengthens attribution: removing the rule failed with `ForbiddenByNsp`, restoring it succeeded. NSP access-log table remained empty; NCC connection remained present; vendor support unconfirmed. See the NSP section |
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
- **Not established:** exact supported control-plane CMK PE route, successful private-endpoint-only CMK configuration, authenticated API/browser access, classic-cluster back-end path, or runtime public denial from an external network. Vendor supportability of the NSP configuration remains unconfirmed.
- **Observed in Azure:** the Baseline deployment succeeded in Korea Central; both workspaces are Premium with private workspace endpoints; the vault is public Disabled/bypass None and now associated with an Enforced NSP rule; the VM resolves the vault privately and created/listed the key over the endpoint; control-plane CMK succeeded with the NSP rule present and failed when it was removed; ARM key creation was refused before a PE existed (O-1).
- **Observed locally:** the initial terminal issue was resolved; deployment and validation evidence was collected by scripts and retained locally. Raw evidence stays in ignored local storage.
- **CMK operation logs:** the audit record contains both denied requests (`KeyGet` 403 with `ForbiddenByConnection` or `ForbiddenByNsp`) and successful requests (`KeyGet`/`KeyUnwrap` 200, RBAC authorized) from separate attempts. Raw logs stay in ignored local storage; this document carries sanitized summaries only.

## Per-test execution record template

When executing, add a dated entry for each run: test ID/objective; UTC start/end; approved preconditions; exact local config snapshot reference and sanitized summary; actual steps/commands/script revision; expected result; actual statuses/errors; Pass/Fail/Inconclusive; real evidence aliases/checksums retained locally; identity/network attribution; technical interpretation; unresolved uncertainty; next action. Keep unsuccessful attempts, not only the latest success.
