#Requires -Version 5.1
<#
.SYNOPSIS
Creates the Managed Services CMK key in the private-only vault, from this VM, over the private endpoint.
.DESCRIPTION
- Grants the signed-in user "Key Vault Crypto Officer" on the NEW vault only (scope = vault).
- Requires the vault hostname to resolve to a private address from this VM; otherwise stops.
- Never enables public access or the trusted-services bypass.
- Writes the key version to ignored .local/deploy/key.json.
#>
[CmdletBinding()]
param([string]$KeyName = 'cmk-managed-services')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$StateDir = Join-Path $Root '.local/deploy'
$null = Start-Transcript -Path (Join-Path $StateDir ("key-{0}.log" -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))) -Force

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

try {
    $state = Get-Content -Raw -Path (Join-Path $StateDir 'run.json') | ConvertFrom-Json
    $rg = $state.ResourceGroup
    $vault = (Invoke-Az @('keyvault', 'list', '-g', $rg, '--query', '[0].name', '-o', 'tsv')).Trim()
    $vaultId = (Invoke-Az @('keyvault', 'show', '-n', $vault, '-g', $rg, '--query', 'id', '-o', 'tsv')).Trim()
    $props = (Invoke-Az @('keyvault', 'show', '-n', $vault, '-g', $rg, '-o', 'json')) | ConvertFrom-Json
    if ($props.properties.publicNetworkAccess -ne 'Disabled' -or $props.properties.networkAcls.bypass -ne 'None') {
        throw 'Vault is not in the required private-only state; refusing to continue.'
    }

    # DNS must resolve to a private address from this VM (private endpoint path).
    $answers = @(Resolve-DnsName -Name "$vault.vault.azure.net" -Type A -ErrorAction Stop | Where-Object { $_.Type -eq 'A' })
    $ip = $answers[0].IPAddress
    if ($ip -notmatch '^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.)') { throw 'Vault hostname does not resolve to a private address from this VM; stop (no public workaround).' }
    Write-Output 'Vault hostname resolves to a private address from this VM.'

    $me = (Invoke-Az @('ad', 'signed-in-user', 'show', '--query', 'id', '-o', 'tsv')).Trim()
    $existing = (Invoke-Az @('role', 'assignment', 'list', '--assignee', $me, '--scope', $vaultId, '--query', "[?roleDefinitionName=='Key Vault Crypto Officer'] | length(@)", '-o', 'tsv')).Trim()
    if ($existing -eq '0') {
        $null = Invoke-Az @('role', 'assignment', 'create', '--assignee-object-id', $me, '--assignee-principal-type', 'User', '--role', 'Key Vault Crypto Officer', '--scope', $vaultId)
        Write-Output 'Granted Key Vault Crypto Officer on the new vault to the signed-in user.'
    }

    # RBAC propagation can take minutes; retry the data-plane call over the private path.
    $created = $null
    foreach ($attempt in 1..12) {
        try {
            $created = (Invoke-Az @('keyvault', 'key', 'create', '--vault-name', $vault, '--name', $KeyName, '--kty', 'RSA', '--size', '2048', '--protection', 'software', '-o', 'json')) | ConvertFrom-Json
            break
        }
        catch {
            Write-Output ("Attempt {0}/12 not yet permitted; waiting 30s." -f $attempt)
            Start-Sleep -Seconds 30
        }
    }
    if ($null -eq $created) { throw 'Key creation did not succeed within the wait window.' }
    $version = ($created.key.kid -split '/')[-1]
    @{ KeyName = $KeyName; KeyVersion = $version; Enabled = $created.attributes.enabled } | ConvertTo-Json | Set-Content -Path (Join-Path $StateDir 'key.json') -Encoding UTF8
    Write-Output ("KEY_CREATED name={0} enabled={1}" -f $KeyName, $created.attributes.enabled)
}
catch {
    Write-Output ("KEY_STOPPED: {0}" -f $_.Exception.Message)
    throw
}
finally {
    $null = Stop-Transcript
}
