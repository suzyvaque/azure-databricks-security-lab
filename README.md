# Azure Databricks private-network CMK security lab

## Abstract

This Korea Central lab tests whether Azure Databricks **Managed Services CMK** can use Azure Key Vault with public network access Disabled, trusted-services bypass `None`, and **customer Private Endpoint-only connectivity**. The original strict configuration failed with `ForbiddenByConnection`; an Approved NCC connection did not make the CMK request private or successful. The `AzureServices` bypass control passed. Subsequent public-source allowance tests passed using an NSP IP rule, a selected-networks Key Vault IP rule, and, most recently, a native NSP `AzureDatabricks` service-tag rule.

**The requested PE-only CMK path was NOT achieved.** Both the selected-IP and service-tag successes admit a public control-plane source, not a customer Private Endpoint route. The current working configuration is the service-tag NSP variant with vault public access Disabled and bypass `None`. Functional success is not vendor support confirmation or a production endorsement.

For the successful service-tag test, the native `AzureDatabricks` tag was applied to an **NSP profile's inbound access rule**, not to the Key Vault IP firewall, a subnet NSG, NCC, or an Azure resource metadata tag. The vault was associated with that profile in **Enforced** mode, with **zero vault IP/VNet rules**. A new CMK version applied successfully and the audit confirmed `KeyUnwrap` HTTP 200. This permits a service-wide public source range; it is not workspace-specific. Preview/support status remains unconfirmed because the documentation is inconsistent.

## Latest verified state — 2026-10-19

**CMK-NSP-TAG-01 passed, 01:29:16–01:31:27 UTC.** A new isolated NSP in Korea Central accepted a native inbound `serviceTags` rule for `AzureDatabricks`; read-back was `Succeeded`, with no address prefixes. The vault association is **Enforced** and Log Analytics workspace (LAW) association is **Learning**.

| Component | Current verified state |
| --- | --- |
| Key Vault network controls | Public network access **Disabled**, bypass **`None`**, default **Deny**, **zero Key Vault IP rules and zero VNet rules**; policy-exclusion tags preserved without publishing their key/value |
| NSP | Native inbound `AzureDatabricks` service-tag rule working; vault Enforced, LAW Learning |
| Target workspace | Provisioning **`Succeeded`**, new CMK key version applied; public access **Disabled**, VNet injection and secure cluster connectivity (SCC) unchanged |
| Tag-run audit evidence | At least one `KeyUnwrap` HTTP 200 at **01:30:18 UTC**, RBAC authorized, `TrustedService=AzureDatabricks`, public source; `KeyGet` was **not observed** in the queried tag-run window |
| NCC | Third vault connection still **Approved**; retained confounder, not proof of a control-plane private route |
| Disposition | Retain the working tag-NSP configuration pending the owner's next decision; no automatic cleanup, commit or push |

Immediately before this, **CMK-IP-03 passed, 01:18:23–01:21:01 UTC** with a fresh key version: no NSP, vault public access Enabled from selected networks, default Deny, bypass `None`, one approved public control-plane IP and zero VNet rules. Audit showed **three `KeyGet` and one `KeyUnwrap`**, all HTTP 200 with `IsRbacAuthorized=true` and `IsAddressAuthorized=true`, from the approved public IP; tags were preserved. That selected-IP posture is historical, not the current vault configuration.

The owner applied a policy-exclusion tag before the selected-IP test; its key/value is intentionally not disclosed. The **00:55 UTC recovery** reapplied the existing pinned key version successfully **without rotation** and is historical; it is not evidence of a fresh-version test.

## Test summary

| Test / configuration | Outcome | Interpretation / limits |
| --- | --- | --- |
| Original PE-only request: vault public Disabled, bypass `None` | **Failed** — `ForbiddenByConnection` | Databricks control-plane request used a public source, not a customer PE |
| Trusted-service control: public Disabled, bypass `AzureServices` | **Passed** | Network admission enabled CMK with existing RBAC; public trusted-service path, not PE-only |
| CMK-NCC-01: bypass `None`, NCC vault connection Approved | **Failed** — `ForbiddenByConnection` | NCC did not establish a working private CMK path; attachment / `ESTABLISHED` state not independently verified |
| CMK-NSP-02 / CMK-NSP-03: Enforced NSP inbound IP rule | **Passed; removal failed; restoration passed** | Removing the rule produced `ForbiddenByNsp`; restoring it and applying a new key version succeeded. Public-source admission; negative-phase audit / NSP correlation incomplete |
| CMK-IP-02: NSP removed, stored KV IP rule, public Disabled / `None` | **Failed** — `ForbiddenByConnection` | A stored firewall IP rule does not admit public traffic while public access is Disabled; not a selected-networks test |
| Existing-key recovery, 2026-10-19 00:55 UTC | **Passed, no rotation** | Existing pinned version reapplied; caching limits conclusions about fresh key access |
| CMK-IP-03: no NSP, selected networks Enabled / Deny / `None`, one IP | **Passed** — 2026-10-19 01:18:23–01:21:01 UTC | Fresh version; three `KeyGet` + one `KeyUnwrap`, all 200, `IsRbacAuthorized=true` and `IsAddressAuthorized=true`; approved public source |
| CMK-NSP-TAG-01: native `AzureDatabricks` service tag, vault Enforced | **Passed** — 2026-10-19 01:29:16–01:31:27 UTC | New version applied; at least `KeyUnwrap` 200 at 01:30:18, RBAC true, public trusted-service source. No `KeyGet` observed in queried window; do not infer four operations |

