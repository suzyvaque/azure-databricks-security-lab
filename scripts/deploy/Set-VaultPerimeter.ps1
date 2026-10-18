#Requires -Version 5.1
<#
.SYNOPSIS
Manages a network security perimeter (NSP) around the PoC Key Vault for the Stage 2b tests. Touches only PoC resources.
.DESCRIPTION
Actions:
  Setup      Create the perimeter and a profile, associate the vault AND the Log Analytics workspace in Transition (Learning) mode.
  AddRule    Add one inbound access rule for one public IPv4 address or narrow CIDR (-AddressPrefix).
  Enforce    Switch the VAULT association to Enforced (the workspace association stays Transition so audit queries keep working).
  Transition Switch the vault association back to Transition.
  Status     Read-only: perimeter, associations and the vault's network settings.
  Remove     Delete rule, associations, profile and perimeter. If the vault is SecuredByPerimeter it is locked down until restored.
Needs the Azure CLI 'nsp' extension (installed on demand). Output carries no addresses beyond counts.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Setup', 'AddRule', 'RemoveRule', 'Enforce', 'Transition', 'Status', 'Remove')][string]$Action,
    [string]$AddressPrefix
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL = 'no'

function Invoke-Az {
    param([string[]]$Arguments, [switch]$AllowFailure)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & az @Arguments --only-show-errors 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    if ($code -ne 0) {
        if ($AllowFailure) { return $null }
        throw ("az {0} failed (exit {1}): {2}" -f ($Arguments[0..2] -join ' '), $code, ($output | Out-String))
    }
    return ($output | Out-String)
}

$state = Get-Content -Raw -Path (Join-Path $Root '.local/deploy/run.json') | ConvertFrom-Json
$rg = $state.ResourceGroup
$run = $state.RunId
$nsp = "nsp-dbxcmk-krc-$run"
$profileName = 'profile-poc'
$ruleName = 'allow-databricks-cp'
$vaultName = (Invoke-Az @('keyvault', 'list', '-g', $rg, '--query', '[0].name', '-o', 'tsv')).Trim()
$vaultId = (Invoke-Az @('keyvault', 'show', '-n', $vaultName, '-g', $rg, '--query', 'id', '-o', 'tsv')).Trim()
$lawId = (Invoke-Az @('resource', 'show', '-g', $rg, '-n', "law-dbxcmk-krc-$run", '--resource-type', 'Microsoft.OperationalInsights/workspaces', '--query', 'id', '-o', 'tsv')).Trim()

if ($null -eq (Invoke-Az @('extension', 'show', '--name', 'nsp', '-o', 'none') -AllowFailure)) {
    $null = Invoke-Az @('extension', 'add', '--name', 'nsp', '--yes', '-o', 'none')
    Write-Output 'Installed the Azure CLI nsp extension.'
}

function Get-VaultNetwork {
    $v = (Invoke-Az @('keyvault', 'show', '-n', $vaultName, '-g', $rg, '-o', 'json')) | ConvertFrom-Json
    return [ordered]@{
        PublicNetworkAccess = $v.properties.publicNetworkAccess
        Bypass              = $v.properties.networkAcls.bypass
        DefaultAction       = $v.properties.networkAcls.defaultAction
        IpRuleCount         = @($v.properties.networkAcls.ipRules).Count
    }
}

function Set-Association {
    param([string]$Name, [string]$ResourceId, [string]$Mode, [string]$ProfileId)
    $null = Invoke-Az @('network', 'perimeter', 'association', 'create', '--name', $Name, '--perimeter-name', $nsp, '-g', $rg,
        '--access-mode', $Mode, '--private-link-resource', "{id:$ResourceId}", '--profile', "{id:$ProfileId}", '-o', 'none')
}

Write-Output ('VAULT BEFORE ' + ((Get-VaultNetwork) | ConvertTo-Json -Compress))

