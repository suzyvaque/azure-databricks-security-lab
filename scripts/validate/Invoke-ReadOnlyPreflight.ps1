#Requires -Version 5.1
<#
.SYNOPSIS
Read-only Azure/VM discovery. Writes sensitive metadata ONLY under ignored .local.
.DESCRIPTION
No login/account selection, extension installation, provider registration, deployment,
resource changes, secret retrieval or access-token output. Run on the existing VM
only if you want local OS DNS/routes to describe that VM. Results need human review.
#>
[CmdletBinding()]
param(
    [ValidatePattern('^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Compute/virtualMachines/[^/]+$')]
    [string]$VmResourceId,
    [ValidateSet('koreacentral')]
    [string]$Location = 'koreacentral'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$out = Join-Path $root ".local/preflight/$stamp"
$null = New-Item -ItemType Directory -Path $out -Force
$script:checks = New-Object 'System.Collections.Generic.List[object]'
$oldDynamic = $env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL
$oldTelemetry = $env:AZURE_CORE_COLLECT_TELEMETRY
$env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL = 'no'
$env:AZURE_CORE_COLLECT_TELEMETRY = 'no'

function Save-LocalJson {
    param([string]$Name, [object]$Value)
    $Value | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath (Join-Path $out "$Name.json") -Encoding UTF8
}

function Get-JsonProperty {
    param([object]$Object, [string]$Name)
    # Optional ARM properties can be omitted, not just null. StrictMode requires
    # checking property existence before member access.
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Read-Azure {
    param([string]$Name, [string[]]$Arguments)
    # Native stderr can contain internal identifiers: suppress it from the console.
    # The entire .local directory is ignored; never force-add it to Git.
    $stderr = Join-Path $out "$Name.stderr.txt"
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $raw = & az @Arguments --only-show-errors --output json 2> $stderr
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    if ($code -ne 0) {
        $script:checks.Add([pscustomobject]@{ Check = $Name; Status = 'Blocked'; ExitCode = $code })
        return $null
    }
    try {
        $text = $raw -join "`n"
        if ([string]::IsNullOrWhiteSpace($text)) {
            $script:checks.Add([pscustomobject]@{ Check = $Name; Status = 'Empty-response'; ExitCode = 0 })
            return $null
        }
        $value = $text | ConvertFrom-Json
        Save-LocalJson -Name $Name -Value $value
        $script:checks.Add([pscustomobject]@{ Check = $Name; Status = 'Collected-not-validated'; ExitCode = 0 })
        return $value
    }
    catch {
        $script:checks.Add([pscustomobject]@{ Check = $Name; Status = 'Invalid-JSON'; ExitCode = 0 })
        return $null
    }
}

try {
    Save-LocalJson -Name 'execution' -Value @{
        StartedUtc = [DateTime]::UtcNow.ToString('o')
        Location = $Location
        PowershellVersion = $PSVersionTable.PSVersion.ToString()
        LocalOsIsAzureVm = 'Not established; do not assume local OS data describes target VM'
    }
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'Azure CLI not found. No Azure commands executed; install tooling separately after review.'
    }
    $null = Read-Azure -Name 'cli-version' -Arguments @('version')
    $null = Read-Azure -Name 'extensions' -Arguments @('extension', 'list')
    $account = Read-Azure -Name 'account' -Arguments @('account', 'show')
    if ($null -eq $account) { throw 'Azure context could not be read. No login or subscription changes attempted.' }
    $cloud = Read-Azure -Name 'cloud' -Arguments @('cloud', 'show')
    if ((Get-JsonProperty -Object $cloud -Name 'name') -ne 'AzureCloud') {
        throw 'Expected AzureCloud; stop rather than select another cloud or region.'
    }
    $subscription = Get-JsonProperty -Object $account -Name 'id'
    if ([string]::IsNullOrWhiteSpace($subscription)) { throw 'Account response lacks subscription context; stop.' }
    $null = Read-Azure -Name 'subscription-locations' -Arguments @('account', 'list-locations')
    # These are GET operations, not effective-write permission proofs. Deny assignments,
    # PIM, policy and scope restrictions still require review.
    $null = Read-Azure -Name 'subscription-permissions' -Arguments @(
        'rest', '--method', 'get', '--url',
        "https://management.azure.com/subscriptions/$subscription/providers/Microsoft.Authorization/permissions?api-version=2022-04-01")
    foreach ($provider in @('Microsoft.Databricks', 'Microsoft.Network', 'Microsoft.KeyVault',
            'Microsoft.OperationalInsights', 'Microsoft.Insights', 'Microsoft.Compute', 'Microsoft.Storage')) {
        $null = Read-Azure -Name ("provider-" + $provider) -Arguments @('provider', 'show', '--namespace', $provider)
    }
    $null = Read-Azure -Name 'compute-skus-krc' -Arguments @('vm', 'list-skus', '--location', 'koreacentral', '--all')
    $null = Read-Azure -Name 'compute-usage-krc' -Arguments @('vm', 'list-usage', '--location', 'koreacentral')
    $null = Read-Azure -Name 'network-usage-krc' -Arguments @('network', 'list-usages', '--location', 'koreacentral')
    $null = Read-Azure -Name 'policy-assignments' -Arguments @('policy', 'assignment', 'list', '--scope', "/subscriptions/$subscription", '--disable-scope-strict-match')
    $null = Read-Azure -Name 'databricks-enterprise-application' -Arguments @('ad', 'sp', 'show', '--id', '2ff814a6-3304-4ab8-85cb-cd0e6f879c1d')

    if ($VmResourceId) {
        $vm = Read-Azure -Name 'existing-vm' -Arguments @('vm', 'show', '--ids', $VmResourceId)
        if ($null -ne $vm) {
            $index = 0
            $networkProfile = Get-JsonProperty -Object $vm -Name 'networkProfile'
            $nicReferences = Get-JsonProperty -Object $networkProfile -Name 'networkInterfaces'
            foreach ($nicRef in @($nicReferences)) {
                if ($null -eq $nicRef) { continue }
                $index++
                $nic = Read-Azure -Name "nic-$index" -Arguments @('network', 'nic', 'show', '--ids', $nicRef.id)
                if ($null -eq $nic) { continue }
                $null = Read-Azure -Name "nic-$index-effective-nsg" -Arguments @('network', 'nic', 'list-effective-nsg', '--ids', $nicRef.id)
                $null = Read-Azure -Name "nic-$index-effective-routes" -Arguments @('network', 'nic', 'show-effective-route-table', '--ids', $nicRef.id)
                $nicNsg = Get-JsonProperty -Object $nic -Name 'networkSecurityGroup'
                if ($null -ne $nicNsg) {
                    $null = Read-Azure -Name "nic-$index-nsg" -Arguments @('network', 'nsg', 'show', '--ids', $nicNsg.id)
                }
                $ipIndex = 0
                $ipConfigurations = Get-JsonProperty -Object $nic -Name 'ipConfigurations'
                foreach ($ip in @($ipConfigurations)) {
                    if ($null -eq $ip) { continue }
                    $ipIndex++
                    $ipSubnet = Get-JsonProperty -Object $ip -Name 'subnet'
                    if ($null -eq $ipSubnet) { continue }
                    $subnetId = $ipSubnet.id
                    $vnetId = $subnetId -replace '/subnets/[^/]+$', ''
                    # GET full VNet includes all subnets, their NSG/UDR references, DNS and peerings.
                    $vnet = Read-Azure -Name "nic-$index-ip-$ipIndex-vnet" -Arguments @('network', 'vnet', 'show', '--ids', $vnetId)
                    if ($null -eq $vnet) { continue }
                    $vnetSubnets = Get-JsonProperty -Object $vnet -Name 'subnets'
                    $subnet = @($vnetSubnets | Where-Object { $null -ne $_ -and $_.id -eq $subnetId })
                    if ($subnet.Count -ne 1) { continue }
                    $subnetNsg = Get-JsonProperty -Object $subnet[0] -Name 'networkSecurityGroup'
                    if ($null -ne $subnetNsg) {
                        $null = Read-Azure -Name "nic-$index-ip-$ipIndex-subnet-nsg" -Arguments @('network', 'nsg', 'show', '--ids', $subnetNsg.id)
                    }
                    $routeTable = Get-JsonProperty -Object $subnet[0] -Name 'routeTable'
                    if ($null -ne $routeTable) {
                        $null = Read-Azure -Name "nic-$index-ip-$ipIndex-route-table" -Arguments @('network', 'route-table', 'show', '--ids', $routeTable.id)
                    }
                    $null = Read-Azure -Name "nic-$index-ip-$ipIndex-vnet-permissions" -Arguments @(
                        'rest', '--method', 'get', '--url', "https://management.azure.com$vnetId/providers/Microsoft.Authorization/permissions?api-version=2022-04-01")
                }
            }
        }
    }
    else {
        $script:checks.Add([pscustomobject]@{ Check = 'Existing-VM-network'; Status = 'Blocked-VM-ID-required'; ExitCode = $null })
    }
    foreach ($command in @('Get-DnsClientServerAddress', 'Get-NetRoute')) {
        if (Get-Command $command -ErrorAction SilentlyContinue) {
            try { Save-LocalJson -Name "local-os-$command" -Value (& $command -ErrorAction Stop) }
            catch { $script:checks.Add([pscustomobject]@{ Check = $command; Status = 'Blocked'; ExitCode = $null }) }
        }
    }
}
finally {
    $env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL = $oldDynamic
    $env:AZURE_CORE_COLLECT_TELEMETRY = $oldTelemetry
    Save-LocalJson -Name 'collection-summary' -Value @{
        FinishedUtc = [DateTime]::UtcNow.ToString('o')
        Checks = @($script:checks.ToArray())
        DeploymentReady = $false
        Note = 'Collection only. Manual permissions, DNS conflicts, KRC features/SKUs, quotas, policy and CMK support review required.'
    }
    Write-Output 'Preflight collection finished or stopped. Review ignored .local/preflight evidence locally. No Azure writes attempted; deployment readiness NOT established.'
}