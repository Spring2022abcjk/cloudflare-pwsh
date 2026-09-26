[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CandidateRoot,
    [switch]$CurrentCredentialUseApproved,
    [switch]$PreflightOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# This probe deliberately has no URL, method, retry, pagination, or output-file
# overrides. Its only possible live requests are the six GETs below.
$names = @(
    'CLOUDFLARE_POWERSHELL_INTEGRATION_TOKEN',
    'CLOUDFLARE_POWERSHELL_INTEGRATION_ACCOUNT_ID',
    'CLOUDFLARE_POWERSHELL_INTEGRATION_ZONE_ID'
)
$values = @{}
foreach ($name in $names) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Blocked: required environment variable is absent: $name"
    }
    $values[$name] = $value
}
if (-not $CurrentCredentialUseApproved) {
    throw 'Blocked: current credential use has not been approved.'
}

$candidate = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $CandidateRoot).Path)
$manifestPath = Join-Path $candidate 'candidate-manifest.json'
$zipPath = Join-Path $candidate 'Cloudflare.PowerShell.0.1.0.zip'
$modulePath = Join-Path $candidate 'package/Cloudflare.PowerShell/Cloudflare.PowerShell.psd1'
foreach ($path in @($manifestPath, $zipPath, $modulePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'Blocked: candidate package is incomplete.'
    }
}
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$head = ((& git rev-parse HEAD) -join "`n").Trim()
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ([string]$manifest.sourceRevision -cne $head -or
    [string]$manifest.archiveSha256 -cne $zipHash -or
    [string]$manifest.assemblyInformationalVersion -cne "0.1.0+source.$head") {
    throw 'Blocked: candidate provenance does not match current HEAD.'
}
Import-Module -Name $modulePath -Force
$exports = @(Get-Command -Module Cloudflare.PowerShell -CommandType Cmdlet |
    Select-Object -ExpandProperty Name | Sort-Object)
$expected = @('Get-CfDnsRecord', 'Get-CfZone', 'New-CfDnsRecord',
    'Remove-CfDnsRecord', 'Set-CfDnsRecord')
if (($exports -join '|') -cne ($expected -join '|')) {
    throw 'Blocked: public command surface differs from the approved five.'
}
if ($PreflightOnly) {
    [pscustomobject][ordered]@{
        Status = 'PreflightPassed'
        SourceRevision = $head
        CandidateZipSha256 = $zipHash
        CredentialPresent = $true
        ScopeVariablesPresent = $true
        LiveRequestCount = 0
    } | ConvertTo-Json -Depth 3
    return
}

$accountId = $values['CLOUDFLARE_POWERSHELL_INTEGRATION_ACCOUNT_ID']
$zoneId = $values['CLOUDFLARE_POWERSHELL_INTEGRATION_ZONE_ID']
$token = $values['CLOUDFLARE_POWERSHELL_INTEGRATION_TOKEN']
$escapedAccount = [Uri]::EscapeDataString($accountId)
$escapedZone = [Uri]::EscapeDataString($zoneId)
$nonexistent = [Guid]::NewGuid().ToString('N')
$requests = @(
    [pscustomobject]@{ Label='token-verify'; Path="/accounts/$escapedAccount/tokens/verify"; Expected=200 },
    [pscustomobject]@{ Label='account-get'; Path="/accounts/$escapedAccount"; Expected=200 },
    [pscustomobject]@{ Label='zone-get'; Path="/zones/$escapedZone"; Expected=200 },
    [pscustomobject]@{ Label='dns-page-one'; Path="/zones/$escapedZone/dns_records?page=1&per_page=1"; Expected=200 },
    [pscustomobject]@{ Label='missing-record'; Path="/zones/$escapedZone/dns_records/$nonexistent"; Expected=404 },
    [pscustomobject]@{ Label='dns-export'; Path="/zones/$escapedZone/dns_records/export"; Expected=200 }
)

