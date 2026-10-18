#Requires -Version 5.1
<#
.SYNOPSIS
Peers the existing VM VNet with the two NEW PoC VNets and lets the VM VNet resolve the Databricks private DNS zone.
.DESCRIPTION
Existing-infrastructure changes (explicitly approved by the user):
  - two peering links on the existing VM VNet (one per new VNet)
  - one virtual network link from the NEW privatelink.azuredatabricks.net zone to the VM VNet
No VM, NIC, NSG, route table or DNS-server setting is changed. No gateway transit or forwarded traffic.
Idempotent: existing links are left as they are. Reads the VM subnet from ignored .local/vm/subnet-id.txt.
Rollback: delete the two peerings on the VM VNet and the zone link 'link-vm' on the new zone.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))

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
$vmSubnetId = (Get-Content -Raw -Path (Join-Path $Root '.local/vm/subnet-id.txt')).Trim()
$vmVnetId = $vmSubnetId -replace '/subnets/[^/]+$', ''
if ($vmVnetId -notmatch '/resourceGroups/([^/]+)/providers/Microsoft.Network/virtualNetworks/([^/]+)$') { throw 'Cannot parse the VM VNet ID.' }
$vmRg = $Matches[1]
$vmVnetName = $Matches[2]

$targets = @(
    @{ Key = 'ws'; Name = "vnet-dbxcmk-krc-$run-ws" },
    @{ Key = 'transit'; Name = "vnet-dbxcmk-krc-$run-transit" }
)

foreach ($t in $targets) {
    $targetId = (Invoke-Az @('network', 'vnet', 'show', '-g', $rg, '-n', $t.Name, '--query', 'id', '-o', 'tsv')).Trim()

    # New-side peering lives in the PoC resource group.
    $newSide = "peer-to-vm-$($t.Key)"
    if ($null -eq (Invoke-Az @('network', 'vnet', 'peering', 'show', '-g', $rg, '--vnet-name', $t.Name, '-n', $newSide, '-o', 'none') -AllowFailure)) {
        $null = Invoke-Az @('network', 'vnet', 'peering', 'create', '-g', $rg, '--vnet-name', $t.Name, '-n', $newSide, '--remote-vnet', $vmVnetId, '--allow-vnet-access', 'true', '--allow-forwarded-traffic', 'false', '-o', 'none')
        Write-Output "Created new-side peering ($($t.Key))."
    }
    else { Write-Output "New-side peering already exists ($($t.Key))." }

    # Existing-side peering (child of the existing VM VNet): the only existing-infrastructure change besides the DNS link.
    $vmSide = "peer-dbxcmk-$run-to-$($t.Key)"
    if ($null -eq (Invoke-Az @('network', 'vnet', 'peering', 'show', '-g', $vmRg, '--vnet-name', $vmVnetName, '-n', $vmSide, '-o', 'none') -AllowFailure)) {
        $null = Invoke-Az @('network', 'vnet', 'peering', 'create', '-g', $vmRg, '--vnet-name', $vmVnetName, '-n', $vmSide, '--remote-vnet', $targetId, '--allow-vnet-access', 'true', '--allow-forwarded-traffic', 'false', '-o', 'none')
        Write-Output "Created VM-side peering ($($t.Key))."
    }
    else { Write-Output "VM-side peering already exists ($($t.Key))." }
}

# Lets the VM VNet resolve the workspace and browser-auth names to the private endpoints.
$zone = 'privatelink.azuredatabricks.net'
if ($null -eq (Invoke-Az @('network', 'private-dns', 'link', 'vnet', 'show', '-g', $rg, '-z', $zone, '-n', 'link-vm', '-o', 'none') -AllowFailure)) {
    $null = Invoke-Az @('network', 'private-dns', 'link', 'vnet', 'create', '-g', $rg, '-z', $zone, '-n', 'link-vm', '--virtual-network', $vmVnetId, '--registration-enabled', 'false', '-o', 'none')
    Write-Output 'Created Databricks private DNS zone link to the VM VNet.'
}
else { Write-Output 'Databricks private DNS zone link to the VM VNet already exists.' }

# Report peering state (non-sensitive).
foreach ($t in $targets) {
    $state1 = (Invoke-Az @('network', 'vnet', 'peering', 'show', '-g', $rg, '--vnet-name', $t.Name, '-n', "peer-to-vm-$($t.Key)", '--query', 'peeringState', '-o', 'tsv')).Trim()
    $state2 = (Invoke-Az @('network', 'vnet', 'peering', 'show', '-g', $vmRg, '--vnet-name', $vmVnetName, '-n', "peer-dbxcmk-$run-to-$($t.Key)", '--query', 'peeringState', '-o', 'tsv')).Trim()
    Write-Output ("PEERING {0}: new-side={1} vm-side={2}" -f $t.Key, $state1, $state2)
}
Write-Output 'PEERING_DONE'
