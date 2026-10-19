# Azure Databricks private-network CMK security lab

**Selected-networks clarification and retry — 2026-10-19:** the user means the portal option **Allow public access from specific virtual networks and IP addresses**, i.e. PNA Enabled, default Deny, bypass None, one control-plane IP rule. After NSP removal we explicitly attempted that configuration. Before/after read-back remained PNA Disabled / None / Deny / one IP rule / zero VNet rules; the script stopped with “Stage 2 posture not reached.” The intended selected-networks CMK test is **blocked, not failed or passed**. The preceding Disabled-PNA CMK denial is a separate negative test and is not a selected-networks result. No additional CMK update was run after the blocked configuration attempt; workspace remains `Failed` with its prior CMK version. The previously identified organization modify policy is the known blocker; no policy exemption was attempted.

> **Latest verified state — 2026-10-19 local date (2026-10-18 23:54 UTC):** PoC NSP removed. Vault public access Disabled, bypass `None`, default Deny, one stored control-plane IP firewall rule. CMK-IP-02 failed with HTTP 403 `ForbiddenByConnection`; workspace provisioning state is `Failed`, with the prior CMK version retained. No public access, bypass or NSP recovery was enabled. A stored IP rule does not admit public traffic while public access is Disabled.

## Abstract

This Korea Central PoC tested whether Azure Databricks Managed Services CMK can use Key Vault with public network access disabled, trusted-services bypass `None`, and customer Private Endpoint-only connectivity. The strict configuration failed with `ForbiddenByConnection`; a Databricks-created NCC connection was Approved on the vault, but the CMK request still failed. The NCC attachment and `ESTABLISHED` rule state were not independently verified. CMK succeeded when the trusted-services bypass was set to `AzureServices`, and also when an Enforced Network Security Perimeter (NSP) admitted the observed Databricks control-plane IP while bypass remained `None`. Removing that NSP rule caused `ForbiddenByNsp`; restoring it and applying a new key version succeeded. Audit logs confirmed successful key retrieval/unwrap and RBAC authorization.

The final follow-up removed NSP, kept public access Disabled and bypass `None`, stored the control-plane address in the vault firewall, and retried CMK with a new key version. It failed with `ForbiddenByConnection`; the IP rule did not override public access Disabled. Active selected-network IP access requires public access Enabled, which this request excluded and previous organizational-policy tests prevented.

**Conclusion:** the requested private-endpoint-only CMK path was not achieved. The successful NSP variant admitted a public control-plane source, not a customer Private Endpoint route; official support remains unconfirmed. NSP is now removed and the workspace is `Failed` with its prior CMK version retained. Recovery requires a separately approved working admission path. Authentication, classic-cluster back-end, external-denial and vendor-support checks remain.

## Project dashboard

**Baseline infrastructure remains deployed in Korea Central. Seven CMK attempts establish that the requested private-only configuration failed; trusted-service bypass and an Enforced NSP address rule each admitted the public control-plane caller. In the final test, the owner-approved NSP removal plus one stored vault IP rule at public Disabled / bypass `None` again failed with `ForbiddenByConnection`. NSP is absent; the target workspace is currently `Failed` with its previous CMK version. Recovery or full cleanup requires a separate decision.**

Last documentation update: 2026-10-19 (local date). The latest-state note above supersedes the historical run summaries below.

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

**Final run 7 / CMK-IP-02:** NSP deleted; public Disabled / bypass `None` / Deny; one stored control-plane IP firewall rule; new key version applied. Update failed with 403 `ForbiddenByConnection` (23:51:10–23:54:05 UTC on 2026-10-18). Workspace now `Failed`, prior key version retained. This tests the requested flags, not active selected-network admission.

See [results](docs/results.md).

**Control experiment (2026-10-18, user-approved):** one setting changed, `bypass: None` to `AzureServices`. A side-by-side table of both runs is in [results](docs/results.md). Public access stayed Disabled, default action stayed Deny, no IP rules were added. The first failure was therefore a network-policy denial, not a permission problem: RBAC (the Crypto Service Encryption User role) was already correct and passed once the network layer let the request through.

**Observation O-1:** earlier, while the vault was private-only and before any private endpoint existed, creating a key through Azure Resource Manager was also refused with `ForbiddenByConnection`. Together with the CMK result, this shows the vault enforces the policy against Microsoft first-party services on the public path.

### Status

| Phase | State | Summary |
| --- | --- | --- |
| 1 — Feasibility/research | Completed (with open support question) | Documentation reviewed; preflight collected; login, providers, policies, permissions and Korea Central availability verified. CMK private-only route remains undocumented |
| 2 — Deployment plan | Completed | Plan approved by the user's instruction to create resources; deviations recorded in the deployment guide |
| 3 — Deployment | Completed; recovery decision open | Baseline, VM peering and CMK configured; final no-NSP update failed; target provisioning state `Failed`, previous CMK retained |
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
| Databricks workspaces | Premium, public network access **Disabled**, required NSG rules `NoAzureDatabricksRules`. Target provisioning `Failed` after CMK-IP-02, previous managed-services key retained; the auth-only workspace is separate |
| Target workspace VNet injection | Custom VNet with new host and container subnets, `enableNoPublicIp=true` |
| Workspace private endpoint connections | Approved (`databricks_ui_api`, `browser_authentication`) |
| Key Vault | Public access **Disabled**, bypass **`None`**, default Deny, one stored control-plane IP firewall rule (inactive while public access Disabled), purge protection and RBAC on; no PoC NSP |
| Network security perimeter | Deleted under owner approval for CMK-IP-02; absence verified. Earlier NSP success/negative/repeat remains historical evidence |
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
2. Decide recovery or full cleanup. NSP is already removed and the latest workspace CMK update failed. Recreating the known-working NSP rule or enabling trusted-service bypass requires separate approval; neither was done automatically. Key-cache duration and runtime impact are undocumented; provisioning `Failed` is not proof that every workspace operation has already stopped.
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
