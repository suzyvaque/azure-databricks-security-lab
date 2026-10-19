# Deployment

## Executable entry points

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

Provisioning templates and deployment commands are implemented in `infra/` and `Deploy-Poc.ps1` and were used for the PoC. The selected-networks setting script was also exercised but blocked by Azure Policy; do not treat generic examples that enable public network access as an approved workaround. Read-only validation commands are documented in the validation script reference.

- [Set-VaultIpAllowlist.ps1](Set-VaultIpAllowlist.ps1) sets the vault to the Stage 2 posture (public network access Enabled for selected networks, default Deny, bypass None, exactly one allowed public address) or, with `-Restore`, back to the lab posture. It refuses private ranges and CIDRs wider than /24, prints the vault settings before and after, and stops if the intended posture is not reached. **In this subscription the Enabled setting cannot be reached because a management-group Azure Policy forces Key Vault public network access to Disabled**; the script then stops, by design, with the IP rule left in place until `-Restore` is run. `Deploy-Poc.ps1` also takes `-VaultPublicNetworkAccess` and `-VaultAllowedIps` (defaults: Disabled, none) so a redeploy does not reset the vault setting.

- [Set-VaultPerimeter.ps1](Set-VaultPerimeter.ps1) manages the network security perimeter around the PoC vault for the NSP test: `-Action Setup` (perimeter, profile, vault and Log Analytics associations in Transition mode), `AddRule` (one inbound public address), `Enforce` (vault association only), `Transition`, `Status` and `Remove`. It prints the vault's network settings before and after, never prints addresses, and needs the Azure CLI `nsp` extension. Removing the association of a vault whose public network access is SecuredByPerimeter locks the vault down, so remove the perimeter only when you intend to.
