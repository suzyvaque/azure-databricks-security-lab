#Requires -Version 5.1
<#
.SYNOPSIS
Sets the PoC Key Vault to the Stage 2 posture (selected networks, one allowed address, bypass None) or restores the lab posture.
.DESCRIPTION
Changes ONLY: public network access, the IP rule list, the default action (Deny) and the trusted-services bypass (None).
Prints the vault's network settings before and after (addresses are shown only as a count). Refuses anything but a single
public IPv4 address or CIDR, and refuses private ranges (Key Vault IP rules accept public addresses only).
Rollback: run with -Restore, which sets public network access Disabled, removes all IP rules, default Deny, bypass None.
.PARAMETER AllowedIp
The one public IPv4 address (or CIDR) to allow, for example the control plane address read from the audit log.
.PARAMETER Restore
Restore the lab posture instead.
#>
[CmdletBinding(DefaultParameterSetName = 'Allow')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Allow')][string]$AllowedIp,
    [Parameter(Mandatory, ParameterSetName = 'Restore')][switch]$Restore
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))

function Invoke-Az {
    param([string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & az @Arguments --only-show-errors 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    if ($code -ne 0) { throw ("az {0} failed (exit {1}): {2}" -f ($Arguments[0..1] -join ' '), $code, ($output | Out-String)) }
    return ($output | Out-String)
}

function Get-VaultNetwork {
    param([string]$Name, [string]$Group)
    $v = (Invoke-Az @('keyvault', 'show', '-n', $Name, '-g', $Group, '-o', 'json')) | ConvertFrom-Json
    return [ordered]@{
        PublicNetworkAccess = $v.properties.publicNetworkAccess
        Bypass              = $v.properties.networkAcls.bypass
        DefaultAction       = $v.properties.networkAcls.defaultAction
        IpRuleCount         = @($v.properties.networkAcls.ipRules).Count
        VnetRuleCount       = @($v.properties.networkAcls.virtualNetworkRules).Count
    }
}

$state = Get-Content -Raw -Path (Join-Path $Root '.local/deploy/run.json') | ConvertFrom-Json
$rg = $state.ResourceGroup
$vault = (Invoke-Az @('keyvault', 'list', '-g', $rg, '--query', '[0].name', '-o', 'tsv')).Trim()

if (-not $Restore) {
    if ($AllowedIp -notmatch '^(\d{1,3}\.){3}\d{1,3}(/\d{1,2})?$') { throw 'AllowedIp must be a single IPv4 address or CIDR.' }
    if ($AllowedIp -match '^(10\.|127\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.)') { throw 'Key Vault IP rules accept public addresses only; refusing a private or reserved range.' }
    if ($AllowedIp -match '/(\d+)$' -and [int]$Matches[1] -lt 24) { throw 'CIDR wider than /24 refused; allow a single address or a narrow range.' }
}

Write-Output ('BEFORE ' + ((Get-VaultNetwork -Name $vault -Group $rg) | ConvertTo-Json -Compress))

# Start from a clean rule list so exactly the intended rule exists afterwards.
$existing = (Invoke-Az @('keyvault', 'network-rule', 'list', '-n', $vault, '-g', $rg, '-o', 'json')) | ConvertFrom-Json
foreach ($r in @($existing.ipRules)) {
    if ($null -ne $r) { $null = Invoke-Az @('keyvault', 'network-rule', 'remove', '-n', $vault, '-g', $rg, '--ip-address', $r.value, '-o', 'none') }
}

if ($Restore) {
    $null = Invoke-Az @('keyvault', 'update', '-n', $vault, '-g', $rg, '--default-action', 'Deny', '--bypass', 'None', '--public-network-access', 'Disabled', '-o', 'none')
}
else {
    # The rule is added while public access is still Disabled, then public access is enabled for selected networks.
    $null = Invoke-Az @('keyvault', 'network-rule', 'add', '-n', $vault, '-g', $rg, '--ip-address', $AllowedIp, '-o', 'none')
    $null = Invoke-Az @('keyvault', 'update', '-n', $vault, '-g', $rg, '--default-action', 'Deny', '--bypass', 'None', '--public-network-access', 'Enabled', '-o', 'none')
}

$after = Get-VaultNetwork -Name $vault -Group $rg
Write-Output ('AFTER  ' + ($after | ConvertTo-Json -Compress))
if ($after.DefaultAction -ne 'Deny') { throw 'Default action is not Deny; stop and investigate.' }
if ($after.Bypass -ne 'None') { throw 'Bypass is not None; stop and investigate.' }
if ($Restore) {
    if ($after.PublicNetworkAccess -ne 'Disabled' -or $after.IpRuleCount -ne 0) { throw 'Restore did not reach the lab posture.' }
}
else {
    if ($after.PublicNetworkAccess -ne 'Enabled' -or $after.IpRuleCount -ne 1) { throw 'Stage 2 posture not reached.' }
}
Write-Output 'VAULT_NETWORK_SET'
