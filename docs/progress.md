# Phase-by-phase progress

**Latest clarification (2026-10-19):** “selected networks” means PNA Enabled from specific virtual networks/IPs, default Deny, bypass None, one control-plane address. This supersedes the previous Disabled-PNA interpretation. Retried that exact portal-equivalent configuration with NSP absent: vault still Disabled / None / Deny / one IP rule / zero VNet rules; script stopped “Stage 2 posture not reached.” Selected-network CMK test is blocked at configuration; no new CMK update was run. Workspace remains `Failed` with previous key retained. Prior management-group modify-policy finding explains the blocker; policy-owner permission/exemption would be needed, not a bypass or broader allowlist. No governance changes made.

Session dates: 2026-10-17 to 2026-10-18. Exact UTC times were not captured for most steps; date-level entries are intentional.

**Latest completed follow-up (2026-10-19 local date):** CMK-IP-02 removed the PoC NSP (verified absent 2026-10-18 23:48:22 UTC), retained public Disabled / bypass `None` / Deny, stored one control-plane firewall IP rule, created a new key version through the VM PE and retried CMK. The update ran 23:51:10–23:54:05 UTC and failed with wrapped HTTP 403 `ForbiddenByConnection`; final read-back at 23:54:08 UTC: target workspace `Failed`, prior CMK version retained, not the attempted new version. NSP remains removed and one inactive IP rule remains stored. No public-enable, bypass, policy or NCC change, and no automatic NSP recovery. Earlier successful-NSP snapshots below are historical and superseded. Active selected networks requires PNA Enabled, which contradicts this follow-up and was also blocked by the previously verified policy. Recovery/full cleanup decision now open; all other pending validations remain.

**Current as of 2026-10-18 10:54 UTC: Baseline deployed; target workspace `Succeeded` with Managed Services CMK. NSP negative control failed with `ForbiddenByNsp` after removing the sole inbound rule; restoring it and applying another key version succeeded. Vault is public Disabled / bypass `None`, associated with an Enforced NSP with one inbound rule. This permits a public control-plane address; it is not a private-endpoint-only CMK path. Authenticated/API, browser, classic-cluster and external public-denial tests remain. NCC rule cleanup, support question, Git review/commit and cleanup are pending. This current-state note supersedes earlier status entries below.**

| Phase | Status | Start | Completion | Tasks completed | Resources created/modified | Tests/outcomes | Issues | Next actions |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 — Feasibility and architecture research | Completed (open support question) | 2026-10-17 | 2026-10-17 | Official-source research; preflight run and reviewed (login, providers, policies, permissions, Korea Central availability, quota); VM network inspected | Local files only | Preflight 18/18 collected; VM network read | CMK private-only route undocumented; support question unanswered; Git commit and secret scan not done | Ask Microsoft/Databricks about private-only CMK |
| 2 — Infrastructure deployment plan | Completed | 2026-10-17 | 2026-10-17 | Plan drafted; user instructed resource creation | None | Not applicable | Deviations from plan (see guide) | None |
| 3 — Deployment and configuration | Completed | 2026-10-17 | 2026-10-18 | Baseline stage Succeeded (8/8 modules); key created over the private endpoint; VM peered; CMK configured | New RG and resources in Korea Central; approved peering/DNS additions to existing VM VNet; NSP deployed | Target workspace currently `Succeeded` with CMK | Private-only CMK failed; NSP rule required for the tested public control-plane path | Preserve current safe state; account-console NCC cleanup requires coordination |
| 4 — Security and functional validation | In Progress | 2026-10-18 | — | Vault lockdown, private VM reachability, CMK bypass/NCC/NSP tests; NSP A/B negative/repeat completed | None beyond deployed resources | See results.md; CMK-NSP-03 A failed `ForbiddenByNsp`, B succeeded | No NSP access-log rows; NCC connection remains a confounder; vendor support unconfirmed | Authenticated API/browser, classic cluster/back-end, external public-denial tests |
| 5 — Final reporting | In Progress | 2026-10-18 | — | Living records synchronized with final A/B outcome | Local docs only | Final-state snapshot at about 10:54 UTC | Support question and evidence review remain | Ask support; finish secret/history review and final report |
| 6 — Complete cleanup | Not Started | — | — | Cleanup procedure proposed only | None | Not run | Separate approval required; soft-delete retention expected | Inventory and approve cleanup after experiment |

