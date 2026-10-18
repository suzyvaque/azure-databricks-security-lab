# Read-only Phase 1 tooling

[Invoke-ReadOnlyPreflight.ps1](Invoke-ReadOnlyPreflight.ps1) collects Azure CLI version/extensions, current account/cloud, provider metadata, Korea Central compute SKUs/quotas and network usage, subscription permissions/policy assignments, the AzureDatabricks enterprise application, and an explicitly identified VM's NIC/VNet/subnet/NSG/UDR/effective routes. It makes no resource changes and never requests or prints tokens or keys. Dynamic extension installation is disabled for its process and the prior environment setting restored.

**Status: executed 2026-10-17; 18 of 18 collection checks succeeded.** Collection success is not feature validation or an authorization to deploy.

A second read-only tool, [Get-VaultStatus.ps1](Get-VaultStatus.ps1), reports the vault's network flags, private endpoint states, whether the vault name resolves to a private address from the machine it runs on, and key enablement. It was run on 2026-10-18 (see [results](../../docs/results.md)). It writes details to ignored `.local/validate`.

[Get-NccTestStatus.ps1](Get-NccTestStatus.ps1) is read-only status for the NCC test: vault network settings, every private endpoint connection on the vault (connections that are not ours are counted as foreign, which is how an NCC rule would appear), the target workspace state and the CMK key version suffix, and the Databricks control plane's recent key requests from the audit log. The console summary prints no addresses; full detail is written to ignored `.local/validate`.

## Inputs and output

- Run from PowerShell 5.1+ in the existing VM's repository checkout if local OS DNS/routes should describe that VM. Running from a local laptop does not establish VM OS state.
- Optional `VmResourceId`: supply the actual VM resource ID through a local shell variable, never a committed configuration. Omission explicitly blocks VM inspection; it does not discover/select a VM by guesswork.
- `Location`: only `koreacentral` is accepted. Existing VM location is read, never modified.
- Output: timestamped **ignored** `.local/preflight` directory. It contains actual identifiers/network settings and is **not sanitized for publication**. Review local ACLs, disk encryption and retention. Do not paste raw output into public issues or docs.
- GET failures, missing Graph rights or effective-route reads on a deallocated VM remain blocked checks. The script does not install tools, log in, select a subscription, register providers or start the VM.

## Initial preflight checks (historical; completed unless noted)

1. **Completed before deployment:** account/subscription, VM, provider registrations, permissions, policies, Korea Central availability/quota and VM network were inspected read-only; actual resource creation and approved peering later succeeded. Successful deployment does not confirm vendor support or untested classic-compute capacity.
2. **Still open:** obtain Microsoft/Databricks confirmation for Managed Services CMK private-only or NSP support; verify the Databricks-managed RG locations and classic compute SKU/capacity before starting a cluster.
3. Existing DNS/peer information was inspected before the approved changes. The VM was directly peered with both PoC VNets and linked to PoC private DNS. Reinspect current state only as needed for validation or separately approved cleanup; the script does not enumerate every subscription DNS zone.
4. Exact allocated ranges and raw network details remain local-only; sanitized findings are documented in the inventory.

## Exact read-only command inventory

The executable source contains argument arrays for `az version`, `az extension list`, `az account show`, `az cloud show`, `az account list-locations`, `az provider show`, `az vm list-skus --location koreacentral --all`, `az vm list-usage --location koreacentral`, `az network list-usages --location koreacentral`, `az policy assignment list`, `az ad sp show`, `az vm show`, `az network nic show`, `az network nic list-effective-nsg`, `az network nic show-effective-route-table`, `az network vnet show`, `az network nsg show`, `az network route-table show`, and `az rest --method get` for ARM permissions. No Azure write verbs are present.

Runtime coverage is partial: [Test-WorkspaceConnectivity.ps1](Test-WorkspaceConnectivity.ps1) verifies DNS, TCP, TLS and unauthenticated HTTPS reachability and was run from the VM. Authenticated API/browser login, cluster back-end tests and external public-denial tests remain unimplemented or unrun; the [test plan](../../docs/test-plan.md) defines their acceptance criteria.
