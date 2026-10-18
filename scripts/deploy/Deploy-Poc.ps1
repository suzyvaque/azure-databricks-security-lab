#Requires -Version 5.1
<#
.SYNOPSIS
Deploys the Korea Central Databricks private-only PoC into ONE new resource group.
.DESCRIPTION
- Creates only new resources. Never modifies the existing VM or its network.
- Region is fixed to koreacentral.
- Run state, CIDRs and outputs are written under ignored .local/deploy (never commit).
- Stage Baseline: RG, VNets, NSGs, NAT, Key Vault (public disabled, bypass None), key, LAW,
  two private-only workspaces, private endpoints and DNS. No CMK on the workspace.
- Stage Cmk: updates the target workspace with Managed Services CMK. Expected to be the
  experiment's decisive step; failure is a valid result and must NOT be worked around by
  enabling public access or trusted-services bypass.
.PARAMETER ValidateOnly
Runs template validation without creating the resource group deployment.
#>
[CmdletBinding()]
param(
    [ValidateSet('Baseline', 'Cmk')]
    [string]$Stage = 'Baseline',
    [string]$KeyVersion = '',
    # Key Vault trusted-services bypass. None is the lab requirement. AzureServices is only for the approved control experiment.
    [ValidateSet('None', 'AzureServices')]
    [string]$VaultBypass = 'None',
    # Existing VM subnet that receives a vault private endpoint. Defaults to .local/vm/subnet-id.txt.
    [string]$VmSubnetId = '',
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Location = 'koreacentral'
$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$StateDir = Join-Path $Root '.local/deploy'
$null = New-Item -ItemType Directory -Path $StateDir -Force
$StatePath = Join-Path $StateDir 'run.json'
$null = Start-Transcript -Path (Join-Path $StateDir ("deploy-{0}-{1}.log" -f $Stage, [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))) -Force

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

function ConvertTo-Range {
    param([string]$Cidr)
    $parts = $Cidr.Split('/')
    $bytes = [Net.IPAddress]::Parse($parts[0]).GetAddressBytes()
    [Array]::Reverse($bytes)
    $start = [uint64][BitConverter]::ToUInt32($bytes, 0)
    $size = [uint64][math]::Pow(2, 32 - [int]$parts[1])
    return @($start, ($start + $size - 1))
}

function Test-Overlap {
    param([string]$Candidate, [string[]]$Existing)
    $c = ConvertTo-Range $Candidate
    foreach ($e in $Existing) {
        $r = ConvertTo-Range $e
        if ($c[0] -le $r[1] -and $r[0] -le $c[1]) { return $true }
    }
    return $false
}

try {
    if ($Stage -eq 'Cmk' -and [string]::IsNullOrWhiteSpace($KeyVersion)) { throw 'Stage Cmk requires -KeyVersion (exact version of the key created over the private path).' }
    # ---- Preconditions -------------------------------------------------------------
    $account = (Invoke-Az @('account', 'show', '--output', 'json')) | ConvertFrom-Json
    if ($account.environmentName -ne 'AzureCloud' -or $account.state -ne 'Enabled') { throw 'Unexpected cloud or subscription state; stop.' }
    Write-Output ("Stage={0}; subscription state={1}; region={2}; vaultBypass={3}" -f $Stage, $account.state, $Location, $VaultBypass)

    # ---- Run state (idempotent re-runs reuse identifiers) -----------------------
    if (Test-Path $StatePath) {
        $state = Get-Content -Raw -Path $StatePath | ConvertFrom-Json
    }
    else {
        $chars = 'abcdefghijklmnopqrstuvwxyz0123456789'.ToCharArray()
        $runId = 'r' + (-join (1..5 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] }))
        $existing = (Invoke-Az @('network', 'vnet', 'list', '--query', '[].addressSpace.addressPrefixes[]', '--output', 'json')) | ConvertFrom-Json
        $picked = @()
        foreach ($x in 200..250) {
            $cand = "10.$x.0.0/24"
            if (-not (Test-Overlap -Candidate $cand -Existing (@($existing) + $picked))) { $picked += $cand }
            if ($picked.Count -eq 2) { break }
        }
        if ($picked.Count -lt 2) { throw 'No free /24 pair found in 10.200-250.x.x; choose ranges manually.' }
        $state = [pscustomobject]@{
            RunId = $runId
            ResourceGroup = "rg-dbxcmk-krc-$runId"
            WorkspaceVnetCidr = $picked[0]
            TransitVnetCidr = $picked[1]
        }
        $state | ConvertTo-Json | Set-Content -Path $StatePath -Encoding UTF8
    }
    Write-Output ("RunId={0}; ResourceGroup={1}" -f $state.RunId, $state.ResourceGroup)

    # ---- Resource group (new only) -----------------------------------------------
    $rgExists = (Invoke-Az @('group', 'exists', '--name', $state.ResourceGroup)).Trim()
    if ($rgExists -eq 'true') {
        $rg = (Invoke-Az @('group', 'show', '--name', $state.ResourceGroup, '--output', 'json')) | ConvertFrom-Json
        if ($rg.location -ne $Location -or $rg.tags.run -ne $state.RunId) { throw 'Existing RG is not owned by this run; refusing to touch it.' }
        Write-Output 'Resource group already created by this run; continuing idempotently.'
    }
    elseif (-not $ValidateOnly) {
        $null = Invoke-Az @('group', 'create', '--name', $state.ResourceGroup, '--location', $Location,
            '--tags', 'project=dbx-cmk-private-poc', 'environment=poc', 'region=koreacentral', "run=$($state.RunId)", 'managedBy=iac')
        Write-Output 'Resource group created.'
    }
    else {
        # No resource group yet: compile-check the templates only (no Azure resources involved).
        $null = Invoke-Az @('bicep', 'build', '--file', (Join-Path $Root 'infra/main.bicep'), '--stdout')
        Write-Output 'ValidateOnly: Bicep compiled successfully; group-scoped validation needs the resource group.'
        return
    }

    # ---- AzureDatabricks enterprise application object ID (read-only) ------------
    $spObjectId = (Invoke-Az @('ad', 'sp', 'show', '--id', '2ff814a6-3304-4ab8-85cb-cd0e6f879c1d', '--query', 'id', '--output', 'tsv')).Trim()

    # ---- Parameters file (ignored directory) -------------------------------------
    $params = @{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters = @{
            runId = @{ value = $state.RunId }
            location = @{ value = $Location }
            workspaceVnetCidr = @{ value = $state.WorkspaceVnetCidr }
            transitVnetCidr = @{ value = $state.TransitVnetCidr }
            databricksServicePrincipalObjectId = @{ value = $spObjectId }
            enableCmk = @{ value = ($Stage -eq 'Cmk') }
            keyVersion = @{ value = $KeyVersion }
            vaultBypass = @{ value = $VaultBypass }
            tags = @{ value = @{ project = 'dbx-cmk-private-poc'; environment = 'poc'; region = 'koreacentral'; run = $state.RunId; managedBy = 'iac' } }
        }
    }
    if ([string]::IsNullOrWhiteSpace($VmSubnetId)) {
        $probe = Join-Path $Root '.local/vm/subnet-id.txt'
        if (Test-Path $probe) { $VmSubnetId = (Get-Content -Raw -Path $probe).Trim() }
    }
    $VmVnetId = ''
    if (-not [string]::IsNullOrWhiteSpace($VmSubnetId)) {
        $VmVnetId = $VmSubnetId -replace '/subnets/[^/]+$', ''
        Write-Output 'VM access endpoint: enabled (existing subnet IP only; no existing resource modified).'
    }
    $params.parameters.vmSubnetId = @{ value = $VmSubnetId }
    $params.parameters.vmVnetId = @{ value = $VmVnetId }
    $paramPath = Join-Path $StateDir 'parameters.json'
    $params | ConvertTo-Json -Depth 10 | Set-Content -Path $paramPath -Encoding UTF8

    $template = Join-Path $Root 'infra/main.bicep'
    $common = @('--resource-group', $state.ResourceGroup, '--template-file', $template, '--parameters', "@$paramPath", '--name', 'poc-main')

    $null = Invoke-Az (@('deployment', 'group', 'validate') + $common + @('--output', 'none'))
    Write-Output 'Template validation succeeded.'
    if ($ValidateOnly) { return }

    $result = Invoke-Az (@('deployment', 'group', 'create') + $common + @('--output', 'json'))
    $result | Set-Content -Path (Join-Path $StateDir "deployment-$Stage.json") -Encoding UTF8
    Write-Output ("Deployment stage {0} completed." -f $Stage)
}
catch {
    Write-Output ("DEPLOYMENT_STOPPED: {0}" -f $_.Exception.Message)
    throw
}
finally {
    $null = Stop-Transcript
}