$handler = [Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $false
$http = [Net.Http.HttpClient]::new($handler)
$http.Timeout = [TimeSpan]::FromSeconds(20)
$http.DefaultRequestHeaders.Authorization =
    [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $token)
$http.DefaultRequestHeaders.Accept.ParseAdd('application/json')
$rows = [Collections.Generic.List[object]]::new()
$sent = 0
$stopReason = ''
$utf8 = [Text.UTF8Encoding]::new($false, $true)
try {
    foreach ($item in $requests) {
        if ($sent -ge 6) { $stopReason = 'request-cap'; break }
        if ($sent -gt 0) { Start-Sleep -Seconds 3 }
        $request = [Net.Http.HttpRequestMessage]::new(
            [Net.Http.HttpMethod]::Get,
            [Uri]::new('https://api.cloudflare.com/client/v4' + $item.Path)
        )
        $response = $null
        $body = $null
        $now = [DateTimeOffset]::UtcNow.ToString('o')
        try {
            $sent++
            $response = $http.SendAsync($request).GetAwaiter().GetResult()
            $body = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            $status = [int]$response.StatusCode
            $contentType = if ($response.Content.Headers.ContentType) {
                [string]$response.Content.Headers.ContentType
            } else { '' }
            $headerNames = @('Ratelimit', 'Ratelimit-Policy', 'Retry-After')
            $headerPresence = [ordered]@{}
            foreach ($name in $headerNames) {
                $allValues = $null
                $headerPresence[$name] = $response.Headers.TryGetValues(
                    $name, [ref]$allValues)
            }
            $json = $null
            if ($item.Label -ne 'dns-export') {
                try { $json = $utf8.GetString($body) | ConvertFrom-Json }
                catch { $json = $null }
            }
            $success = if ($null -ne $json -and
                $null -ne $json.PSObject.Properties['success']) {
                [bool]$json.success
            } else { $null }
            $providerCode = $null
            if ($null -ne $json -and $json.PSObject.Properties['errors']) {
                $firstError = @($json.errors) | Select-Object -First 1
                if ($null -ne $firstError -and
                    $null -ne $firstError.PSObject.Properties['code']) {
                    $providerCode = [string]$firstError.code
                }
            }
            $shapeOk = $true
            if ($item.Label -eq 'token-verify') {
                $shapeOk = ($success -eq $true -and
                    [string]$json.result.status -ceq 'active')
            } elseif ($item.Label -eq 'account-get') {
                $shapeOk = ($success -eq $true -and
                    [string]$json.result.id -ceq $accountId)
            } elseif ($item.Label -eq 'zone-get') {
                $shapeOk = ($success -eq $true -and
                    [string]$json.result.id -ceq $zoneId)
            } elseif ($item.Label -eq 'dns-page-one') {
                $shapeOk = ($success -eq $true -and
                    @($json.result).Count -le 1)
            } elseif ($item.Label -eq 'dns-export') {
                try { $null = $utf8.GetString($body) }
                catch { $shapeOk = $false }
            }
            $rows.Add([pscustomobject][ordered]@{
                Operation = $item.Label
                Utc = $now
                HttpStatus = $status
                Success = $success
                ErrorCategory = if ($status -eq 404) { 'ObjectNotFound' }
                    elseif ($status -ge 400) { 'HttpError' } else { '' }
                ProviderCode = $providerCode
                RateLimitPresent = $headerPresence['Ratelimit']
                RateLimitPolicyPresent = $headerPresence['Ratelimit-Policy']
                RetryAfterPresent = $headerPresence['Retry-After']
                ContentType = if ($item.Label -eq 'dns-export') { $contentType } else { '' }
                ByteCount = $body.Length
                ShapeOk = $shapeOk
            })
            if ($status -ne $item.Expected -or -not $shapeOk) {
                $stopReason = 'unexpected-status-or-shape'
                break
            }
        } catch {
            $stopReason = 'transport-or-parse-failure'
            break
        } finally {
            if ($null -ne $response) { $response.Dispose() }
            $request.Dispose()
        }
    }
} finally {
    $http.Dispose()
    $handler.Dispose()
}
[pscustomobject][ordered]@{
    SourceRevision = $head
    CandidateZipSha256 = $zipHash
    RequestCount = $sent
    Status = if ($stopReason) { 'Stopped' } else { 'CompletedWithinScope' }
    StopReason = $stopReason
    Checks = @($rows.ToArray())
} | ConvertTo-Json -Depth 6
if ($stopReason) { exit 2 }
