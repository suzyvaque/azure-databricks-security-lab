# Cleanup design — not executable and not approved

PoC resources were created and remain deployed. **Full cleanup has not been approved or run.** The user authorized removal of the previous PoC NSP for CMK-IP-02 on 2026-10-19 (local date); its absence was verified then. **That absence is historical:** the owner subsequently approved CMK-IP-03 (selected-IP success) and CMK-NSP-TAG-01, which created a new isolated Korea Central NSP/profile and succeeded with a native Inbound AzureDatabricks service-tag rule (provisioning Succeeded, zero address prefixes). Neither test approval authorizes cleanup or a tag-removal negative control.

**Retain current posture (2026-10-19):** workspace `Succeeded`, private PNA Disabled, newest CMK version applied; vault Disabled / None / Deny / zero firewall IP and VNet rules; vault NSP association Enforced, LAW Learning/Transition; owner policy-exclusion tag retained. NCC connection remains Approved, a disclosed confounder because NCC alone failed earlier. Do not remove the rule, associations, profile, perimeter, NCC, keys or tags as housekeeping; failed CMK access can leave a workspace `Failed`, and caches do not guarantee continued operation. No customer PE-only, external public-denial or vendor-support conclusion follows from the native-tag success. See [execution record](../../docs/experiment-log.md#latest-completed-follow-ups--2026-10-19-utc) and [scope/support caveats](../../docs/feasibility.md#native-nsp-service-tag-scope-and-documentation-conflict).

Do not infer that the subscription contains no other resources. Current Azure state and cross-boundary artifacts are listed in [the inventory](../../docs/resource-inventory.md); full cleanup requires separate explicit approval. Test scripts are not cleanup automation, and the previous address-rule perimeter removal must not be assumed to target the new native-tag perimeter.

## Future approval-gated sequence

1. Obtain separate cleanup approval; verify exact subscription, dedicated PoC RG, immutable run identifier and local creation manifest. Refuse any existing-resource target not explicitly enumerated in the approved cross-boundary change ledger.
2. Export required evidence to ignored local storage; stop disposable compute. Do not delete keys while still needing managed-services data. Preserve prior versions for at least 24 hours after each rotation, and longer while dependencies remain. Obtain a reviewed CMK continuity/teardown decision before changing the current native-tag perimeter. Enumerate its rule, profile, vault and LAW associations from the local manifest; remove only separately approved artifacts in a supported order, never leave an unplanned interval of blocked key access. Preserve the owner policy-exclusion tag unless its removal is separately approved.
3. Remove **only the two explicitly created existing-VNet-side peering children**, and any explicitly approved temporary DNS forwarding changes. Preserve all original peers/routes/NSGs/DNS settings. Verify DNS baseline restoration and existing VM health; no VM restart/reconfiguration by default.
4. Remove approved links from the **new** private DNS zones to the existing VNet. These links/diagnostic settings/scoped role assignments normally disappear with their PoC parent, but check cross-boundary artifacts explicitly.
5. Delete the dedicated customer RG after human target confirmation. Let the Databricks provider delete its workspaces and associated service-managed resources. Do not bypass managed-RG deny assignments or manually delete individual service storage/disks.
6. Poll customer RG absence and both recorded Databricks managed RGs. If the provider leaves a managed RG, record it and seek supported cleanup; no blind broad deletion.
7. Check subscription-scoped **soft-deleted Key Vaults** for the exact newly created vault. With purge protection enabled it remains until its approved retention expires (proposed 7 days, subject to policy). Do not call purge to evade protection. Record expiry and name reservation. Re-check after retention.
8. Compare tagged resources AND manifest-recorded resource IDs against absence (tags alone are incomplete for child/provider-created resources). Re-query existing peering children, DNS links/forwarders, role assignments and any approved exceptions. Verify the original VM/NIC/subnet/NSG/routes/DNS remained intact.
9. Update inventory/results with removal timestamps, remaining service-managed/soft-delete artifacts and residual costs; only then mark cleanup complete, or Blocked with residuals. Never report “no resources remain” before these checks pass.

## Placement exceptions

| Artifact | Why outside customer RG | Authorization / handling |
| --- | --- | --- |
| Two Databricks-managed RGs and their resources | Azure service requirement, one per target/auth workspace | Explicit plan acknowledgment; provider lifecycle; verify deletion |
| Databricks account-level NCC and its vault connection | Account-plane configuration and Databricks-created private endpoint lifecycle | Separate approval to remove the NCC rule/detach configuration; verify residual vault connection and billing, do not assume PoC RG deletion cleans the account object |
| Two peering children under existing VM VNet | Peering is directional and owned by source VNet | Exact create/delete approval required; store original baseline locally |
| Existing DNS conditional forwarders, if required | Existing resolver ownership | Separate approved delta/rollback; never replace whole configuration |
| Soft-deleted purge-protected vault | Subscription-scoped recovery record after deletion | Retain until allowed expiry; verify eventual removal |

Any subscription-scoped role assignment or provider registration, if later proposed, must be separately approved and logged. Do not unregister a provider: other resources may depend on it. Public publication, local evidence destruction and Git history changes are separate approvals.
