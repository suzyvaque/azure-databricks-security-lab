#Requires -Version 5.1
<#
.SYNOPSIS
Owner-approved final negative test: remove the PoC NSP, retain vault public Disabled / bypass None,
store one control-plane firewall IP rule, and retry Managed Services CMK with a new key version.
.DESCRIPTION
An IP firewall rule is not an admission exception while public access is Disabled. This is a
negative experiment, not a test of active selected-network access. Never enables public access,
changes organization policy, recreates NSP, deletes NCC, or enables trusted-service bypass.
Full evidence stays in ignored local storage. A denied CMK update may leave the workspace Failed.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][switch]$ConfirmRemovePerimeterAndTest)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out = Join-Path $root ('.local/deploy/final-no-nsp-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
$null = New-Item -ItemType Directory -Path $out -Force
function AzJson {
    param([string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $text = & az @Arguments --only-show-errors 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previous
    if ($exitCode -ne 0) { throw ($text | Out-String) }
    return (($text | Out-String) | ConvertFrom-Json)
}
function Save-Json {
    param([string]$Name, $Value)
    $Value | ConvertTo-Json -Depth 30 | Set-Content -Encoding UTF8 -Path (Join-Path $out $Name)
}
function Assert-Vault {
    $v = AzJson @('keyvault', 'show', '-g', $rg, '-n', $vault.name, '-o', 'json')
    if ($v.properties.publicNetworkAccess -ne 'Disabled' -or $v.properties.networkAcls.bypass -ne 'None' -or
        $v.properties.networkAcls.defaultAction -ne 'Deny') { throw 'Strict vault flags not retained; stop.' }
    return $v
}
$result = [ordered]@{ StartedUtc = [DateTime]::UtcNow.ToString('o'); Outcome = 'InProgress' }
try {
    if (-not $ConfirmRemovePerimeterAndTest) { throw 'Explicit removal/test confirmation required.' }
    $state = Get-Content -Raw (Join-Path $root '.local/deploy/run.json') | ConvertFrom-Json
    $rg = $state.ResourceGroup
    $run = $state.RunId
    $group = AzJson @('group', 'show', '-n', $rg, '-o', 'json')
    if ($group.location -ne 'koreacentral' -or $group.tags.run -ne $run) { throw 'PoC ownership check failed.' }
    $vaults = @(AzJson @('keyvault', 'list', '-g', $rg, '-o', 'json'))
    if ($vaults.Count -ne 1) { throw 'Expected exactly one PoC vault.' }
    $vault = $vaults[0]
    Save-Json 'vault-before.json' (Assert-Vault)
    $rules = @(AzJson @('network', 'perimeter', 'profile', 'access-rule', 'list', '--profile-name', 'profile-poc',
        '--perimeter-name', "nsp-dbxcmk-krc-$run", '-g', $rg, '-o', 'json'))
    $rule = @($rules | Where-Object { $_.name -eq 'allow-databricks-cp' })
    if ($rule.Count -ne 1 -or @($rule[0].addressPrefixes).Count -ne 1) { throw 'Expected one known control-plane prefix.' }
    $prefix = [string]$rule[0].addressPrefixes[0]
    if ($prefix -notmatch '^(\d{1,3}\.){3}\d{1,3}(/32)?$') { throw 'Expected a single IPv4 address, not a range.' }
    Save-Json 'perimeter-rules-before.json' $rules
    & (Join-Path $PSScriptRoot 'Set-VaultPerimeter.ps1') -Action Remove *> (Join-Path $out 'remove-nsp.log')
    $perimeters = @(AzJson @('network', 'perimeter', 'list', '-g', $rg, '-o', 'json'))
    Save-Json 'perimeters-after.json' $perimeters
    if (@($perimeters | Where-Object { $_.name -eq "nsp-dbxcmk-krc-$run" }).Count -ne 0) { throw 'NSP removal not verified.' }
    $result.NspRemoved = $true
    $result.NspRemovedUtc = [DateTime]::UtcNow.ToString('o')
    Save-Json 'result.json' $result
    $null = Assert-Vault
    $null = AzJson @('keyvault', 'network-rule', 'add', '-n', $vault.name, '-g', $rg, '--ip-address', $prefix, '-o', 'json')
    $after = Assert-Vault
    Save-Json 'vault-test-config.json' $after
    if (@($after.properties.networkAcls.ipRules).Count -ne 1) { throw 'Expected exactly one stored vault IP rule.' }
    if (@($after.properties.networkAcls.virtualNetworkRules).Count -ne 0) { throw 'Unexpected vault VNet rules.' }
    $result.StoredIpRuleCount = 1
    $result.ActiveSelectedNetworksTest = 'Not achievable with publicNetworkAccess Disabled; IP rule does not admit public traffic.'
    Save-Json 'result.json' $result
    Start-Sleep -Seconds 150
    & (Join-Path $PSScriptRoot 'New-CmkKey.ps1') *> (Join-Path $out 'key-create.log')
    $key = Get-Content -Raw (Join-Path $root '.local/deploy/key.json') | ConvertFrom-Json
    $result.CmkStartedUtc = [DateTime]::UtcNow.ToString('o')
    Save-Json 'result.json' $result
    try {
        & (Join-Path $PSScriptRoot 'Deploy-Poc.ps1') -Stage Cmk -KeyVersion $key.KeyVersion -VaultBypass None -VaultPublicNetworkAccess Disabled -VaultAllowedIps @($prefix) *> (Join-Path $out 'cmk.log')
        $result.Outcome = 'CmkUpdateSucceeded'
    }
    catch {
        $result.Outcome = 'CmkUpdateFailed'
        $result.Error = $_.Exception.Message
    }
    $result.CmkFinishedUtc = [DateTime]::UtcNow.ToString('o')
    Save-Json 'vault-after.json' (Assert-Vault)
    $workspace = AzJson @('resource', 'show', '-g', $rg, '-n', "dbw-dbxcmk-krc-$run", '--resource-type', 'Microsoft.Databricks/workspaces', '--api-version', '2024-05-01', '-o', 'json')
    Save-Json 'workspace-after.json' $workspace
    $result.WorkspaceState = $workspace.properties.provisioningState
    $result.WorkspaceKeyMatchesAttempt = ($workspace.properties.encryption.entities.managedServices.keyVaultProperties.keyVersion -eq $key.KeyVersion)
}
catch {
    $result.Outcome = 'Stopped'
    $result.Error = $_.Exception.Message
}
finally {
    $result.FinishedUtc = [DateTime]::UtcNow.ToString('o')
    Save-Json 'result.json' $result
    Write-Output ('FINAL_TEST outcome={0}; evidence saved locally' -f $result.Outcome)
}