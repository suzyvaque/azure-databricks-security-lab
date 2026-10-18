#Requires -Version 5.1
<#
.SYNOPSIS
Read-only status of the PoC Key Vault: network lockdown, private endpoint states, DNS path from this VM, key enablement.
.DESCRIPTION
Writes a sanitized-for-console summary and the full detail to ignored .local/validate. Makes no changes.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$StateDir = Join-Path $Root '.local/deploy'
$Out = Join-Path $Root '.local/validate'
$null = New-Item -ItemType Directory -Path $Out -Force

function Invoke-Az {
    param([string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & az @Arguments --only-show-errors 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    if ($code -ne 0) { return $null }
    return ($output | Out-String)
}

$state = Get-Content -Raw -Path (Join-Path $StateDir 'run.json') | ConvertFrom-Json
$rg = $state.ResourceGroup
$vault = (Invoke-Az @('keyvault', 'list', '-g', $rg, '--query', '[0].name', '-o', 'tsv')).Trim()
$v = (Invoke-Az @('keyvault', 'show', '-n', $vault, '-g', $rg, '-o', 'json')) | ConvertFrom-Json
$v | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $Out 'vault.json') -Encoding UTF8

$summary = [ordered]@{}
$summary.PublicNetworkAccess = $v.properties.publicNetworkAccess
$summary.TrustedServicesBypass = $v.properties.networkAcls.bypass
$summary.DefaultAction = $v.properties.networkAcls.defaultAction
$summary.IpRules = @($v.properties.networkAcls.ipRules).Count
$summary.PurgeProtection = $v.properties.enablePurgeProtection
$summary.SoftDeleteDays = $v.properties.softDeleteRetentionInDays
$summary.RbacAuthorization = $v.properties.enableRbacAuthorization

$peJson = Invoke-Az @('network', 'private-endpoint', 'list', '-g', $rg, '-o', 'json')
$allPes = if ($null -ne $peJson) { @($peJson | ConvertFrom-Json) } else { @() }
$pes = @($allPes | Where-Object { $_.name -like '*vault*' })
$summary.VaultPrivateEndpoints = @($pes | ForEach-Object { '{0}: {1}/{2}' -f $_.name, $_.privateLinkServiceConnections[0].privateLinkServiceConnectionState.status, $_.provisioningState })

try {
    $ip = (Resolve-DnsName -Name "$vault.vault.azure.net" -Type A -ErrorAction Stop | Where-Object { $_.Type -eq 'A' })[0].IPAddress
    $summary.DnsFromThisVmIsPrivate = [bool]($ip -match '^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.)')
}
catch { $summary.DnsFromThisVmIsPrivate = 'resolution failed' }

$keys = Invoke-Az @('keyvault', 'key', 'list', '--vault-name', $vault, '-o', 'json')
if ($null -eq $keys) { $summary.Keys = 'data-plane call failed (no private path or missing RBAC)' }
else { $summary.Keys = @((ConvertFrom-Json $keys) | ForEach-Object { '{0}: enabled={1}' -f $_.name, $_.attributes.enabled }) }

$summary | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Out 'vault-status.json') -Encoding UTF8
$summary | ConvertTo-Json -Depth 5
