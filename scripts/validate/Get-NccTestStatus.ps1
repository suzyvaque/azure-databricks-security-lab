#Requires -Version 5.1
<#
.SYNOPSIS
Read-only status for the NCC test: vault network settings, vault private endpoint connections,
target workspace state, and recent Databricks control-plane key requests in the vault audit log.
.DESCRIPTION
Makes no changes. Full detail (including addresses) is written to ignored .local/validate/ncc-status.json;
the console summary prints no addresses. Connections whose private endpoint is not one of ours are flagged
as "foreign" - an NCC rule appears here as a Pending or Approved connection created by Databricks.
#>
[CmdletBinding()]
param(
    [string]$SinceUtc = ([DateTime]::UtcNow.AddHours(-6).ToString('o'))
)

$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$Out = Join-Path $Root '.local/validate'
$null = New-Item -ItemType Directory -Path $Out -Force
$enc = New-Object Text.UTF8Encoding($false)

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

$state = Get-Content -Raw -Path (Join-Path $Root '.local/deploy/run.json') | ConvertFrom-Json
$rg = $state.ResourceGroup
$run = $state.RunId
$vaultName = (Invoke-Az @('keyvault', 'list', '-g', $rg, '--query', '[0].name', '-o', 'tsv')).Trim()
$vault = (Invoke-Az @('keyvault', 'show', '-n', $vaultName, '-g', $rg, '-o', 'json')) | ConvertFrom-Json

$summary = [ordered]@{ CapturedUtc = [DateTime]::UtcNow.ToString('o') }
$summary.Vault = [ordered]@{
    PublicNetworkAccess = $vault.properties.publicNetworkAccess
    Bypass              = $vault.properties.networkAcls.bypass
    DefaultAction       = $vault.properties.networkAcls.defaultAction
    IpRuleCount         = @($vault.properties.networkAcls.ipRules).Count
}

# Private endpoint connections on the vault (an NCC rule shows up here, created by Databricks).
$connJson = Invoke-Az @('network', 'private-endpoint-connection', 'list', '--id', $vault.id, '-o', 'json')
$conns = @()
if ($null -ne $connJson) {
    # Windows PowerShell 5.1 returns a JSON array as ONE object when piped; enumerate it explicitly.
    $parsed = $connJson | ConvertFrom-Json
    foreach ($item in $parsed) { $conns += $item }
}
$connSummary = foreach ($c in $conns) {
    $peId = [string]$c.properties.privateEndpoint.id
    $peName = if ($peId) { ($peId -split '/')[-1] } else { '' }
    [ordered]@{
        ConnectionName = ([string]$c.id -split '/')[-1]
        Status         = $c.properties.privateLinkServiceConnectionState.status
        Description    = $c.properties.privateLinkServiceConnectionState.description
        EndpointName   = $peName
        Ours           = [bool]($peName -like "pe-dbxcmk-krc-$run-*")
    }
}
$summary.VaultConnections = @($connSummary)
$summary.ForeignConnections = @($connSummary | Where-Object { -not $_.Ours }).Count

$wsJson = Invoke-Az @('resource', 'show', '-g', $rg, '-n', "dbw-dbxcmk-krc-$run", '--resource-type', 'Microsoft.Databricks/workspaces', '--api-version', '2024-05-01', '-o', 'json')
if ($null -ne $wsJson) {
    $ws = $wsJson | ConvertFrom-Json
    $summary.Workspace = [ordered]@{
        ProvisioningState   = $ws.properties.provisioningState
        PublicNetworkAccess = $ws.properties.publicNetworkAccess
        CmkKeyName          = $ws.properties.encryption.entities.managedServices.keyVaultProperties.keyName
        CmkKeyVersionLast6  = ([string]$ws.properties.encryption.entities.managedServices.keyVaultProperties.keyVersion) -replace '^.*(.{6})$', '$1'
    }
}

# Control-plane key requests (clients other than the Azure CLI) since the given time.
$cust = (Invoke-Az @('resource', 'show', '-g', $rg, '-n', "law-dbxcmk-krc-$run", '--resource-type', 'Microsoft.OperationalInsights/workspaces', '--query', 'properties.customerId', '-o', 'tsv')).Trim()
$q = "AZKVAuditLogs | where TimeGenerated > datetime($SinceUtc) | where ClientInfo !has 'AZURECLI' | where OperationName in ('KeyGet','KeyWrap','KeyUnwrap') | project TimeGenerated, OperationName, HttpStatusCode, ResultSignature, IsRbacAuthorized, IsAddressAuthorized, TrustedService, CallerIpAddress, ResultDescription | order by TimeGenerated asc"
$bodyPath = Join-Path $Out 'ncc-query.json'
[IO.File]::WriteAllText($bodyPath, (@{ query = $q } | ConvertTo-Json -Compress), $enc)
$auditJson = Invoke-Az @('rest', '--method', 'post', '--url', "https://api.loganalytics.io/v1/workspaces/$cust/query", '--resource', 'https://api.loganalytics.io', '--headers', 'Content-Type=application/json', '--body', "@$bodyPath", '-o', 'json')
$rows = @()
if ($null -ne $auditJson) {
    $t = ($auditJson | ConvertFrom-Json).tables[0]
    $cols = @($t.columns | ForEach-Object { $_.name })
    foreach ($r in $t.rows) {
        $o = [ordered]@{}
        for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $r[$i] }
        $rows += [pscustomobject]$o
    }
}
$summary.ControlPlaneKeyRequestsSince = $SinceUtc
$summary.ControlPlaneKeyRequests = @($rows | ForEach-Object {
        [ordered]@{
            TimeUtc = $_.TimeGenerated; Operation = $_.OperationName; Http = $_.HttpStatusCode; Result = $_.ResultSignature
            IsRbacAuthorized = $_.IsRbacAuthorized; IsAddressAuthorized = $_.IsAddressAuthorized; TrustedService = $_.TrustedService
            CallerIsPrivateRange = [bool]([string]$_.CallerIpAddress -match '^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.)')
        }
    })

# Full detail (with addresses) stays in the ignored local folder.
[IO.File]::WriteAllText((Join-Path $Out 'ncc-status-detail.json'), (@{ Summary = $summary; AuditRowsRaw = $rows } | ConvertTo-Json -Depth 8), $enc)
$text = $summary | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText((Join-Path $Out 'ncc-status.json'), $text, $enc)
$text
