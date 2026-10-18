#Requires -Version 5.1
<#
.SYNOPSIS
Approves ONE pending private endpoint connection on the PoC Key Vault (used after Databricks creates an NCC rule).
.DESCRIPTION
Changes only the named connection's state, and only if it is currently Pending. The connection name is mandatory
so nothing is approved implicitly. Run scripts/validate/Get-NccTestStatus.ps1 first to see the pending connection.
Rollback: reject or delete that connection (or delete the NCC private endpoint rule in the Databricks account console).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConnectionName,
    [string]$Description = 'Approved for the Databricks NCC test'
)

$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))

function Invoke-Az {
    param([string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & az @Arguments --only-show-errors 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    if ($code -ne 0) { throw ("az {0} failed (exit {1}): {2}" -f ($Arguments[0..2] -join ' '), $code, ($output | Out-String)) }
    return ($output | Out-String)
}

$state = Get-Content -Raw -Path (Join-Path $Root '.local/deploy/run.json') | ConvertFrom-Json
$rg = $state.ResourceGroup
$vaultId = (Invoke-Az @('keyvault', 'list', '-g', $rg, '--query', '[0].id', '-o', 'tsv')).Trim()
$parsed = (Invoke-Az @('network', 'private-endpoint-connection', 'list', '--id', $vaultId, '-o', 'json')) | ConvertFrom-Json
$conns = @()
# Windows PowerShell 5.1 returns a JSON array as ONE object when piped; enumerate it explicitly.
foreach ($item in $parsed) { $conns += $item }
$target = @($conns | Where-Object { ([string]$_.id -split '/')[-1] -eq $ConnectionName })
if ($target.Count -ne 1) { throw "Connection '$ConnectionName' not found on the vault. Run Get-NccTestStatus.ps1 to list names." }
$status = $target[0].properties.privateLinkServiceConnectionState.status
$peName = ([string]$target[0].properties.privateEndpoint.id -split '/')[-1]
if ($peName -like "pe-dbxcmk-krc-$($state.RunId)-*") { throw 'That connection belongs to one of our own endpoints; refusing.' }
if ($status -ne 'Pending') { Write-Output "Connection is '$status', not Pending. Nothing changed."; return }

$null = Invoke-Az @('network', 'private-endpoint-connection', 'approve', '--id', $target[0].id, '--description', $Description, '-o', 'none')
$after = ((Invoke-Az @('network', 'private-endpoint-connection', 'show', '--id', $target[0].id, '-o', 'json')) | ConvertFrom-Json).properties.privateLinkServiceConnectionState.status
Write-Output ("BEFORE {0}; AFTER {1}" -f $status, $after)
