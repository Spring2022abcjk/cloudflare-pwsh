[CmdletBinding()]
param(
    [string]$BaseUrl = 'https://api.cloudflare.com/client/v4/',
    [string]$Token = $env:CF_API_TOKEN,
    [string]$ZoneId = $env:CF_ZONE_ID
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Token)) {
    Write-Output 'SKIP real account validation: CF_API_TOKEN is not set.'
    exit 0
}

$headers = @{ Authorization = "Bearer $Token" }
$verifyUri = [Uri]::new($BaseUrl.TrimEnd('/') + '/user/tokens/verify')
$zonesUri = [Uri]::new($BaseUrl.TrimEnd('/') + '/zones?per_page=1')

function Assert-CfSuccess {
    param(
        [Parameter(Mandatory)][object]$Response,
        [Parameter(Mandatory)][string]$Operation
    )

    $success = $Response.PSObject.Properties['success']
    if ($null -eq $success -or $success.Value -ne $true) {
        $detail = if ($null -ne $Response.PSObject.Properties['errors']) {
            $Response.errors | ConvertTo-Json -Compress -Depth 10
        } else {
            'response did not contain success=true'
        }
        throw "$Operation did not return success=true: $detail"
    }
}

try {
    $verify = Invoke-RestMethod -Method Get -Uri $verifyUri -Headers $headers -ErrorAction Stop
    $zones = Invoke-RestMethod -Method Get -Uri $zonesUri -Headers $headers -ErrorAction Stop
    Assert-CfSuccess $verify 'API token verification'
    Assert-CfSuccess $zones 'zone listing'
    $zoneCount = [int]$zones.result_info.total_count
    [pscustomobject]@{
        Check = 'api-token-and-zones'
        TokenVerifySuccess = [bool]$verify.success
        ZoneListSuccess = [bool]$zones.success
        ZoneCount = $zoneCount
        DnsRead = 'not-run'
    }
} catch {
    throw "Real account verification failed: $($_.Exception.Message)"
}

if ([string]::IsNullOrWhiteSpace($ZoneId)) {
    Write-Output 'DNS read not run: provide -ZoneId or CF_ZONE_ID for a constrained read-only DNS check.'
    exit 0
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$moduleManifest = Join-Path $projectRoot 'module/Cloudflare.PowerShell/Cloudflare.PowerShell.psd1'
Import-Module $moduleManifest -Force

try {
    $records = @(Get-CfDnsRecord -ZoneId $ZoneId -BaseUrl $BaseUrl -Token $Token -ErrorAction Stop)
    [pscustomobject]@{
        Check = 'dns-record-list'
        ZoneIdSupplied = $true
        RecordCount = $records.Count
        DnsRead = 'passed'
    }
} catch {
    $status = if ($_.Exception.PSObject.Properties.Name -contains 'StatusCode') { [int]$_.Exception.StatusCode } else { 0 }
    [pscustomobject]@{
        Check = 'dns-record-list'
        ZoneIdSupplied = $true
        DnsRead = 'failed'
        ErrorId = $_.FullyQualifiedErrorId
        Status = $status
        Category = [string]$_.CategoryInfo.Category
    }
    exit 1
}
