#Requires -Version 5.1
<#
.SYNOPSIS
Tests private reachability of the Databricks workspace from THIS VM. Read-only; sends no credentials.
.DESCRIPTION
For the workspace and the browser-authentication name:
  1. resolves the name and checks the answer is a private address
  2. opens a TCP connection and records the actual remote address
  3. completes a TLS handshake using the real hostname and checks certificate name validity
  4. requests the HTTPS root and records the status code
DNS alone is not treated as proof. An unauthenticated request cannot prove API access; authenticated access
is a separate step. Results go to ignored .local/validate/connectivity.json.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$Out = Join-Path $Root '.local/validate'
$null = New-Item -ItemType Directory -Path $Out -Force

function Invoke-Az {
    param([string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & az @Arguments --only-show-errors 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    if ($code -ne 0) { return $null }
    return ($output | Out-String).Trim()
}

function Test-Private { param([string]$Ip) return [bool]($Ip -match '^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.)') }

function Test-Host {
    param([string]$HostName)
    $r = [ordered]@{ Host = 'redacted'; Resolved = $null; ResolvedIsPrivate = $false; TcpConnected = $false; RemoteIsPrivate = $false; TlsOk = $false; HttpStatus = $null; Error = $null }
    try {
        $answers = @(Resolve-DnsName -Name $HostName -Type A -ErrorAction Stop | Where-Object { $_.Type -eq 'A' })
        $ip = $answers[0].IPAddress
        $r.ResolvedIsPrivate = Test-Private $ip
        $r.Resolved = if ($r.ResolvedIsPrivate) { 'private-address' } else { 'PUBLIC-address' }

        $client = New-Object Net.Sockets.TcpClient
        $task = $client.ConnectAsync($HostName, 443)
        if (-not $task.Wait(15000)) { throw 'TCP connect timed out' }
        $r.TcpConnected = $client.Connected
        $remote = ([Net.IPEndPoint]$client.Client.RemoteEndPoint).Address.ToString()
        $r.RemoteIsPrivate = Test-Private $remote

        $ssl = New-Object Net.Security.SslStream($client.GetStream(), $false)
        $ssl.AuthenticateAsClient($HostName)   # validates the certificate against the real hostname
        $r.TlsOk = $ssl.IsAuthenticated
        $ssl.Dispose(); $client.Close()

        try {
            $resp = Invoke-WebRequest -Uri "https://$HostName/" -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 30 -ErrorAction Stop
            $r.HttpStatus = [int]$resp.StatusCode
        }
        catch {
            if ($_.Exception.Response) { $r.HttpStatus = [int]$_.Exception.Response.StatusCode } else { $r.Error = $_.Exception.GetType().Name }
        }
    }
    catch { $r.Error = $_.Exception.Message }
    return [pscustomobject]$r
}

$state = Get-Content -Raw -Path (Join-Path $Root '.local/deploy/run.json') | ConvertFrom-Json
$rg = $state.ResourceGroup
$wsId = Invoke-Az @('resource', 'list', '-g', $rg, '--resource-type', 'Microsoft.Databricks/workspaces', '--query', "[?name=='dbw-dbxcmk-krc-$($state.RunId)'].id | [0]", '-o', 'tsv')
$wsUrl = Invoke-Az @('resource', 'show', '--ids', $wsId, '--api-version', '2024-05-01', '--query', 'properties.workspaceUrl', '-o', 'tsv')
if ([string]::IsNullOrWhiteSpace($wsUrl)) { throw 'Could not read the workspace URL.' }

$results = [ordered]@{}
$results.Workspace = Test-Host -HostName $wsUrl
# SSO callback name documented as pl-auth.<region>.azuredatabricks.net
$results.BrowserAuth = Test-Host -HostName 'koreacentral.pl-auth.azuredatabricks.net'
$results | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Out 'connectivity.json') -Encoding UTF8
$results | ConvertTo-Json -Depth 5