## Phase 1 checklist

- [x] Inspect initial repository contents with file tools.
- [x] Attempt read-only local tooling/Git inspection; record failure to obtain execution output.
- [x] Review official VNet Injection, front/back-end Private Link, SCC, CMK, Key Vault and NCC guidance.
- [x] Distinguish control-plane CMK from compute-to-Key-Vault tests.
- [x] Record draft subnet, DNS, resource-placement, connectivity and cost proposal.
- [x] Author safe read-only preflight collector; editor PowerShell diagnostics report no errors, not runtime validation.
- [x] Attempt background marker, confirm it also fails, and terminate the looping terminal.
- [x] Review partial editor Git diff and run limited editor disclosure-pattern search (no matches; not a full secret scan/history audit).
- [x] Correct Markdown diagnostics and recheck workspace editor diagnostics: no errors found; no runtime inference.
- [x] Verify Azure CLI version/login/cloud/subscription and effective permissions (user-run preflight).
- [x] Identify existing VM and inspect NIC, subnet, VNet (read-only, via instance metadata).
- [x] Verify Korea Central provider/SKU/policy/quota eligibility (preflight).
- [ ] Resolve supportability of the exact Managed Services CMK network policy (open; support question).
- [ ] Execute local checks, secret scan, tracked-file/history review and local commit (not done).

## Historical: authorization and terminal blocker (resolved) — 2026-10-17

- User explicitly requested resource creation and offered to run login if needed. This authorizes new PoC provisioning once prerequisites pass, not changes to existing infrastructure or firewall weakening.
- Last manually executed `az` returned CLI help with exit code 0: CLI availability established; authentication/subscription not established.
- Two assistant terminal requests in this follow-up, including a standalone `az account show` returning only state/cloud, produced only a prompt. No account output or login error was received. Do not assert that login is required until a real check returns that error.
- No Azure writes attempted. Restore a standard PowerShell terminal and shell integration; manually check account state if necessary. Never share tokens or full account identifiers publicly.
- Existing-network changes, cleanup and publication still require their separate explicit approvals. Phase 1 remains Blocked, not Completed.
- Latest follow-up: user confirmed `az login` completed; terminal context shows exit code 0. Retried sanitized account-state query, but received only a prompt again. Do not request another login: the remaining blocker is assistant terminal execution and unverified target context, not an observed authentication failure. No Azure writes attempted.
- User reconfirmed login in PowerShell Extension and reported standard terminals have an infinite-newline bug. Use the working extension to run the existing read-only collector; no standard-terminal switch or further login is required. Collector execution and VM-specific inputs/results remain pending; raw outputs must not be shared publicly.

## Readiness update — 2026-10-17

- Preflight (user-run) collected 18/18 checks; VM-specific inspection skipped (no VM ID). Subscription Enabled in AzureCloud, providers registered, Korea Central listed for Databricks, no blocking policies seen, Owner-level permissions.
- Capacity constraint: Korea Central regional vCPU quota 92/100 used; use a single-node 4-vCPU cluster only.
- Authored [infra/main.bicep](../infra/main.bicep) and [Deploy-Poc.ps1](../scripts/deploy/Deploy-Poc.ps1) (later compiled, validated and run; see the status update below).
- Open: VM resource ID and approval for VM peering/DNS; CMK private-only route remains unresolved (stage Cmk is an experiment).

## Status update — 2026-10-18

- Baseline deployment `Succeeded` (network, keyvault, workspaces, privatelink, vmaccess). Both workspaces Premium, public network access Disabled, `NoAzureDatabricksRules`, private endpoint connections Approved. Target workspace uses the new VNet with `enableNoPublicIp=true`.
- Key Vault: public access Disabled, bypass None, default Deny, no IP rules, purge protection on. Both vault private endpoints Approved. From the VM the vault name resolves privately; key `cmk-managed-services` created over the private endpoint and enabled.
- Issues found and fixed: (1) ARM key creation refused by the private-only vault, so key creation moved to a private-path client; (2) redeploy conflicted with Databricks network intent policies, fixed by adding the three required outbound NSG rules; (3) status script's JMESPath filter broke under Windows quoting, fixed by filtering in PowerShell.
- Pending: VM peering approval; CMK stage; audit-log review; public-denial and negative tests; support question; Git scan and commit.

