# Azure Databricks private-network CMK security lab

## Abstract

This Korea Central PoC tested whether Azure Databricks Managed Services CMK can use Key Vault with public network access disabled, trusted-services bypass `None`, and customer Private Endpoint-only connectivity. The strict configuration failed with `ForbiddenByConnection`; a Databricks-created NCC connection was Approved on the vault, but the CMK request still failed. The NCC attachment and `ESTABLISHED` rule state were not independently verified. CMK succeeded when the trusted-services bypass was set to `AzureServices`, and also when an Enforced Network Security Perimeter (NSP) admitted the observed Databricks control-plane IP while bypass remained `None`. Removing that NSP rule caused `ForbiddenByNsp`; restoring it and applying a new key version succeeded. Audit logs confirmed successful key retrieval/unwrap and RBAC authorization.

**Conclusion:** the tested NSP configuration works functionally, but it admits a public control-plane source—it does not route CMK through a customer Private Endpoint. The requested private-endpoint-only CMK path was not achieved, and official support remains unconfirmed. The workspace is currently `Succeeded`; the vault is public access Disabled / bypass `None`, with the NSP rule retained. Authentication, classic-cluster back-end, external-denial and vendor-support checks remain.

## Project dashboard

**Baseline infrastructure deployed and verified in Azure (Korea Central). Managed Services CMK failed with bypass `None` and private-endpoint-only access; succeeded when only the trusted-services bypass changed to `AzureServices`; and failed again with bypass `None` plus an approved Databricks NCC connection. With bypass `None`, an Enforced NSP plus one inbound control-plane address rule succeeded; removing that rule failed with `ForbiddenByNsp`, and restoring it then applying another key version succeeded. The successful control-plane requests used a public address, not a customer private endpoint. The target workspace is currently `Succeeded` with CMK. **The vault remains inside the Enforced perimeter with that rule; it is reachable from one shared Databricks address. This deviates from private-endpoint-only; a keep-or-teardown decision remains (see next actions).**

Last documentation update: 2026-10-18.

### Objective and current finding

Determine whether **Managed Services CMK** (control-plane notebook source, queries and related metadata) works with Azure Key Vault using **public network access disabled, trusted-services bypass None, Private Endpoint only**. Separately validate a Premium, VNet-injected, private-access-only Azure Databricks workspace from the existing VM.

**No documented/configurable customer-private-endpoint route for Managed Services CMK was found.** A Key Vault Private Endpoint in the workspace VNet does not connect the Databricks control plane to that VNet. NCC serves serverless compute, not Managed Services CMK. Do not deploy on the assumption that these features solve the CMK requirement.

**Experimental result:** applying Managed Services CMK with the vault set to public access Disabled, trusted-services bypass `None` and private-endpoint-only access **failed**. The Databricks control plane's first request (`KeyGet`) was rejected with HTTP 403 `ForbiddenByConnection`. The vault audit log shows the caller as the AzureDatabricks application, classified `TrustedService=AzureDatabricks`, arriving from a **public Azure address**, not through any customer private endpoint. This matches the documentation review: the CMK configuration takes only a vault URI, key name and version, with no private-route field. NCC serves serverless compute, not Managed Services CMK.

**Why:** Microsoft documents Azure Databricks as a Key Vault *trusted service* that reaches the vault through the firewall bypass, which "continues to apply when public access is disabled" so "listed services don't require a private endpoint". That is the documented design for this feature. A requirement of private-endpoint-only access with bypass `None` therefore cannot be met for Managed Services CMK as documented. What a private endpoint can serve is traffic that originates in your network (the VM, and classic compute in the injected VNet), which is a different path.

Current experimental results, **read together:**

1. **Requested configuration (public access Disabled, bypass `None`, private endpoint only): failed in the direct test. Official support unconfirmed.** The direct attempt and the NCC attempt failed with `ForbiddenByConnection`; Microsoft/Databricks have not been asked.
2. **Documented trusted-service configuration (public access Disabled, bypass `AzureServices`): functionally validated.** Changing only the bypass made the same CMK deployment succeed. The workspace is `Succeeded` with the managed-services key applied, and the vault audit log shows the Databricks control plane's `KeyGet` (200, three times) and `KeyUnwrap` (200) with `IsRbacAuthorized=true`. The caller is still a **public Azure address** classified `TrustedService=AzureDatabricks`, so this path is **not** a private endpoint. It matches what Microsoft documents. Official support for the exact lab topology is still unconfirmed.
3. **Bypass `None` plus an approved NCC private endpoint rule to the vault: failed (test CMK-NCC-01).** Same 403 `ForbiddenByConnection`, same public caller address, `IsRbacAuthorized` empty. NCC did not carry the control plane's key request, which matches Microsoft documenting NCC for serverless compute only. One attempt; the NCC rule status and workspace attachment were reported by the account admin and not read by us.

