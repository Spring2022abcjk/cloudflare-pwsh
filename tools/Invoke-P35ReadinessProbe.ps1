[CmdletBinding()]
param(
    [string]$BaseUrl = 'https://api.cloudflare.com/client/v4/',
    [string]$TokenEnvironmentVariable = 'CF_API_TOKEN',
    [string]$AccountId = $env:CF_ACCOUNT_ID,
    [string]$ZoneId = $env:CF_ZONE_ID
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$token = [Environment]::GetEnvironmentVariable($TokenEnvironmentVariable)
$baseUri = $BaseUrl.TrimEnd('/')
$headers = if ([string]::IsNullOrWhiteSpace($token)) {
    @{}
} else {
    @{ Authorization = "Bearer $token"; Accept = 'application/json' }
}

function Get-HeaderValue {
    param(
        [Parameter(Mandatory = $true)][object]$Headers,
        [Parameter(Mandatory = $true)][string]$Name
    )

    try {
        $value = @($Headers.GetValues($Name)) -join ', '
    } catch {
        try {
            $value = $Headers[$Name]
        } catch {
            $value = ''
        }
    }
    if ($null -eq $value) {
        return ''
    }

    return [string]$value
}

function Invoke-P35ReadOnlyGet {
    param(
        [Parameter(Mandatory = $true)][string]$Check,
        [Parameter(Mandatory = $true)][string]$PathTemplate,
        [Parameter(Mandatory = $true)][string]$RequestPath,
        [Parameter(Mandatory = $true)][ValidateSet('Verify', 'Collection')][string]$Shape
    )

    $row = [ordered]@{
        Check = $Check
        Path = $PathTemplate
        HttpStatus = $null
        CloudflareSuccess = $null
        ResultCount = $null
        TokenStatus = $null
        RateLimit = ''
        RateLimitPolicy = ''
        RetryAfter = ''
        ErrorClass = ''
    }

    try {
        $response = Invoke-WebRequest -Method Get -Uri ($baseUri + $RequestPath) -Headers $headers -ErrorAction Stop
        $row.HttpStatus = [int]$response.StatusCode
        $row.RateLimit = Get-HeaderValue -Headers $response.Headers -Name 'Ratelimit'
        $row.RateLimitPolicy = Get-HeaderValue -Headers $response.Headers -Name 'Ratelimit-Policy'
        $row.RetryAfter = Get-HeaderValue -Headers $response.Headers -Name 'Retry-After'

        $body = $response.Content | ConvertFrom-Json
        if ($null -ne $body.PSObject.Properties['success']) {
            $row.CloudflareSuccess = [bool]$body.success
        }

        if ($Shape -eq 'Verify' -and $null -ne $body.result.status) {
            $row.TokenStatus = [string]$body.result.status
        }

        if ($Shape -eq 'Collection' -and $null -ne $body.result_info.total_count) {
            $row.ResultCount = [int]$body.result_info.total_count
        }
    } catch {
        $response = $_.Exception.Response
        if ($null -ne $response) {
            $row.HttpStatus = [int]$response.StatusCode
            $row.RateLimit = Get-HeaderValue -Headers $response.Headers -Name 'Ratelimit'
            $row.RateLimitPolicy = Get-HeaderValue -Headers $response.Headers -Name 'Ratelimit-Policy'
            $row.RetryAfter = Get-HeaderValue -Headers $response.Headers -Name 'Retry-After'
        }

        $row.ErrorClass = $_.Exception.GetType().FullName
    }

    return [pscustomobject]$row
}

$rows = @(
    [pscustomobject][ordered]@{
        Check = 'credential'
        CredentialEnvironmentVariable = $TokenEnvironmentVariable
        Present = (-not [string]::IsNullOrWhiteSpace($token))
    }
)

if ([string]::IsNullOrWhiteSpace($token)) {
    $rows | ConvertTo-Json -Depth 5
    exit 0
}

$rows += Invoke-P35ReadOnlyGet `
    -Check 'token-verify' `
    -PathTemplate '/user/tokens/verify' `
    -RequestPath '/user/tokens/verify' `
    -Shape Verify
$rows += Invoke-P35ReadOnlyGet `
    -Check 'account-list' `
    -PathTemplate '/accounts?per_page=5' `
    -RequestPath '/accounts?per_page=5' `
    -Shape Collection
$rows += Invoke-P35ReadOnlyGet `
    -Check 'zone-list' `
    -PathTemplate '/zones?per_page=5' `
    -RequestPath '/zones?per_page=5' `
    -Shape Collection

if ([string]::IsNullOrWhiteSpace($AccountId)) {
    $rows += [pscustomobject][ordered]@{
        Check = 'd1-database-list'
        Path = '/accounts/{account_id}/d1/database?per_page=10'
        Status = 'blocked-no-explicit-account-id'
    }
} else {
    $rows += Invoke-P35ReadOnlyGet `
        -Check 'd1-database-list' `
        -PathTemplate '/accounts/{account_id}/d1/database?per_page=10' `
        -RequestPath ("/accounts/{0}/d1/database?per_page=10" -f [Uri]::EscapeDataString($AccountId)) `
        -Shape Collection
}

if ([string]::IsNullOrWhiteSpace($ZoneId)) {
    $rows += [pscustomobject][ordered]@{
        Check = 'dns-record-list'
        Path = '/zones/{zone_id}/dns_records?per_page=1'
        Status = 'blocked-no-explicit-zone-id'
    }
    $rows += [pscustomobject][ordered]@{
        Check = 'healthcheck-list'
        Path = '/zones/{zone_id}/healthchecks?per_page=1'
        Status = 'blocked-no-explicit-zone-id'
    }
} else {
    $escapedZoneId = [Uri]::EscapeDataString($ZoneId)
    $rows += Invoke-P35ReadOnlyGet `
        -Check 'dns-record-list' `
        -PathTemplate '/zones/{zone_id}/dns_records?per_page=1' `
        -RequestPath ("/zones/{0}/dns_records?per_page=1" -f $escapedZoneId) `
        -Shape Collection
    $rows += Invoke-P35ReadOnlyGet `
        -Check 'healthcheck-list' `
        -PathTemplate '/zones/{zone_id}/healthchecks?per_page=1' `
        -RequestPath ("/zones/{0}/healthchecks?per_page=1" -f $escapedZoneId) `
        -Shape Collection
}

$rows | ConvertTo-Json -Depth 5
