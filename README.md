# Azure Databricks private-network CMK security lab

## Project dashboard

**Baseline infrastructure deployed and verified in Azure (Korea Central). Managed Services CMK FAILS with the vault at bypass `None` (the requested private-only posture) and WORKS when only the trusted-services bypass is changed to `AzureServices`. The vault is currently left at `AzureServices`, which deviates from the stated requirement; a decision is needed.**

Last documentation update: 2026-10-18.

### Objective and current finding

Determine whether **Managed Services CMK** (control-plane notebook source, queries and related metadata) works with Azure Key Vault using **public network access disabled, trusted-services bypass None, Private Endpoint only**. Separately validate a Premium, VNet-injected, private-access-only Azure Databricks workspace from the existing VM.

**No documented/configurable customer-private-endpoint route for Managed Services CMK was found.** A Key Vault Private Endpoint in the workspace VNet does not connect the Databricks control plane to that VNet. NCC serves serverless compute, not Managed Services CMK. Do not deploy on the assumption that these features solve the CMK requirement.

**Experimental result:** applying Managed Services CMK with the vault set to public access Disabled, trusted-services bypass `None` and private-endpoint-only access **failed**. The Databricks control plane's first request (`KeyGet`) was rejected with HTTP 403 `ForbiddenByConnection`. The vault audit log shows the caller as the AzureDatabricks application, classified `TrustedService=AzureDatabricks`, arriving from a **public Azure address**, not through any customer private endpoint. This matches the documentation review: the CMK configuration takes only a vault URI, key name and version, with no private-route field. NCC serves serverless compute, not Managed Services CMK.

**Why:** Microsoft documents Azure Databricks as a Key Vault *trusted service* that reaches the vault through the firewall bypass, which "continues to apply when public access is disabled" so "listed services don't require a private endpoint". That is the documented design for this feature. A requirement of private-endpoint-only access with bypass `None` therefore cannot be met for Managed Services CMK as documented. What a private endpoint can serve is traffic that originates in your network (the VM, and classic compute in the injected VNet), which is a different path.

Current overall result, **two statements that must be read together:**

1. **Requested configuration (public access Disabled, bypass `None`, private endpoint only): 3 — Unsupported or not configurable, as observed. Official support unconfirmed.** Limits: one attempt, one workspace, one region; Microsoft/Databricks not yet asked.
2. **Documented trusted-service configuration (public access Disabled, bypass `AzureServices`): functionally validated.** Changing only the bypass made the same CMK deployment succeed. The workspace is `Succeeded` with the managed-services key applied, and the vault audit log shows the Databricks control plane's `KeyGet` (200, three times) and `KeyUnwrap` (200) with `IsRbacAuthorized=true`. The caller is still a **public Azure address** classified `TrustedService=AzureDatabricks`, so this path is **not** a private endpoint. It matches what Microsoft documents. Official support for the exact lab topology is still unconfirmed.

See [results](docs/results.md).

**Control experiment (2026-10-18, user-approved):** one setting changed, `bypass: None` to `AzureServices`. A side-by-side table of both runs is in [results](docs/results.md). Public access stayed Disabled, default action stayed Deny, no IP rules were added. The first failure was therefore a network-policy denial, not a permission problem: RBAC (the Crypto Service Encryption User role) was already correct and passed once the network layer let the request through.

**Observation O-1:** earlier, while the vault was private-only and before any private endpoint existed, creating a key through Azure Resource Manager was also refused with `ForbiddenByConnection`. Together with the CMK result, this shows the vault enforces the policy against Microsoft first-party services on the public path.

### Status

| Phase | State | Summary |
| --- | --- | --- |
| 1 — Feasibility/research | Completed (with open support question) | Documentation reviewed; preflight collected; login, providers, policies, permissions and Korea Central availability verified. CMK private-only route remains undocumented |
| 2 — Deployment plan | Completed | Plan approved by the user's instruction to create resources; deviations recorded in the deployment guide |
| 3 — Deployment | In Progress | Baseline succeeded; key created privately; VM peered to both new VNets (approved); CMK failed at bypass None, then succeeded after the approved bypass change; target workspace `Succeeded` with the managed-services key applied |
| 4 — Validation | In Progress | Vault lockdown, private reachability from the VM, the CMK outcome and the control experiment verified; authenticated API, public-denial and negative-control tests not run |
| 5 — Reporting | In Progress | Living records current; final report pending |
| 6 — Cleanup | Not Started | Not authorized; nothing removed |

### Deployed architecture (summary)

