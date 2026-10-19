# Deployment

## Latest execution and retained state — 2026-10-19

Both owner-approved new-version tests completed. **CMK-IP-03** ran 01:18:23–01:21:01 UTC with vault Enabled / Deny / None / one control-plane IP / zero VNet rules, PoC NSP absent. Deployment/workspace `Succeeded`, new version applied, tags/posture preserved. Audit: three Get and one Unwrap, all 200, RBAC and address authorization true, public source matching allowed IP.

**CMK-NSP-TAG-01** then accepted a native Inbound `serviceTags=['AzureDatabricks']` rule in a new isolated Korea Central NSP/profile (provisioning Succeeded, zero address prefixes). Vault association Enforced, LAW Learning/Transition; vault Disabled / None / Deny / zero firewall IP and VNet rules. Another version was created privately and only the target workspace updated. CMK start 01:29:16.8501Z; script finish 01:31:27.6947Z; workspace `Succeeded`, new version applied, owner tags preserved. Audit includes Unwrap 200 at 01:30:18 UTC, RBAC true, TrustedService AzureDatabricks, public source; no Get count or address-authorization claim for this run.

**Do not rerun or restore automatically:** current workspace is private, PNA Disabled and `Succeeded`; current vault is Disabled / None / Deny / zero IP and VNet rules, with Enforced native-tag NSP and owner policy-exclusion tag retained; LAW Learning. NCC remains Approved, a confounder (NCC alone failed earlier). No tag-removal negative control, external public-denial validation or vendor confirmation exists; not customer PE-only. Retain all prior key versions, with at least 24 hours of old-version availability after rotation. The native tag is cloud-wide, not workspace-specific or a regional/custom-tag guarantee; concepts says Preview while CLI/ARM says unavailable. See [scope, feed variations and reference conflict](../../docs/feasibility.md#native-nsp-service-tag-scope-and-documentation-conflict). These are execution records, not permission for further changes.

## Executable entry points

- [Test-NspServiceTagCmk.ps1](Test-NspServiceTagCmk.ps1) requires explicit owner confirmation and a working selected-IP baseline. Creates an isolated Korea Central NSP/profile and tries one native AzureDatabricks inbound service-tag rule; proceeds to vault association/access changes only after rule read-back matches. No prefix expansion, alternate-tag fallback or policy registration. If accepted, associates vault Enforced and LAW Learning, removes vault IP rules, sets Disabled/None/Deny, creates a version over the VM PE and updates only the target workspace via [infra/cmk-workspace-only.bicep](../../infra/cmk-workspace-only.bicep). Retains owner tags and prior key versions; no automatic recovery. Raw evidence remains ignored/local. Already executed successfully; the helper refuses reuse of its existing test perimeter, so it is not a generic rerun/cleanup procedure.

- [Restore-WorkspaceExistingCmk.ps1](Restore-WorkspaceExistingCmk.ps1) is an explicitly confirmed, target-workspace-only recovery. It verifies PoC ownership, private workspace settings, selected-IP vault posture and the existing key's enablement, then reapplies the currently pinned CMK version through the targeted template. It creates no new key version and does not redeploy the vault, overwrite its tags, enable bypass, recreate NSP or remove NCC. It verifies final workspace state, key version, vault ACLs and tags. Recovery may itself generate CMK key requests; do not describe it as an independent new-version test.

- [Test-SelectedIpCmk.ps1](Test-SelectedIpCmk.ps1) requires owner confirmation and verifies Enabled/Deny/bypass None, exactly one approved control-plane IP, no VNet rules and no PoC NSP. Creates a fresh enabled key over the VM PE and deploys only [infra/cmk-workspace-only.bicep](../../infra/cmk-workspace-only.bicep) to the target workspace. It preserves the vault's owner-supplied policy-exclusion tag by never redeploying the vault template; all prior key versions remain. Full state, identifiers, tags and errors stay in ignored local evidence; result requires workspace/key-version and vault-posture/tag read-back. No automatic rollback or additional policy/NCC changes.

- [Test-CmkWithoutPerimeter.ps1](Test-CmkWithoutPerimeter.ps1) is the explicit-confirmation, owner-approved CMK-IP-02 follow-up: checks PoC RG ownership, saves the existing single NSP prefix locally, removes the PoC perimeter, verifies absence, stores that prefix in the Key Vault IP firewall, keeps public access Disabled/bypass None, creates a new key version through the VM PE, and retries CMK while preserving the stored rule. It never enables public access, alters policy, removes NCC, or automatically restores NSP. The stored IP rule is inactive with public access Disabled; this is a negative experiment, not active selected-network access. A failed update can leave the workspace `Failed`. Evidence remains local-only.

All run from the PowerShell Extension terminal. State, parameters and transcripts go to ignored `.local/deploy`.

- [Deploy-Poc.ps1](Deploy-Poc.ps1) deploys [infra/main.bicep](../../infra/main.bicep) into one **new** resource group in `koreacentral`. `-ValidateOnly` compiles only; `-Stage Baseline` deploys; `-Stage Cmk -KeyVersion <version>` applies Managed Services CMK. If `.local/vm/subnet-id.txt` exists (from the VM probe) it also creates a vault endpoint in the VM's subnet. It is idempotent: a rerun reuses the saved run ID.
- [New-CmkKey.ps1](New-CmkKey.ps1) creates the key from this VM over the private endpoint. It stops unless the vault resolves privately, never enables public access or bypass, and grants Crypto Officer on the vault only.

After `-Stage Baseline` was run, a rerun must keep the Databricks network intent rules in the NSGs; the template now includes them.

- [Set-VaultBypass.ps1](Set-VaultBypass.ps1) changes **only** the vault's trusted-services bypass (`-Bypass None` or `-Bypass AzureServices`), prints the vault's network settings before and after, and refuses to finish if public access is not Disabled. Use `-Bypass None` to restore the lab posture. `Deploy-Poc.ps1` takes `-VaultBypass` (default `None`) so a redeploy never silently resets the setting. Run `-Stage Cmk -VaultBypass AzureServices` while the vault is at `AzureServices`.

- [Approve-VaultConnection.ps1](Approve-VaultConnection.ps1) approves exactly one **named, currently Pending** private endpoint connection on the vault (for the NCC test). It refuses connections that belong to our own endpoints and prints the state before and after. See the [Stage 1 runbook](../../docs/deployment-plan.md#stage-1-runbook-ncc-test).

The CMK stage is the experiment's decisive step. The trusted-services bypass `AzureServices` was used only for the separately approved control experiment; it is not the requested private-only posture. Do not enable it or public access as an unapproved workaround.

Run state, CIDRs and a transcript go to ignored `.local/deploy`. VM peering/DNS beyond the vault endpoint were completed through the separately approved [Connect-VmPeering.ps1](Connect-VmPeering.ps1) workflow; review the [inventory](../../docs/resource-inventory.md) before reruns or cleanup.

**Deviation from the earlier draft:** explicit egress uses a NAT gateway (cheap, **unfiltered** outbound), not a filtering firewall. Back-end Private Link does not make all dependency traffic private.

## Original deployment gate (historical)

The initial Phase 1 design intentionally did not include a deployment entry point. The user later approved deployment; Bicep modules and executable scripts now exist and were run. This section retains the original authorization gates as a record, not as current deployment status.

The preflight completed and Azure deployment succeeded. The private-only CMK support question remains unresolved. Do not confuse the completed experiment with vendor support or production readiness.

The [draft plan](../../docs/deployment-plan.md) defines the future modules and order. Implement pinned Bicep/ARM modules and idempotent PowerShell orchestration only after:

1. Read-only Azure/VM inspection and exact Korea Central readiness pass.
2. The unsupported/undocumented CMK route question is resolved, or the owner explicitly approves a clearly labeled negative experiment.
3. Address ranges, DNS topology, explicit egress destinations/SKU, managed-RG and vault-retention exceptions, budget and existing-network changes are approved.
4. The owner explicitly approves Azure deployment. Deployment approval is not approval for a public-access workaround.

Future scripts must require explicit target subscription/RG confirmation from ignored local configuration, reject existing PoC RGs unless a verified run manifest establishes ownership, reject every region other than `koreacentral` for regional resources, check resource IDs/tags and stage dependencies, keep workspace/vault PNA disabled from creation, emit no credentials, and never run cleanup on failure without separate approval. Global DNS resources must use `global` where Azure requires it.

Provisioning templates and deployment commands are implemented in `infra/` and `Deploy-Poc.ps1` and were used for the PoC. The selected-networks script was initially blocked by Azure Policy; the owner's later policy-exclusion tag allowed CMK-IP-03 to run successfully. Do not treat generic public-enable examples as approval or use a full redeploy that could overwrite owner tags/current posture. Read-only validation commands are documented in the validation script reference.

- [Set-VaultIpAllowlist.ps1](Set-VaultIpAllowlist.ps1) sets the vault to the Stage 2 posture (public network access Enabled for selected networks, default Deny, bypass None, exactly one allowed public address) or, with `-Restore`, back to the lab posture. It refuses private ranges and CIDRs wider than /24, prints the vault settings before and after, and stops if the intended posture is not reached. **Historical blocker:** a management-group modify policy initially forced Disabled; later the owner's exclusion tag allowed Enabled to persist. Always verify read-back; a successful write alone is insufficient. A failed gate can leave a stored IP rule; any restoration needs approval and must account for the current Enforced native-tag NSP. `Deploy-Poc.ps1` also takes `-VaultPublicNetworkAccess` and `-VaultAllowedIps` (defaults: Disabled, none); it is not the tag-preserving workspace-only path used in the latest tests.

- [Set-VaultPerimeter.ps1](Set-VaultPerimeter.ps1) manages the network security perimeter around the PoC vault for the NSP test: `-Action Setup` (perimeter, profile, vault and Log Analytics associations in Transition mode), `AddRule` (one inbound public address), `Enforce` (vault association only), `Transition`, `Status` and `Remove`. It prints the vault's network settings before and after, never prints addresses, and needs the Azure CLI `nsp` extension. Removing the association of a vault whose public network access is SecuredByPerimeter locks the vault down, so remove the perimeter only when you intend to.
