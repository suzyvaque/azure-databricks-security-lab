# Deployment

## Executable entry points

All run from the PowerShell Extension terminal. State, parameters and transcripts go to ignored `.local/deploy`.

- [Deploy-Poc.ps1](Deploy-Poc.ps1) deploys [infra/main.bicep](../../infra/main.bicep) into one **new** resource group in `koreacentral`. `-ValidateOnly` compiles only; `-Stage Baseline` deploys; `-Stage Cmk -KeyVersion <version>` applies Managed Services CMK. If `.local/vm/subnet-id.txt` exists (from the VM probe) it also creates a vault endpoint in the VM's subnet. It is idempotent: a rerun reuses the saved run ID.
- [New-CmkKey.ps1](New-CmkKey.ps1) creates the key from this VM over the private endpoint. It stops unless the vault resolves privately, never enables public access or bypass, and grants Crypto Officer on the vault only.

After `-Stage Baseline` was run, a rerun must keep the Databricks network intent rules in the NSGs; the template now includes them.

- [Set-VaultBypass.ps1](Set-VaultBypass.ps1) changes **only** the vault's trusted-services bypass (`-Bypass None` or `-Bypass AzureServices`), prints the vault's network settings before and after, and refuses to finish if public access is not Disabled. Use `-Bypass None` to restore the lab posture. `Deploy-Poc.ps1` takes `-VaultBypass` (default `None`) so a redeploy never silently resets the setting. Run `-Stage Cmk -VaultBypass AzureServices` while the vault is at `AzureServices`.

The CMK stage is the experiment's decisive step. Failure is a valid result and must not be worked around with public access or the trusted-services bypass.

Run state, CIDRs and a transcript go to ignored `.local/deploy`. VM peering/DNS beyond the vault endpoint is a separate approval-gated step not included here.

**Deviation from the earlier draft:** explicit egress uses a NAT gateway (cheap, **unfiltered** outbound), not a filtering firewall. Back-end Private Link does not make all dependency traffic private.

## Original deployment gate

**No executable deployment entry point or provisioning template is supplied in Phase 1.** This prevents a partial/unsupported design from being mistaken for an approved reproducible deployment.

Follow-up: user authorization to create new resources has been received. Execution remains blocked by terminal failure and unmet mandatory preflight/support/design gates. Do not confuse authorization with validated readiness; no Azure write has been attempted.

The [draft plan](../../docs/deployment-plan.md) defines the future modules and order. Implement pinned Bicep/ARM modules and idempotent PowerShell orchestration only after:

1. Read-only Azure/VM inspection and exact Korea Central readiness pass.
2. The unsupported/undocumented CMK route question is resolved, or the owner explicitly approves a clearly labeled negative experiment.
3. Address ranges, DNS topology, explicit egress destinations/SKU, managed-RG and vault-retention exceptions, budget and existing-network changes are approved.
4. The owner explicitly approves Azure deployment. Deployment approval is not approval for a public-access workaround.

Future scripts must require explicit target subscription/RG confirmation from ignored local configuration, reject existing PoC RGs unless a verified run manifest establishes ownership, reject every region other than `koreacentral` for regional resources, check resource IDs/tags and stage dependencies, keep workspace/vault PNA disabled from creation, emit no credentials, and never run cleanup on failure without separate approval. Global DNS resources must use `global` where Azure requires it.

Exact provisioning commands and tested templates are deferred, not claimed as delivered. Read-only commands already exist in the validation script. Do not run generic documentation examples that enable public network access.
