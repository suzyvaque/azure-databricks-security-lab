# Phase-by-phase progress

Session dates: 2026-10-17 to 2026-10-18. Exact UTC times were not captured for most steps; date-level entries are intentional.

**Overall: Baseline infrastructure deployed and verified; VM peered; Managed Services CMK experiment run and failed under the private-only vault settings (result 3, support unconfirmed). Target workspace is in `Failed` provisioning state. Connectivity beyond reachability, public-denial tests, cleanup and publication pending.**

| Phase | Status | Start | Completion | Tasks completed | Resources created/modified | Tests/outcomes | Issues | Next actions |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 — Feasibility and architecture research | Completed (open support question) | 2026-10-17 | 2026-10-17 | Official-source research; preflight run and reviewed (login, providers, policies, permissions, Korea Central availability, quota); VM network inspected | Local files only | Preflight 18/18 collected; VM network read | CMK private-only route undocumented; support question unanswered; Git commit and secret scan not done | Ask Microsoft/Databricks about private-only CMK |
| 2 — Infrastructure deployment plan | Completed | 2026-10-17 | 2026-10-17 | Plan drafted; user instructed resource creation | None | Not applicable | Deviations from plan (see guide) | None |
| 3 — Deployment and configuration | In Progress | 2026-10-17 | — | Baseline stage Succeeded (8/8 modules); key created over the private endpoint; vault status verified | New RG and resources in Korea Central; one IP in VM subnet; one DNS link to VM VNet | Config verified in Azure | Template defect (NSG intent rules) found and fixed; ARM key creation refused by private-only vault (design changed) | Approval for VM peering; CMK stage |
| 4 — Security and functional validation | In Progress | 2026-10-18 | — | Vault lockdown, private DNS from VM and key enablement verified; Databricks configuration verified | None | See results.md | Workspace not reachable from VM until peered; no external test vantage | Peering decision, CMK stage, public-denial and audit-log tests |
| 5 — Final reporting | Not Started | — | — | Living records initialized, not final results | Local docs only | Not applicable | No evidence yet | Keep evidence/status synchronized |
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

## Required update discipline

Before each major action announce intent, mark the active task here, then execute and verify. Update the guide, inventory, journal and dashboard immediately after the outcome. Failed and blocked actions stay in the journal. Never equate a planned operation with an executed one.
