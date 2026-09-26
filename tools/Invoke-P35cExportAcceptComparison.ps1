[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CandidateRoot,
    [switch]$Approved,
    [switch]$PreflightOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $Approved) { throw 'Blocked: export Accept comparison requires specific approval.' }

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

$candidate = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $CandidateRoot).Path)
$manifestPath = Join-Path $candidate 'candidate-manifest.json'
$zipPath = Join-Path $candidate 'Cloudflare.PowerShell.0.1.0.zip'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
    throw 'Blocked: candidate package is incomplete.'
}
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$head = ((& git rev-parse HEAD) -join "`n").Trim()
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ([string]$manifest.sourceRevision -cne $head -or
    [string]$manifest.archiveSha256 -cne $zipHash) {
    throw 'Blocked: candidate provenance does not match current HEAD.'
}
if ($PreflightOnly) {
    [pscustomobject][ordered]@{
        Status = 'PreflightPassed'
        SourceRevision = $head
        CandidateZipSha256 = $zipHash
        LiveRequestCount = 0
    } | ConvertTo-Json -Depth 3
    return
}

$zoneId = [Uri]::EscapeDataString(
    $values['CLOUDFLARE_POWERSHELL_INTEGRATION_ZONE_ID'])
$uri = [Uri]::new(
    "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records/export")
$token = $values['CLOUDFLARE_POWERSHELL_INTEGRATION_TOKEN']
$handler = [Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $false
$http = [Net.Http.HttpClient]::new($handler)
$http.Timeout = [TimeSpan]::FromSeconds(20)
$http.DefaultRequestHeaders.Authorization =
    [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $token)
$strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
$rows = [Collections.Generic.List[object]]::new()
$sent = 0
$stopReason = ''
try {
    foreach ($accept in @('text/plain', 'application/json')) {
        if ($sent -ge 2) { $stopReason = 'request-cap'; break }
        if ($sent -gt 0) { Start-Sleep -Seconds 3 }
        $request = [Net.Http.HttpRequestMessage]::new(
            [Net.Http.HttpMethod]::Get, $uri)
        $request.Headers.Accept.ParseAdd($accept)
        $response = $null
        try {
            $sent++
            $response = $http.SendAsync($request).GetAwaiter().GetResult()
            $body = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            $status = [int]$response.StatusCode
            $contentType = if ($response.Content.Headers.ContentType) {
                [string]$response.Content.Headers.ContentType
            } else { '' }
            $utf8Valid = $false
            $hasOrigin = $false
            $hasSoa = $false
            try {
                $content = $strictUtf8.GetString($body)
                $utf8Valid = $true
                $hasOrigin = $content -match '(?m)^\$ORIGIN\b'
                $hasSoa = $content -match '(?m)^\S+\s+\d+\s+IN\s+SOA\s+'
            } catch {
                # Preserve only the boolean shape result.
            }
            $rows.Add([pscustomobject][ordered]@{
                Accept = $accept
                Utc = [DateTimeOffset]::UtcNow.ToString('o')
                HttpStatus = $status
                ContentType = $contentType
                ByteCount = $body.Length
                Utf8Valid = $utf8Valid
                HasOriginDirective = $hasOrigin
                HasSoaRecord = $hasSoa
            })
            if ($status -ne 200 -or -not $utf8Valid) {
                $stopReason = 'unexpected-status-or-shape'
                break
            }
        } catch {
            $stopReason = 'transport-failure'
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
} | ConvertTo-Json -Depth 5
if ($stopReason) { exit 2 }