switch ($Action) {
    'Setup' {
        $null = Invoke-Az @('network', 'perimeter', 'create', '--name', $nsp, '-g', $rg, '-l', 'koreacentral', '-o', 'none')
        $null = Invoke-Az @('network', 'perimeter', 'profile', 'create', '--name', $profileName, '-g', $rg, '--perimeter-name', $nsp, '-o', 'none')
        $profileId = (Invoke-Az @('network', 'perimeter', 'profile', 'show', '--name', $profileName, '-g', $rg, '--perimeter-name', $nsp, '--query', 'id', '-o', 'tsv')).Trim()
        Set-Association -Name 'assoc-vault' -ResourceId $vaultId -Mode 'Learning' -ProfileId $profileId
        Set-Association -Name 'assoc-law' -ResourceId $lawId -Mode 'Learning' -ProfileId $profileId
        Write-Output 'Perimeter, profile and Transition-mode associations (vault and workspace) created.'
    }
    'AddRule' {
        if ($AddressPrefix -notmatch '^(\d{1,3}\.){3}\d{1,3}(/\d{1,2})?$') { throw 'AddressPrefix must be one IPv4 address or CIDR.' }
        if ($AddressPrefix -match '^(10\.|127\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.)') { throw 'Public addresses only.' }
        if ($AddressPrefix -match '/(\d+)$' -and [int]$Matches[1] -lt 24) { throw 'CIDR wider than /24 refused.' }
        $null = Invoke-Az @('network', 'perimeter', 'profile', 'access-rule', 'create', '--name', $ruleName, '--profile-name', $profileName,
            '--perimeter-name', $nsp, '-g', $rg, '--address-prefixes', "[$AddressPrefix]", '-o', 'none')
        Write-Output 'Inbound access rule created (one address).'
    }
    'RemoveRule' {
        $null = Invoke-Az @('network', 'perimeter', 'profile', 'access-rule', 'delete', '--name', $ruleName, '--profile-name', $profileName,
            '--perimeter-name', $nsp, '-g', $rg, '--yes', '-o', 'none')
        Write-Output 'Inbound access rule deleted (perimeter, profile and associations unchanged).'
    }
    'Enforce' {
        $profileId = (Invoke-Az @('network', 'perimeter', 'profile', 'show', '--name', $profileName, '-g', $rg, '--perimeter-name', $nsp, '--query', 'id', '-o', 'tsv')).Trim()
        Set-Association -Name 'assoc-vault' -ResourceId $vaultId -Mode 'Enforced' -ProfileId $profileId
        Write-Output 'Vault association set to Enforced (workspace association unchanged, Transition).'
    }
    'Transition' {
        $profileId = (Invoke-Az @('network', 'perimeter', 'profile', 'show', '--name', $profileName, '-g', $rg, '--perimeter-name', $nsp, '--query', 'id', '-o', 'tsv')).Trim()
        Set-Association -Name 'assoc-vault' -ResourceId $vaultId -Mode 'Learning' -ProfileId $profileId
        Write-Output 'Vault association set back to Transition.'
    }
    'Status' {
        $assoc = Invoke-Az @('network', 'perimeter', 'association', 'list', '--perimeter-name', $nsp, '-g', $rg, '-o', 'json') -AllowFailure
        if ($null -eq $assoc) { Write-Output 'No perimeter found or the association list failed.' }
        else {
            # Windows PowerShell 5.1 returns a JSON array as ONE object when piped; enumerate explicitly.
            $parsedAssoc = $assoc | ConvertFrom-Json
            foreach ($a in $parsedAssoc) { Write-Output ('ASSOC {0} mode={1} state={2}' -f $a.name, $a.accessMode, $a.provisioningState) }
        }
        $rules = Invoke-Az @('network', 'perimeter', 'profile', 'access-rule', 'list', '--profile-name', $profileName, '--perimeter-name', $nsp, '-g', $rg, '-o', 'json') -AllowFailure
        if ($null -ne $rules) { $parsedRules = $rules | ConvertFrom-Json; foreach ($r in $parsedRules) { Write-Output ('RULE {0} direction={1} prefixCount={2}' -f $r.name, $r.direction, @($r.addressPrefixes).Count) } }
    }
    'Remove' {
        $null = Invoke-Az @('network', 'perimeter', 'profile', 'access-rule', 'delete', '--name', $ruleName, '--profile-name', $profileName, '--perimeter-name', $nsp, '-g', $rg, '--yes', '-o', 'none') -AllowFailure
        foreach ($n in @('assoc-vault', 'assoc-law')) {
            $null = Invoke-Az @('network', 'perimeter', 'association', 'delete', '--name', $n, '--perimeter-name', $nsp, '-g', $rg, '--yes', '-o', 'none') -AllowFailure
        }
        $null = Invoke-Az @('network', 'perimeter', 'profile', 'delete', '--name', $profileName, '--perimeter-name', $nsp, '-g', $rg, '--yes', '-o', 'none') -AllowFailure
        $null = Invoke-Az @('network', 'perimeter', 'delete', '--name', $nsp, '-g', $rg, '--yes', '-o', 'none') -AllowFailure
        Write-Output 'Perimeter resources deleted (best effort; run Status to confirm).'
    }
}

Write-Output ('VAULT AFTER  ' + ((Get-VaultNetwork) | ConvertTo-Json -Compress))
Write-Output 'NSP_ACTION_DONE'
