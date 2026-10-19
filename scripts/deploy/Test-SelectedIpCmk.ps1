#Requires -Version 5.1
<#
.SYNOPSIS
Retry CMK after the owner supplies a policy-exclusion tag and selects one control-plane IP.
.DESCRIPTION
Requires vault Enabled / Deny / bypass None / one IP / no VNet rules and no PoC NSP.
Preserves vault tags: deploys only the target workspace, never the vault template.
Creates a fresh key version over the VM PE; retains all older versions. No automatic rollback.
All raw evidence, identifiers, addresses and tag values stay in ignored local storage.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][switch]$ConfirmSelectedIpTest)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out = Join-Path $root ('.local/deploy/selected-ip-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
$null = New-Item -ItemType Directory -Path $out -Force
function Az {
    param([string[]]$Arguments)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $text = & az.cmd @Arguments --only-show-errors 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($code -ne 0) { throw ($text | Out-String) }
    return ($text | Out-String)
}
function Save {
    param([string]$Name, $Value)
    [IO.File]::WriteAllText((Join-Path $out $Name), ($Value | ConvertTo-Json -Depth 40), (New-Object Text.UTF8Encoding($false)))
}
function Get-TestVault {
    $v = (Az @('keyvault','show','--name',($vaultId -split '/')[-1],'-o','json')) | ConvertFrom-Json
    if ($v.properties.publicNetworkAccess -ne 'Enabled' -or $v.properties.networkAcls.bypass -ne 'None' -or
        $v.properties.networkAcls.defaultAction -ne 'Deny' -or @($v.properties.networkAcls.ipRules).Count -ne 1 -or
        @($v.properties.networkAcls.virtualNetworkRules).Count -ne 0) { throw 'Selected-IP posture not reached; CMK must not run.' }
    return $v
}
$result = [ordered]@{ StartedUtc = [DateTime]::UtcNow.ToString('o'); Outcome = 'InProgress' }
try {
    if (-not $ConfirmSelectedIpTest) { throw 'Explicit confirmation required.' }
    $s = Get-Content -Raw (Join-Path $root '.local/deploy/run.json') | ConvertFrom-Json
    $rg = (Az @('group','show','-n',$s.ResourceGroup,'-o','json')) | ConvertFrom-Json
    if ($rg.location -ne 'koreacentral' -or $rg.tags.run -ne $s.RunId) { throw 'PoC ownership check failed.' }
    $vs = @((Az @('keyvault','list','-g',$s.ResourceGroup,'-o','json')) | ConvertFrom-Json)
    if ($vs.Count -ne 1) { throw 'Expected one PoC vault.' }
    $vaultId = $vs[0].id
    $before = Get-TestVault
    Save 'vault-before.json' $before
    $expected = Get-Content -Raw (Join-Path $root '.local/deploy/tagged-vault-before.json') | ConvertFrom-Json
    $prefix = [string]$expected[0].properties.networkAcls.ipRules[0].value
    if (([string]$before.properties.networkAcls.ipRules[0].value -replace '/32$','') -ne ($prefix -replace '/32$','')) { throw 'Allowed address changed from approved control-plane evidence.' }
    $perimeterList = ConvertFrom-Json -InputObject (Az @('network','perimeter','list','-g',$s.ResourceGroup,'-o','json'))
    foreach ($perimeter in $perimeterList) {
        if ($null -ne $perimeter) { throw 'Expected no perimeter in the PoC RG.' }
    }
    $result.SelectedIpPostureVerifiedUtc = [DateTime]::UtcNow.ToString('o')
    Save 'result.json' $result
    $dns = @(Resolve-DnsName "$($before.name).vault.azure.net" -Type A | Where-Object { $_.Type -eq 'A' })
    if (-not $dns.Count -or @($dns | Where-Object { $_.IPAddress -notmatch '^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.)' }).Count) { throw 'VM DNS must resolve only privately.' }
    $wsName = "dbw-dbxcmk-krc-$($s.RunId)"
    $ws = (Az @('resource','show','-g',$s.ResourceGroup,'-n',$wsName,'--resource-type','Microsoft.Databricks/workspaces','--api-version','2024-05-01','-o','json')) | ConvertFrom-Json
    Save 'workspace-before.json' $ws
    $keyName = $ws.properties.encryption.entities.managedServices.keyVaultProperties.keyName
    $key = (Az @('keyvault','key','create','--vault-name',$before.name,'--name',$keyName,'--kty','RSA','--size','2048','--protection','software','-o','json')) | ConvertFrom-Json
    $version = ($key.key.kid -split '/')[-1]
    if (-not $key.attributes.enabled -or $version -eq $ws.properties.encryption.entities.managedServices.keyVaultProperties.keyVersion) { throw 'Expected new enabled key version.' }
    Save 'key.json' @{KeyName=$keyName;KeyVersion=$version;Enabled=$true}
    # Reuse the known deployed VNet/SCC parameters, not service-generated/read-only fields.
    $ps = @{}
    foreach ($name in @('customVirtualNetworkId','customPublicSubnetName','customPrivateSubnetName','enableNoPublicIp')) {
        $ps[$name] = @{value=$ws.properties.parameters.$name.value}
    }
    if ($ws.location -ne 'koreacentral' -or $ws.properties.publicNetworkAccess -ne 'Disabled' -or $ps.enableNoPublicIp.value -ne $true) { throw 'Workspace isolation checks failed.' }
    $values = @{workspaceName=$wsName;location=$ws.location;tags=$ws.tags;managedResourceGroupId=$ws.properties.managedResourceGroupId;
        workspaceParameters=$ps;keyVaultUri=$before.properties.vaultUri;keyName=$keyName;keyVersion=$version}
    $params = @{}
    foreach ($name in $values.Keys) { $params[$name] = @{value=$values[$name]} }
    Save 'parameters.json' @{parameters=$params}
    Start-Sleep -Seconds 120
    $null = Get-TestVault
    $result.CmkStartedUtc = [DateTime]::UtcNow.ToString('o')
    Save 'result.json' $result
    try {
        $deployment = Az @('deployment','group','create','-g',$s.ResourceGroup,'-n','poc-selected-ip-cmk',
            '--template-file',(Join-Path $root 'infra/cmk-workspace-only.bicep'),'--parameters',("@" + (Join-Path $out 'parameters.json')),'-o','json')
        $deployment | Set-Content -Encoding UTF8 (Join-Path $out 'deployment.json')
        $result.Outcome = 'CmkDeploymentSucceeded'
    } catch { $result.Outcome = 'CmkDeploymentFailed'; $result.Error = $_.Exception.Message }
    $result.CmkFinishedUtc = [DateTime]::UtcNow.ToString('o')
    $after = Get-TestVault
    Save 'vault-after.json' $after
    $result.VaultTagsPreserved = (($before.tags | ConvertTo-Json -Compress) -eq ($after.tags | ConvertTo-Json -Compress))
    $end = (Az @('resource','show','--ids',$ws.id,'--api-version','2024-05-01','-o','json')) | ConvertFrom-Json
    Save 'workspace-after.json' $end
    $result.WorkspaceState = $end.properties.provisioningState
    $result.AttemptedKeyApplied = ($end.properties.encryption.entities.managedServices.keyVaultProperties.keyVersion -eq $version)
    if ($result.Outcome -eq 'CmkDeploymentSucceeded' -and ($result.WorkspaceState -ne 'Succeeded' -or -not $result.AttemptedKeyApplied -or -not $result.VaultTagsPreserved)) { throw 'Deployment succeeded but verification incomplete.' }
} catch { $result.Outcome = 'Stopped'; $result.Error = $_.Exception.Message; $result.ErrorPosition = $_.InvocationInfo.PositionMessage }
finally { $result.FinishedUtc = [DateTime]::UtcNow.ToString('o'); Save 'result.json' $result; Write-Output ('SELECTED_IP_TEST ' + $result.Outcome) }