#Requires -Version 5.1
<#
.SYNOPSIS
Sets ONLY the Key Vault trusted-services bypass on the PoC vault, and reports before/after state.
.DESCRIPTION
Used for the control experiment (None -> AzureServices) and to restore the lab posture (AzureServices -> None).
Public network access is never changed by this script; it is read and reported so a change would be visible.
Touches only the vault in the PoC resource group recorded in ignored .local/deploy/run.json.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('None', 'AzureServices')][string]$Bypass
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
        IpRules             = @($v.properties.networkAcls.ipRules).Count
    }
}

$state = Get-Content -Raw -Path (Join-Path $Root '.local/deploy/run.json') | ConvertFrom-Json
$rg = $state.ResourceGroup
$vault = (Invoke-Az @('keyvault', 'list', '-g', $rg, '--query', '[0].name', '-o', 'tsv')).Trim()

Write-Output ('BEFORE ' + ((Get-VaultNetwork -Name $vault -Group $rg) | ConvertTo-Json -Compress))
# --public-network-access is deliberately NOT passed: only the bypass changes.
$null = Invoke-Az @('keyvault', 'update', '-n', $vault, '-g', $rg, '--bypass', $Bypass, '-o', 'none')
$after = Get-VaultNetwork -Name $vault -Group $rg
Write-Output ('AFTER  ' + ($after | ConvertTo-Json -Compress))
if ($after.Bypass -ne $Bypass) { throw 'Bypass did not take the requested value.' }
if ($after.PublicNetworkAccess -ne 'Disabled') { throw 'Public network access is not Disabled; stop and investigate.' }
Write-Output 'BYPASS_SET'