Detailed evidence and chronology are recorded in [results](docs/results.md), the [progress tracker](docs/progress.md), [resource inventory](docs/resource-inventory.md) and [engineering journal](docs/experiment-log.md).

### Service-tag scope and documentation caveats

- The native NSP service-tag rule admits a **broader cloud-service address range than one IP**; it is **not tenant- or workspace-specific**.
- Microsoft's service-tag overview lists `AzureDatabricks` with **no regional scope**. No regional suffix such as `.KoreaCentral` is asserted or used here.
- NSP concepts documentation describes service tags as **Preview**, while CLI/ARM documentation says they are unavailable. The lab nevertheless observed native rule acceptance and successful read-back. Record this discrepancy, not a claim of general availability or production support.
- The Approved third NCC connection remains a confounder. No service-tag-rule removal negative control, independent outside-network denial test or Microsoft/Databricks support confirmation has been completed.

## Architecture and validation status

Two Korea Central VNets serve Premium, VNet-injected Databricks workspaces: a **workspace VNet** with delegated host/container subnets, a private-endpoint subnet and outbound NAT, plus a **transit VNet** with authentication-workspace subnets and a private-endpoint subnet. A `databricks_ui_api` private endpoint serves front-end/back-end access; a `browser_authentication` endpoint supports browser sign-in. Workspace public access remains Disabled, with `enableNoPublicIp=true` for the target workspace.

Key Vault has two Approved/Succeeded private endpoints: one in the workspace VNet and one in the existing VM subnet. Private DNS and direct peering connect the VM VNet to both new VNets. These endpoints provide private access for network clients; **they do not give the Databricks control plane a customer-private route for Managed Services CMK**. NCC is documented for serverless compute and must not be treated as evidence of that route.

| Area | Status |
| --- | --- |
| Feasibility and deployment | Baseline deployed; documentation review found no documented/configurable customer-PE route for Managed Services CMK; support question open |
| CMK validation | Bypass, NCC, NSP IP-rule negative/repeat, Disabled-PNA IP-rule denial, fresh selected-IP and native service-tag tests recorded above; current target `Succeeded` |
| VM private reachability | Workspace/authentication DNS and TCP peer private, TLS hostname valid, HTTPS 303 sign-in redirect observed; vault DNS resolves privately |
| Remaining validation | Authenticated API/browser sign-in, classic-cluster back-end connectivity, independent public-denial tests and Databricks-managed RG location verification |
| Reporting / cleanup | Reporting in progress; cleanup not authorized. Earlier approved NSP removal was a test step; a new NSP is now deployed |

The original denied `KeyGet` was attributed to the AzureDatabricks application on a public Azure source, classified `TrustedService=AzureDatabricks`. The trusted-service control's successful RBAC checks distinguish network admission from a permissions failure. Earlier ARM key creation while private-only and before a PE existed also failed with `ForbiddenByConnection`; first-party origin alone did not bypass the network policy.

Changes outside the PoC resource group include peering links on the existing VM VNet, one private IP in its subnet and two private DNS links. The VM, NIC, NSG and routes were not modified. Databricks also created separate managed resource groups and network intent policies. Vault purge protection can leave a soft-deleted vault after deletion; immediate residue-free cleanup cannot be promised.

## Remaining actions / owner decisions

1. **Retain the working service-tag NSP state pending the owner's decision.** Do not remove rules, alter admission paths or clean up automatically.
2. If approved, run a service-tag-rule removal/restoration negative control and correlate vault/NSP logs, accounting for the Approved third NCC connection. NCC removal is a separate owner-approved action and may affect hourly charges.
3. Ask Microsoft/Databricks about support for Managed Services CMK with NSP service tags, the documentation discrepancy and any supported customer-PE-only route. Neither successful public-source variant satisfies the requested PE-only requirement.
4. Complete authenticated API/browser and classic-cluster tests, independent outside-network denial checks, and managed-resource-group location verification.
5. Complete evidence reconciliation, secret scan and full Git-history review before any separately approved commit/publication. **No automatic commit or push.** Cleanup also requires separate approval and must cover VM-VNet peering/DNS links, managed resource groups and vault retention.

## Documentation

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

Keep actual identifiers, IP addresses, exclusion-tag key/value, configuration and raw diagnostics in ignored local storage, never Git. Infrastructure is defined in [infra/main.bicep](infra/main.bicep) and its modules, deployed by [Deploy-Poc.ps1](scripts/deploy/Deploy-Poc.ps1). Cleanup automation is not yet implemented.