## Status update — 2026-10-18 (later)

- VM VNet peered with both new VNets (4 peerings Connected, no gateway transit or forwarded traffic) and linked to the Databricks private DNS zone, on the user's approval. The VM reaches the workspace and browser-auth endpoints privately (private DNS answer, private TCP peer, valid TLS, HTTP 303).
- CMK stage run: **failed**. Control-plane `KeyGet` rejected with 403 `ForbiddenByConnection`; audit shows `TrustedService=AzureDatabricks` from a public Azure address. Vault settings unchanged. Target workspace left `Failed` with no encryption block.
- Pending: workspace recovery (Baseline redeploy); optional bypass control experiment (needs approval); support question; authenticated API and browser sign-in; external public-denial tests; negative controls; Git scan and commit; cleanup (must also remove the two VM-side peerings and the DNS links).

## Status update — 2026-10-18 (control experiment)

- Workspace recovered by a Baseline redeploy (`Succeeded`). Key Vault role grant verified (Crypto Service Encryption User for the AzureDatabricks principal); the first 403 was shown to be a network denial.
- **Control experiment run on the user's instruction:** only the vault bypass changed, `None` to `AzureServices` (public access Disabled, default Deny, no IP rules). The same CMK stage then succeeded: workspace `Succeeded` with the key applied; audit shows `KeyGet` x3 and `KeyUnwrap` (all 200, `IsRbacAuthorized=true`) by `TrustedService=AzureDatabricks` from a public Azure address.
- **Open decision:** the vault is at `AzureServices`, which deviates from the stated requirement. CMK cannot be disabled; restoring `None` is expected to break the control plane's key access after its cache expires.
- Pending: that decision; support question; authenticated API and browser sign-in; external public-denial tests; negative controls (including NEG-CMK-01 if `None` is restored); Git scan and commit; cleanup.

## Status update — 2026-10-18 (staged plan recorded)

- Vault restored to bypass `None` (public access Disabled, default Deny, no IP rules) on the user's instruction.
- Documentation updated **before** any NCC or IP-allowlist change: the NCC serverless-only constraint, the colleague's NAT-IP proposal and its assessment, and the three-stage plan are in [feasibility](feasibility.md) and the [deployment plan](deployment-plan.md); new tests CMK-NCC-01 and CMK-IP-01 are in the [test plan](test-plan.md).
- Finding recorded: the control plane address seen in the audit log is listed by Microsoft under the East US 2 Control Plane NAT, not Korea Central.
- Next: Stage 1 (NCC) needs a Databricks account admin to create the NCC and the vault private endpoint rule; Stage 2 (NAT IP allowlist) needs explicit approval because it ends the public-access-Disabled posture. Nothing in Stages 1 to 3 has been executed.

## Status update - 2026-10-18 (Stage 1 prepared)

- Stage 1 (NCC test) is prepared and **waiting for a Databricks account admin** to create the NCC, attach it to the target workspace and add the vault private endpoint rule (Part A of the runbook in the deployment plan).
- Baseline recorded at 08:17 UTC: vault public Disabled, bypass None, default Deny, no IP rules; only our two vault connections (both Approved, no foreign connection); workspace Succeeded with CMK applied; last control-plane key requests 06:50 UTC (control experiment).
- New read-only and approval scripts added: Get-NccTestStatus.ps1 and Approve-VaultConnection.ps1. A Windows PowerShell 5.1 JSON array bug (two vault connections merged into one object) was found in the first run and fixed before the baseline was recorded.

## Status update - 2026-10-18 (Stage 1 executed, Stage 2 approved)