Two new Korea Central VNets in one new resource group: a **workspace VNet** (two delegated host/container subnets, a private-endpoint subnet, NAT gateway for outbound) and a **transit VNet** (auth workspace subnets and a private-endpoint subnet). One `databricks_ui_api` private endpoint (front-end and back-end roles) and one `browser_authentication` endpoint serve two Premium workspaces with public access disabled. The Key Vault has **two** private endpoints: one in the workspace VNet (resolved through a shared private DNS zone linked to both new VNets) and one in the **existing VM's subnet** with a vault-specific private DNS zone linked only to the VM's VNet. The VM's VNet is peered directly with both new VNets and linked to the Databricks private DNS zone.

The vault private endpoints let clients in those networks reach the vault privately. They do **not** give the Databricks control plane a private route to the vault, so they do not by themselves prove Managed Services CMK works privately.

Azure creates separate Databricks-managed resource groups. Key Vault purge protection leaves a soft-deleted vault after resource-group deletion. Immediate residue-free cleanup cannot be promised.

### Deployed resources and verified state

Verified in Azure after the Baseline stage succeeded (all 8 deployment modules `Succeeded`):

| Item | Verified state |
| --- | --- |
| Resource group and regional resources | New RG; every regional resource in `koreacentral` |
| Both Databricks workspaces | Premium, provisioning `Succeeded`, public network access **Disabled**, required NSG rules `NoAzureDatabricksRules`. The target workspace now carries the managed-services key (key vault URI, key name and pinned version) |
| Target workspace VNet injection | Custom VNet with new host and container subnets, `enableNoPublicIp=true` |
| Workspace private endpoint connections | Approved (`databricks_ui_api`, `browser_authentication`) |
| Key Vault | Public access **Disabled**, trusted-services bypass **`AzureServices` (changed from `None` for the control experiment; deviates from the requirement)**, default action Deny, no IP rules, purge protection on, RBAC on |
| Vault private endpoints | Both Approved/Succeeded |
| Vault DNS from the VM | Resolves to a **private** address |
| Key `cmk-managed-services` | Created from the VM over the private endpoint; enabled |
| Private DNS zones | Databricks and vault zones linked to the new VNets; VM-only vault zone linked to the VM VNet |

**Not yet verified or run:** authenticated API access and browser sign-in from the VM; public-denial tests from an external network; cluster back-end connectivity; whether the Databricks-managed resource groups are in Korea Central.

**Private reachability from the VM (verified):** the workspace and browser-authentication names resolve to private addresses, the TCP peer is private, TLS validates against the real hostname, and HTTPS returns a 303 redirect to sign-in. This shows the private path works, not that the public path is blocked.

Changes outside the PoC resource group: two VNet peering links on the existing VM VNet, one private IP in the VM's existing subnet (the endpoint resource itself is in the PoC RG), and two private DNS zone links to the VM's VNet. The VM, its NIC, NSG and routes were not modified. Databricks also created two managed resource groups and four network intent policies.

No commit, secret scan or push has been performed. **No push is authorized.**

### Next actions / approval gates

1. **Decision needed — the vault is currently at bypass `AzureServices`.** Managed Services CMK cannot be disabled once enabled, and the workspace now depends on the vault. Options: (a) leave it for further tests and revert when finished; (b) restore `None` now with `scripts/deploy/Set-VaultBypass.ps1 -Bypass None`. Restoring `None` should make the control plane's key requests fail again once its cached key expires (the cache interval is not documented), which would degrade the workspace. That is also a useful negative control (NEG-CMK-01) but needs your go-ahead.
2. Ask Microsoft/Databricks whether Managed Services CMK supports a private-only vault and how the route is configured.
3. Authenticated API access and a browser sign-in from the VM; public-denial tests from a genuinely external network; negative controls.
4. Cleanup, commit and publication each need separate approval. Cleanup must also delete the two peering links on the existing VM VNet and the DNS zone links.

### Documentation

- [Progress tracker](docs/progress.md)
- [Feasibility and official references](docs/feasibility.md)
- [Architecture and flows](docs/architecture.md)
- [Proposed deployment plan](docs/deployment-plan.md)
- [Chronological deployment guide](docs/deployment-guide.md)
- [Resource inventory](docs/resource-inventory.md)
- [Engineering journal](docs/experiment-log.md)
- [Test plan](docs/test-plan.md) and [results](docs/results.md)
- [Read-only validation tooling](scripts/validate/README.md)
- [Deployment guide and script reference](scripts/deploy/README.md) and [cleanup design](scripts/cleanup/README.md)
- [Publication safety](docs/publication-safety.md)

All documentation is sanitized. Actual identifiers, addresses, configuration and raw diagnostics belong only in ignored local storage, never Git. Infrastructure is defined in [infra/main.bicep](infra/main.bicep) and its modules, deployed by [Deploy-Poc.ps1](scripts/deploy/Deploy-Poc.ps1). Cleanup automation is not yet implemented.
