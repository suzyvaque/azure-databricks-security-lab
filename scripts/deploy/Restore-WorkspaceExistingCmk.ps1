#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][switch]$ConfirmRecovery)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out = Join-Path $root ('.local/deploy/recovery-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
$null = New-Item -ItemType Directory -Path $out -Force
function Invoke-RecoveryAz {
    param([string[]]$Arguments)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $text = & az.cmd @Arguments --only-show-errors 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($code -ne 0) { throw ($text | Out-String) }
    return ($text | Out-String)
}
function Save-RecoveryJson {
    param([string]$Name, $Value)
    [IO.File]::WriteAllText((Join-Path $out $Name), ($Value | ConvertTo-Json -Depth 40), (New-Object Text.UTF8Encoding($false)))
}
function Assert-RecoveryVault {
    param($Vault)
    if ($Vault.properties.publicNetworkAccess -ne 'Enabled' -or $Vault.properties.networkAcls.bypass -ne 'None' -or
        $Vault.properties.networkAcls.defaultAction -ne 'Deny' -or @($Vault.properties.networkAcls.ipRules).Count -ne 1 -or
        @($Vault.properties.networkAcls.virtualNetworkRules).Count -ne 0) { throw 'Expected selected-IP vault settings; refusing recovery with different settings.' }
}
$result = [ordered]@{StartedUtc=[DateTime]::UtcNow.ToString('o');Outcome='InProgress'}
try {
    if (-not $ConfirmRecovery) { throw 'Explicit recovery confirmation required.' }
    $s = Get-Content -Raw (Join-Path $root '.local/deploy/run.json') | ConvertFrom-Json
    $rg = ConvertFrom-Json -InputObject (Invoke-RecoveryAz @('group','show','-n',$s.ResourceGroup,'-o','json'))
    if ($rg.location -ne 'koreacentral' -or $rg.tags.run -ne $s.RunId) { throw 'PoC ownership mismatch.' }
    $ws = ConvertFrom-Json -InputObject (Invoke-RecoveryAz @('resource','show','-g',$s.ResourceGroup,'-n',"dbw-dbxcmk-krc-$($s.RunId)",'--resource-type','Microsoft.Databricks/workspaces','--api-version','2024-05-01','-o','json'))
    Save-RecoveryJson 'workspace-before.json' $ws
    $key = $ws.properties.encryption.entities.managedServices.keyVaultProperties
    if ([string]::IsNullOrWhiteSpace($key.keyVersion)) { throw 'No existing pinned CMK version; stop.' }
    $vaultName = ([uri]$key.keyVaultUri).Host.Split('.')[0]
    $vault = ConvertFrom-Json -InputObject (Invoke-RecoveryAz @('keyvault','show','-n',$vaultName,'-g',$s.ResourceGroup,'-o','json'))
    Assert-RecoveryVault $vault
    Save-RecoveryJson 'vault-before.json' $vault
    $keyInfo = ConvertFrom-Json -InputObject (Invoke-RecoveryAz @('keyvault','key','show','--vault-name',$vaultName,'--name',$key.keyName,'--version',$key.keyVersion,'-o','json'))
    if (-not $keyInfo.attributes.enabled) { throw 'Existing CMK version is not enabled.' }
    $parameters = @{}
    foreach ($name in @('customVirtualNetworkId','customPublicSubnetName','customPrivateSubnetName','enableNoPublicIp')) {
        if ($null -eq $ws.properties.parameters.PSObject.Properties[$name]) { throw "Required workspace parameter absent: $name" }
        $parameters[$name] = @{value=$ws.properties.parameters.$name.value}
    }
    if ($ws.location -ne 'koreacentral' -or $ws.sku.name -ne 'premium' -or $ws.properties.publicNetworkAccess -ne 'Disabled' -or
        $ws.properties.requiredNsgRules -ne 'NoAzureDatabricksRules' -or $parameters.enableNoPublicIp.value -ne $true) { throw 'Workspace isolation checks failed.' }
    $values = @{workspaceName=$ws.name;location=$ws.location;tags=$ws.tags;managedResourceGroupId=$ws.properties.managedResourceGroupId;
        workspaceParameters=$parameters;keyVaultUri=$key.keyVaultUri;keyName=$key.keyName;keyVersion=$key.keyVersion}
    $p = @{}
    foreach ($name in $values.Keys) { $p[$name] = @{value=$values[$name]} }
    Save-RecoveryJson 'parameters.json' @{parameters=$p}
    $result.WorkspaceBefore = $ws.properties.provisioningState
    $result.ReappliesExistingKeyVersion = $true
    $result.DeploymentStartedUtc = [DateTime]::UtcNow.ToString('o')
    Save-RecoveryJson 'result.json' $result
    try {
        $deployment = Invoke-RecoveryAz @('deployment','group','create','-g',$s.ResourceGroup,'-n','poc-existing-cmk-recovery',
            '--template-file',(Join-Path $root 'infra/cmk-workspace-only.bicep'),'--parameters',('@' + (Join-Path $out 'parameters.json')),'-o','json')
        [IO.File]::WriteAllText((Join-Path $out 'deployment.json'),$deployment)
        $result.Outcome = 'DeploymentSucceeded'
    } catch { $result.Outcome='DeploymentFailed'; $result.Error=$_.Exception.Message }
    $after = ConvertFrom-Json -InputObject (Invoke-RecoveryAz @('resource','show','--ids',$ws.id,'--api-version','2024-05-01','-o','json'))
    $vaultAfter = ConvertFrom-Json -InputObject (Invoke-RecoveryAz @('keyvault','show','-n',$vaultName,'-g',$s.ResourceGroup,'-o','json'))
    Save-RecoveryJson 'workspace-after.json' $after
    Save-RecoveryJson 'vault-after.json' $vaultAfter
    Assert-RecoveryVault $vaultAfter
    $result.WorkspaceState = $after.properties.provisioningState
    $result.ExistingKeyVersionPreserved = ($after.properties.encryption.entities.managedServices.keyVaultProperties.keyVersion -eq $key.keyVersion)
    $result.VaultTagsPreserved = (($vault.tags | ConvertTo-Json -Compress) -eq ($vaultAfter.tags | ConvertTo-Json -Compress))
    $result.VaultNetworkPreserved = (($vault.properties.networkAcls | ConvertTo-Json -Depth 10 -Compress) -eq ($vaultAfter.properties.networkAcls | ConvertTo-Json -Depth 10 -Compress))
    $result.WorkspacePublicAccessDisabled = ($after.properties.publicNetworkAccess -eq 'Disabled')
    if ($result.WorkspaceState -eq 'Succeeded' -and $result.ExistingKeyVersionPreserved -and $result.VaultTagsPreserved -and $result.VaultNetworkPreserved -and $result.WorkspacePublicAccessDisabled) { $result.Outcome='Recovered' }
} catch { $result.Outcome='Stopped'; $result.Error=$_.Exception.Message; $result.ErrorPosition=$_.InvocationInfo.PositionMessage }
finally { $result.FinishedUtc=[DateTime]::UtcNow.ToString('o'); Save-RecoveryJson 'result.json' $result; Write-Output ('RECOVERY ' + $result.Outcome) }