4. **Bypass `None`, vault inside an Enforced network security perimeter with one inbound address rule: succeeded (CMK-NSP-02).** The vault stayed public Disabled with no Key Vault IP rules. CMK-NSP-03 then removed the NSP rule: phase A failed with 403 `ForbiddenByNsp`; after restoring it and applying another new key version, phase B succeeded. The final audit showed `KeyGet`/`KeyUnwrap` 200 and `IsRbacAuthorized=true`. Phase A's audit row and NSP access-log correlation were unavailable, and the NCC connection remained Approved. Microsoft does not document Managed Services CMK with an NSP, so official support is unconfirmed. **This is still a public control-plane path, not a private endpoint path.**

Summary: bypass `None` without an NSP rule failed; bypass `AzureServices` succeeded; bypass `None` with NCC failed; Enforced NSP with its inbound rule succeeded; removing the rule failed with `ForbiddenByNsp`; restoring it succeeded.

See [results](docs/results.md).

**Control experiment (2026-10-18, user-approved):** one setting changed, `bypass: None` to `AzureServices`. A side-by-side table of both runs is in [results](docs/results.md). Public access stayed Disabled, default action stayed Deny, no IP rules were added. The first failure was therefore a network-policy denial, not a permission problem: RBAC (the Crypto Service Encryption User role) was already correct and passed once the network layer let the request through.

**Observation O-1:** earlier, while the vault was private-only and before any private endpoint existed, creating a key through Azure Resource Manager was also refused with `ForbiddenByConnection`. Together with the CMK result, this shows the vault enforces the policy against Microsoft first-party services on the public path.

### Status

| Phase | State | Summary |
| --- | --- | --- |
| 1 — Feasibility/research | Completed (with open support question) | Documentation reviewed; preflight collected; login, providers, policies, permissions and Korea Central availability verified. CMK private-only route remains undocumented |
| 2 — Deployment plan | Completed | Plan approved by the user's instruction to create resources; deviations recorded in the deployment guide |
| 3 — Deployment | Completed | Baseline, VM peering and CMK setup complete; target workspace currently `Succeeded` with Managed Services CMK |
| 4 — Validation | In Progress | Private VM reachability and bypass/NCC/NSP CMK tests complete, including the NSP negative/repeat; authenticated API/browser, classic cluster back-end and external public-denial tests remain |
| 5 — Reporting | In Progress | Living documentation synchronized with CMK-NSP-03; external support response and final report pending |
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
| Key Vault | Public access **Disabled**, bypass **`None`**, default action Deny, no Key Vault IP rules, purge protection and RBAC on; associated with an **Enforced NSP with one inbound control-plane `/32` rule** |
| Network security perimeter | Vault association Enforced; one inbound rule present; Log Analytics association Learning/Transition; removal of the rule failed CMK with `ForbiddenByNsp`, restoration succeeded |
| Vault private endpoints | Both Approved/Succeeded |
| Vault DNS from the VM | Resolves to a **private** address |
| Key `cmk-managed-services` | Created from the VM over the private endpoint; enabled |
| Private DNS zones | Databricks and vault zones linked to the new VNets; VM-only vault zone linked to the VM VNet |

**Not yet verified or run:** authenticated API access and browser sign-in from the VM; public-denial tests from an external network; cluster back-end connectivity; whether the Databricks-managed resource groups are in Korea Central.

**Private reachability from the VM (verified):** the workspace and browser-authentication names resolve to private addresses, the TCP peer is private, TLS validates against the real hostname, and HTTPS returns a 303 redirect to sign-in. This shows the private path works, not that the public path is blocked.

Changes outside the PoC resource group: two VNet peering links on the existing VM VNet, one private IP in the VM's existing subnet (the endpoint resource itself is in the PoC RG), and two private DNS zone links to the VM's VNet. The VM, its NIC, NSG and routes were not modified. Databricks also created two managed resource groups and four network intent policies.

No commit, secret scan or push has been performed. **No push is authorized.**

### Next actions / approval gates

1. Remove the NCC private endpoint rule from the Databricks account console when authorized; it may incur hourly charges until removed. The foreign vault connection may persist temporarily after rule deletion.
2. Decide whether to retain the current Enforced NSP rule for continued operation or approve a safe teardown. CMK-NSP-03 showed that removing the rule blocks a CMK update; the impact of cached-key expiry is not documented. Do not remove the rule or association without a recovery plan.
3. Ask Microsoft/Databricks whether Managed Services CMK supports private-only vault access or NSP-based access, and how the control-plane route is configured.
4. Complete authenticated API and browser sign-in from the VM; test classic-cluster back-end Private Link; run public-denial tests from an independent external network; verify the Databricks-managed RG locations.
5. Secret scan, full Git history review and local commit remain undone. Commit/publishing and cleanup each need separate approval. Cleanup must also address the two peering links and DNS links affecting the existing VM VNet.

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