- **Stage 1 (NCC) executed:** an account admin created the NCC and a private endpoint rule to the vault; a Databricks-created connection appeared on the vault as Approved. A new key version was created over the VM private endpoint and the CMK stage was re-run with the vault bypass left at `None`. Result: **failed** with the same 403 `ForbiddenByConnection`, same public caller address, `IsRbacAuthorized` empty. Workspace left in `Failed` with its earlier key version.
- Three-run summary recorded in [results](results.md): bypass `None` failed; bypass `AzureServices` succeeded; bypass `None` with NCC failed.
- Correction recorded: the `TrustedService` label appears on denied requests too and is not a pass criterion.
- **Stage 2 approved by the user** (selected networks, one allowed address, bypass `None`, deviation from public-access-Disabled). Implementation note: the vault template now takes public access and allowed-address parameters so the CMK stage cannot reset the Stage 2 setting.
- **Stage 2 blocked:** a management-group Azure Policy (`KeyVault_PublicNetwork_Modify`, effect `modify`) rewrites the vault's `publicNetworkAccess` to `Disabled` on every write. Three write paths reported success while the value stayed `Disabled`; the IP rule was added but is inert. No exemption or governance change was attempted. Vault rolled back to the lab posture.
- Open items: NCC rule cleanup (account console); workspace recovery; support question; external-network denial test; Git scan and commit; cleanup.

## Status update - 2026-10-18 (NSP executed)

- **Stage 2b (NSP) executed on the user's instruction.** Perimeter, profile, Transition associations (vault, workspace) and an inbound rule for the control plane address created in the PoC resource group; a diagnostic setting sends perimeter logs to the PoC workspace.
- **CMK-NSP-01 (Transition, then public Enabled): not reached.** The management-group `modify` policy still rewrote public network access to Disabled, so the classic selected-networks test stays untestable here.
- **CMK-NSP-02 (vault association Enforced with one inbound rule, bypass `None`): passed (functional).** Workspace `Succeeded` with the new key version; control plane `KeyGet` and `KeyUnwrap` 200 with `IsRbacAuthorized=true`. Not a private endpoint path. Attribution by elimination (perimeter access log empty when read); NCC connection still present; one attempt; support unconfirmed.
- Correction recorded: an earlier results entry said an NSP was "not expected to help"; that was wrong.
- At the time of this entry, a negative control and final-state decision were pending. The negative control has since completed; the keep-or-teardown decision remains open. See the current status below.

## Current status — 2026-10-18 (CMK-NSP-03 negative control and repeat)

- **Phase A (negative control):** the sole NSP inbound rule was removed while the perimeter and Enforced vault association remained. Bypass stayed `None`, public network access stayed Disabled, and there were no Key Vault IP rules. A new key version was created over the VM private endpoint. CMK update started 10:06:56 UTC and failed at 10:09:52 UTC with wrapped HTTP 403, inner code `ForbiddenByNsp`. The workspace temporarily entered `Failed`; its prior CMK version remained. The matching vault audit row was not available when queried.
- **Phase B (repeat/recovery):** the rule was restored and read back; another new key version was created through the VM private endpoint. CMK update ran 10:29:24–10:46:19 UTC and completed. Final read-back around 10:54 UTC: workspace `Succeeded` with CMK; vault public Disabled, bypass `None`, default Deny, zero Key Vault IP rules; vault association Enforced, one inbound NSP rule; Log Analytics association Learning/Transition; two owned vault PEs plus one Databricks/NCC connection still Approved. Phase-B audit showed three `KeyGet` and one `KeyUnwrap`, all HTTP 200 and `IsRbacAuthorized=true`, from the same public control-plane caller.
- **Finding:** removing the NSP rule failed with `ForbiddenByNsp`; restoring it was followed by success. This is controlled evidence that the NSP rule gates this public control-plane request, not evidence of private-endpoint routing. The perimeter access-log table had no rows when queried; the NCC connection remained present; phase-A audit authorization fields are unavailable; one A/B cycle only; vendor support is unconfirmed.
- **Current decision/safety:** preserve the current rule and bypass `None` until the owner decides whether to retain or tear down. Do not remove the perimeter association/rule without a recovery plan. The Databricks account-level NCC rule remains and may be billed hourly; remove it in the account console when approved.
- **Remaining validation:** authenticated workspace API and browser sign-in from the VM; classic-cluster back-end Private Link; genuine external public-denial checks; verify managed RG locations; ask Microsoft/Databricks about supported CMK routing. Selected-networks IP test remains blocked by the management-group modify policy. Secret scan/full history review/local commit not done; no push authorized; cleanup requires separate approval.

## Required update discipline

Before each major action announce intent, mark the active task here, then execute and verify. Update the guide, inventory, journal and dashboard immediately after the outcome. Failed and blocked actions stay in the journal. Never equate a planned operation with an executed one. Earlier status entries are chronological history; the current-state section and latest update supersede their pending/failed descriptions.
