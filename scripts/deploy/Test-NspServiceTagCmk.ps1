#Requires -Version 5.1
<#
.SYNOPSIS
Test native AzureDatabricks NSP service-tag admission, only if Azure accepts the rule.
.DESCRIPTION
Creates an isolated Korea Central perimeter/profile and tries one native Inbound serviceTags rule.
No vault association or access change unless the rule is read back correctly. No prefix expansion,
alternate tags, policy registration, bypass or service-tag fallback. On rule rejection the working
selected-IP vault is left untouched; empty NSP/profile are retained as recorded test artifacts.
If accepted, associate vault Enforced, LAW Learning, remove vault IP rules and set Disabled/None.
Then create a new key over VM PE and update only the workspace. No automatic recovery.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][switch]$ConfirmServiceTagTest)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out = Join-Path $root ('.local/deploy/nsp-tag-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
$null = New-Item -ItemType Directory -Path $out -Force
function Invoke-TagAz {
    param([string[]]$Arguments)
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $text = & az.cmd @Arguments --only-show-errors 2>&1
    $code = $LASTEXITCODE; $ErrorActionPreference = $old
    if ($code -ne 0) { throw ($text | Out-String) }
    return ($text | Out-String)
}
function Save-TagJson {
    param([string]$Name, $Value)
    [IO.File]::WriteAllText((Join-Path $out $Name), ($Value | ConvertTo-Json -Depth 40), (New-Object Text.UTF8Encoding($false)))
}
function Read-TagVault { return (ConvertFrom-Json -InputObject (Invoke-TagAz @('keyvault','show','-n',$vaultName,'-g',$group,'-o','json'))) }
$result = [ordered]@{StartedUtc=[DateTime]::UtcNow.ToString('o');Outcome='InProgress';VaultChanged=$false;ServiceTag='AzureDatabricks'}
try {
    if (-not $ConfirmServiceTagTest) { throw 'Explicit confirmation required.' }
    $s = Get-Content -Raw (Join-Path $root '.local/deploy/run.json') | ConvertFrom-Json
    $group = $s.ResourceGroup
    $rg = ConvertFrom-Json -InputObject (Invoke-TagAz @('group','show','-n',$group,'-o','json'))
    if ($rg.location -ne 'koreacentral' -or $rg.tags.run -ne $s.RunId) { throw 'Ownership check failed.' }
    $vs = ConvertFrom-Json -InputObject (Invoke-TagAz @('keyvault','list','-g',$group,'-o','json'))
    if (@($vs).Count -ne 1) { throw 'Expected one PoC vault.' }
    $vaultName = $vs[0].name
    $before = Read-TagVault
    Save-TagJson 'vault-before.json' $before
    if ($before.properties.publicNetworkAccess -ne 'Enabled' -or $before.properties.networkAcls.bypass -ne 'None' -or
        $before.properties.networkAcls.defaultAction -ne 'Deny' -or @($before.properties.networkAcls.ipRules).Count -ne 1) { throw 'Expected working selected-IP baseline.' }
    $ws = ConvertFrom-Json -InputObject (Invoke-TagAz @('resource','show','-g',$group,'-n',"dbw-dbxcmk-krc-$($s.RunId)",'--resource-type','Microsoft.Databricks/workspaces','--api-version','2024-05-01','-o','json'))
    Save-TagJson 'workspace-before.json' $ws
    if ($ws.properties.provisioningState -ne 'Succeeded') { throw 'Selected-IP workspace must first be Succeeded.' }
    $nsp = "nsp-dbxcmk-krc-$($s.RunId)-tag"
    $existing = ConvertFrom-Json -InputObject (Invoke-TagAz @('network','perimeter','list','-g',$group,'-o','json'))
    foreach ($item in $existing) { if ($null -ne $item -and $item.name -eq $nsp) { throw 'Isolated test perimeter already exists; stop for review.' } }
    $null = Invoke-TagAz @('network','perimeter','create','-n',$nsp,'-g',$group,'-l','koreacentral','-o','none')
    $null = Invoke-TagAz @('network','perimeter','profile','create','-n','profile-tag-test','--perimeter-name',$nsp,'-g',$group,'-o','none')
    $result.PerimeterCreated=$true
    Save-TagJson 'result.json' $result
    try {
        $ruleText = Invoke-TagAz @('network','perimeter','profile','access-rule','create','-n','allow-databricks-tag',
            '--profile-name','profile-tag-test','--perimeter-name',$nsp,'-g',$group,'--direction','Inbound','--service-tags','[AzureDatabricks]','-o','json')
        Save-TagJson 'rule-create.json' (ConvertFrom-Json -InputObject $ruleText)
    } catch {
        $result.Outcome='NativeServiceTagRuleRejected'; $result.Error=$_.Exception.Message
        Save-TagJson 'vault-after.json' (Read-TagVault)
        throw 'Native service-tag configuration rejected; vault left untouched. See local result error.'
    }
    $rule = ConvertFrom-Json -InputObject (Invoke-TagAz @('network','perimeter','profile','access-rule','show','-n','allow-databricks-tag',
        '--profile-name','profile-tag-test','--perimeter-name',$nsp,'-g',$group,'-o','json'))
    Save-TagJson 'rule-readback.json' $rule
    if ($rule.direction -ne 'Inbound' -or @($rule.serviceTags).Count -ne 1 -or $rule.serviceTags[0] -ne 'AzureDatabricks') { throw 'Native rule read-back mismatch; vault left untouched.' }
    $profile = ConvertFrom-Json -InputObject (Invoke-TagAz @('network','perimeter','profile','show','-n','profile-tag-test','--perimeter-name',$nsp,'-g',$group,'-o','json'))
    $law = ConvertFrom-Json -InputObject (Invoke-TagAz @('resource','show','-g',$group,'-n',"law-dbxcmk-krc-$($s.RunId)",'--resource-type','Microsoft.OperationalInsights/workspaces','-o','json'))
    $null = Invoke-TagAz @('network','perimeter','association','create','-n','assoc-law','--perimeter-name',$nsp,'-g',$group,'--access-mode','Learning','--private-link-resource',("{id:"+$law.id+'}'),'--profile',("{id:"+$profile.id+'}'),'-o','none')
    $null = Invoke-TagAz @('network','perimeter','association','create','-n','assoc-vault','--perimeter-name',$nsp,'-g',$group,'--access-mode','Enforced','--private-link-resource',("{id:"+$before.id+'}'),'--profile',("{id:"+$profile.id+'}'),'-o','none')
    $result.VaultChanged=$true
    Save-TagJson 'result.json' $result
    foreach ($ip in $before.properties.networkAcls.ipRules) { $null = Invoke-TagAz @('keyvault','network-rule','remove','-n',$vaultName,'-g',$group,'--ip-address',$ip.value,'-o','none') }
    $null = Invoke-TagAz @('keyvault','update','-n',$vaultName,'-g',$group,'--public-network-access','Disabled','--default-action','Deny','--bypass','None','-o','none')
    $testVault=Read-TagVault
    Save-TagJson 'vault-test-config.json' $testVault
    if ($testVault.properties.publicNetworkAccess -ne 'Disabled' -or $testVault.properties.networkAcls.bypass -ne 'None' -or @($testVault.properties.networkAcls.ipRules).Count -ne 0) { throw 'Disabled/None/no-IP test flags not reached.' }
    $keyRef=$ws.properties.encryption.entities.managedServices.keyVaultProperties
    $dns=@(Resolve-DnsName "$vaultName.vault.azure.net" -Type A | Where-Object {$_.Type -eq 'A'})
    if (-not $dns.Count -or @($dns | Where-Object {$_.IPAddress -notmatch '^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.)'}).Count) { throw 'Private VM DNS required.' }
    $key=ConvertFrom-Json -InputObject (Invoke-TagAz @('keyvault','key','create','--vault-name',$vaultName,'--name',$keyRef.keyName,'--kty','RSA','--size','2048','--protection','software','-o','json'))
    $version=($key.key.kid -split '/')[-1]
    Save-TagJson 'key.json' @{KeyName=$keyRef.keyName;KeyVersion=$version;Enabled=$key.attributes.enabled}
    $ps=@{}
    foreach($name in @('customVirtualNetworkId','customPublicSubnetName','customPrivateSubnetName','enableNoPublicIp')) {$ps[$name]=@{value=$ws.properties.parameters.$name.value}}
    $values=@{workspaceName=$ws.name;location=$ws.location;tags=$ws.tags;managedResourceGroupId=$ws.properties.managedResourceGroupId;workspaceParameters=$ps;keyVaultUri=$keyRef.keyVaultUri;keyName=$keyRef.keyName;keyVersion=$version}
    $p=@{};foreach($name in $values.Keys){$p[$name]=@{value=$values[$name]}}
    Save-TagJson 'parameters.json' @{parameters=$p}
    Start-Sleep -Seconds 150
    $result.CmkStartedUtc=[DateTime]::UtcNow.ToString('o');Save-TagJson 'result.json' $result
    try {
        $deployment=Invoke-TagAz @('deployment','group','create','-g',$group,'-n','poc-nsp-tag-cmk','--template-file',(Join-Path $root 'infra/cmk-workspace-only.bicep'),'--parameters',('@'+(Join-Path $out 'parameters.json')),'-o','json')
        [IO.File]::WriteAllText((Join-Path $out 'deployment.json'),$deployment)
        $result.Outcome='CmkDeploymentSucceeded'
    } catch {$result.Outcome='CmkDeploymentFailed';$result.Error=$_.Exception.Message}
    $after=Read-TagVault;Save-TagJson 'vault-after.json' $after
    $end=ConvertFrom-Json -InputObject (Invoke-TagAz @('resource','show','--ids',$ws.id,'--api-version','2024-05-01','-o','json'))
    Save-TagJson 'workspace-after.json' $end
    $result.WorkspaceState=$end.properties.provisioningState
    $result.AttemptedKeyApplied=($end.properties.encryption.entities.managedServices.keyVaultProperties.keyVersion -eq $version)
    $result.VaultTagsPreserved=(($before.tags|ConvertTo-Json -Compress) -eq ($after.tags|ConvertTo-Json -Compress))
} catch {
    if($result.Outcome -eq 'InProgress'){$result.Outcome='Stopped';$result.Error=$_.Exception.Message}
    $result.ErrorPosition=$_.InvocationInfo.PositionMessage
} finally {$result.FinishedUtc=[DateTime]::UtcNow.ToString('o');Save-TagJson 'result.json' $result;Write-Output ('NSP_TAG_TEST '+$result.Outcome)}