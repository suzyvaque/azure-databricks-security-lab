# Cleanup design — not executable and not approved

No resources were created by this session, so there is nothing to delete. Do not infer that the subscription contains no other resources. No cleanup has been run.

## Future approval-gated sequence

1. Obtain separate cleanup approval; verify exact subscription, dedicated PoC RG, immutable run identifier and local creation manifest. Refuse any existing-resource target not explicitly enumerated in the approved cross-boundary change ledger.
2. Export required evidence to ignored local storage; stop disposable compute. Do not delete keys while still needing managed-services data.
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
| Two peering children under existing VM VNet | Peering is directional and owned by source VNet | Exact create/delete approval required; store original baseline locally |
| Existing DNS conditional forwarders, if required | Existing resolver ownership | Separate approved delta/rollback; never replace whole configuration |
| Soft-deleted purge-protected vault | Subscription-scoped recovery record after deletion | Retain until allowed expiry; verify eventual removal |

Any subscription-scoped role assignment or provider registration, if later proposed, must be separately approved and logged. Do not unregister a provider: other resources may depend on it. Public publication, local evidence destruction and Git history changes are separate approvals.
