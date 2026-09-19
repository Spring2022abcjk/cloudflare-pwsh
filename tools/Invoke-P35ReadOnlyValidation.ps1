[CmdletBinding()]
param(
    [string]$BaseUrl = 'https://api.cloudflare.com/client/v4/',
    [string]$CandidateModulePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$credentialName = 'CLOUDFLARE_POWERSHELL_INTEGRATION_TOKEN'
$accountScopeName = 'CLOUDFLARE_POWERSHELL_INTEGRATION_ACCOUNT_ID'
$zoneScopeName = 'CLOUDFLARE_POWERSHELL_INTEGRATION_ZONE_ID'
$token = [Environment]::GetEnvironmentVariable($credentialName)
$accountId = [Environment]::GetEnvironmentVariable($accountScopeName)
$zoneId = [Environment]::GetEnvironmentVariable($zoneScopeName)
$baseUri = $BaseUrl.TrimEnd('/')
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$liveRequestCount = 0

function Get-P35HeaderValue {
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

function Get-P35JsonSummary {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Body
    )

    $summary = [ordered]@{
        Success = $null
        PageResultCount = $null
        TotalCount = $null
        ErrorCodes = @()
    }

    try {
        $json = [Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
        if ($null -ne $json.PSObject.Properties['success']) {
            $summary.Success = [bool]$json.success
        }
        if ($null -ne $json.PSObject.Properties['result']) {
            if ($json.result -is [Array]) {
                $summary.PageResultCount = @($json.result).Count
            }
        }
        if ($null -ne $json.PSObject.Properties['result_info'] -and
            $null -ne $json.result_info.PSObject.Properties['total_count']) {
            $summary.TotalCount = [int]$json.result_info.total_count
        }
        if ($null -ne $json.PSObject.Properties['errors']) {
            $summary.ErrorCodes = @($json.errors | ForEach-Object {
                if ($null -ne $_.PSObject.Properties['code']) { [int]$_.code }
            } | Sort-Object -Unique)
        }
    } catch {
        # The body is deliberately not retained or reported when it is not JSON.
    }

    return [pscustomobject]$summary
}

function Get-P35ExportSummary {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Body
    )

    $summary = [ordered]@{
        Utf8Valid = $false
        RecordLikeLineCount = 0
        HasOriginDirective = $false
        HasTtlDirective = $false
        HasSoaRecord = $false
    }

    try {
        $utf8 = [Text.UTF8Encoding]::new($false, $true)
        $text = $utf8.GetString($Body)
        $summary.Utf8Valid = $true
        $summary.RecordLikeLineCount = [regex]::Matches(
            $text,
            '(?im)^\s*[^;\s]+\s+\d+\s+IN\s+(A|AAAA|CAA|CNAME|HTTPS|MX|NAPTR|NS|PTR|SRV|SVCB|TXT)\b'
        ).Count
        $summary.HasOriginDirective = $text -match '(?im)^\s*\$ORIGIN\s+'
        $summary.HasTtlDirective = $text -match '(?im)^\s*\$TTL\s+'
        $summary.HasSoaRecord = $text -match '(?im)\bIN\s+SOA\b'
    } catch {
        # The body is deliberately not retained or reported when it is not valid UTF-8.
    }

    return [pscustomobject]$summary
}

function Get-P35SafeErrorMetadata {
    param(
        [Parameter(Mandatory = $true)][System.Management.Automation.ErrorRecord]$ErrorRecord,
        [Parameter(Mandatory = $true)][string]$TargetKind
    )

    $exception = $ErrorRecord.Exception
    $status = $null
    foreach ($candidate in @($exception, $exception.InnerException)) {
        if ($null -ne $candidate -and $null -ne $candidate.PSObject.Properties['StatusCode']) {
            try { $status = [int]$candidate.StatusCode } catch { }
            if ($null -ne $status) { break }
        }
    }

    $providerCodes = @()
    foreach ($candidate in @($exception, $exception.InnerException)) {
        if ($null -eq $candidate) { continue }
        foreach ($propertyName in @('ErrorCode', 'CloudflareErrorCode')) {
            if ($null -ne $candidate.PSObject.Properties[$propertyName]) {
                try { $providerCodes += [int]$candidate.$propertyName } catch { }
            }
        }
    }

    [pscustomobject][ordered]@{
        HttpStatus = $status
        ErrorId = [string]$ErrorRecord.FullyQualifiedErrorId
        Category = [string]$ErrorRecord.CategoryInfo.Category
        ExceptionType = $exception.GetType().FullName
        TargetKind = $TargetKind
        ProviderErrorCodes = @($providerCodes | Sort-Object -Unique)
    }
}

function Invoke-P35ReadOnlyHttpGet {
    param(
        [Parameter(Mandatory = $true)][string]$Check,
        [Parameter(Mandatory = $true)][string]$PathTemplate,
        [Parameter(Mandatory = $true)][string]$RequestPath,
        [Parameter(Mandatory = $true)][ValidateSet('Bearer', 'Missing', 'Wrong')][string]$AuthMode,
        [switch]$InspectExport
    )

    $row = [ordered]@{
        Check = $Check
        Path = $PathTemplate
        AuthMode = $AuthMode
        HttpStatus = $null
        CloudflareSuccess = $null
        PageResultCount = $null
        TotalCount = $null
        ContentType = ''
        ContentLength = $null
        BodyByteLength = $null
        Utf8Valid = $null
        RecordLikeLineCount = $null
        HasOriginDirective = $null
        HasTtlDirective = $null
        HasSoaRecord = $null
        ErrorCodes = @()
        ErrorId = ''
        ExceptionType = ''
        RateLimit = ''
        RateLimitPolicy = ''
        RetryAfter = ''
        ElapsedMilliseconds = $null
    }

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $client = [Net.Http.HttpClient]::new()
    $request = [Net.Http.HttpRequestMessage]::new(
        [Net.Http.HttpMethod]::Get,
        [Uri]::new($baseUri + $RequestPath)
    )
    try {
        if ($AuthMode -eq 'Bearer') {
            $request.Headers.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $token)
        } elseif ($AuthMode -eq 'Wrong') {
            $request.Headers.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', 'p35a-invalid-credential')
        }

        $script:liveRequestCount++
        $response = $client.SendAsync(
            $request,
            [Net.Http.HttpCompletionOption]::ResponseHeadersRead
        ).GetAwaiter().GetResult()
        $body = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        $row.HttpStatus = [int]$response.StatusCode
        $row.ContentType = Get-P35HeaderValue -Headers $response.Content.Headers -Name 'Content-Type'
        $row.ContentLength = $response.Content.Headers.ContentLength
        $row.BodyByteLength = $body.Length
        $row.RateLimit = Get-P35HeaderValue -Headers $response.Headers -Name 'Ratelimit'
        $row.RateLimitPolicy = Get-P35HeaderValue -Headers $response.Headers -Name 'Ratelimit-Policy'
        $row.RetryAfter = Get-P35HeaderValue -Headers $response.Headers -Name 'Retry-After'

        $json = Get-P35JsonSummary -Body $body
        $row.CloudflareSuccess = $json.Success
        $row.PageResultCount = $json.PageResultCount
        $row.TotalCount = $json.TotalCount
        $row.ErrorCodes = @($json.ErrorCodes)

        if ($InspectExport) {
            $export = Get-P35ExportSummary -Body $body
            $row.Utf8Valid = $export.Utf8Valid
            $row.RecordLikeLineCount = $export.RecordLikeLineCount
            $row.HasOriginDirective = $export.HasOriginDirective
            $row.HasTtlDirective = $export.HasTtlDirective
            $row.HasSoaRecord = $export.HasSoaRecord
        }
    } catch {
        $row.ExceptionType = $_.Exception.GetType().FullName
        $response = $null
        if ($null -ne $_.Exception.PSObject.Properties['Response']) {
            $response = $_.Exception.Response
        }
        if ($null -ne $response) {
            try { $row.HttpStatus = [int]$response.StatusCode } catch { }
            $row.RateLimit = Get-P35HeaderValue -Headers $response.Headers -Name 'Ratelimit'
            $row.RateLimitPolicy = Get-P35HeaderValue -Headers $response.Headers -Name 'Ratelimit-Policy'
            $row.RetryAfter = Get-P35HeaderValue -Headers $response.Headers -Name 'Retry-After'
        }
    } finally {
        $stopwatch.Stop()
        $row.ElapsedMilliseconds = $stopwatch.ElapsedMilliseconds
        $request.Dispose()
        $client.Dispose()
    }

    return [pscustomobject]$row
}

function Get-P35PropertyValue {
    param(
        [Parameter(Mandatory = $true)][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $InputObject -or $null -eq $InputObject.PSObject.Properties[$Name]) {
        return $null
    }

    return $InputObject.PSObject.Properties[$Name].Value
}

function Test-P35Candidate {
    param(
        [Parameter(Mandatory = $true)][string]$ModulePath
    )

    $result = [ordered]@{
        Status = 'Blocked'
        ModulePathProvided = $true
        CandidateManifestPresent = $false
        SourceRevisionMatchesHead = $false
        PublicCmdletPresent = $false
        HelpDiscovered = $false
        AssemblyProvenancePresent = $false
        SourceRevision = ''
        Reason = ''
    }

    try {
        $resolvedModulePath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ModulePath).Path)
        $moduleManifestPath = Join-Path $resolvedModulePath 'Cloudflare.PowerShell.psd1'
        $candidateRoot = Split-Path -Parent (Split-Path -Parent $resolvedModulePath)
        $candidateManifestPath = Join-Path $candidateRoot 'candidate-manifest.json'
        if (-not (Test-Path -LiteralPath $candidateManifestPath -PathType Leaf)) {
            $result.Reason = 'candidate-manifest-missing'
            return [pscustomobject]$result
        }
        $result.CandidateManifestPresent = $true
        $manifest = Get-Content -Raw -LiteralPath $candidateManifestPath | ConvertFrom-Json
        $head = ((& git -C $repoRoot rev-parse HEAD 2>$null) -join "`n").Trim()
        $result.SourceRevision = [string]$manifest.sourceRevision
        $result.SourceRevisionMatchesHead = ([string]$manifest.sourceRevision -ceq $head)
        $result.AssemblyProvenancePresent = (-not [string]::IsNullOrWhiteSpace([string]$manifest.assemblyInformationalVersion))
        if (-not $result.SourceRevisionMatchesHead) {
            $result.Reason = 'candidate-source-revision-does-not-match-head'
            return [pscustomobject]$result
        }
        if (-not (Test-Path -LiteralPath $moduleManifestPath -PathType Leaf)) {
            $result.Reason = 'candidate-module-manifest-missing'
            return [pscustomobject]$result
        }

        Import-Module -Name $moduleManifestPath -Force
        $loaded = Get-Module -Name 'Cloudflare.PowerShell' | Where-Object {
            [IO.Path]::GetFullPath($_.ModuleBase) -ceq $resolvedModulePath
        } | Select-Object -First 1
        if ($null -eq $loaded) {
            $result.Reason = 'candidate-module-not-loaded-from-requested-path'
            return [pscustomobject]$result
        }
        $command = Get-Command -Name 'Get-CfDnsRecord' -Module $loaded.Name -ErrorAction Stop
        $result.PublicCmdletPresent = ($command.CommandType -eq 'Cmdlet')
        $help = Get-Help -Name 'Get-CfDnsRecord' -ErrorAction Stop
        $result.HelpDiscovered = (-not [string]::IsNullOrWhiteSpace([string]$help.Synopsis) -or
            -not [string]::IsNullOrWhiteSpace([string]$help.Description))
        if (-not $result.PublicCmdletPresent -or -not $result.HelpDiscovered -or -not $result.AssemblyProvenancePresent) {
            $result.Reason = 'candidate-contract-check-failed'
            return [pscustomobject]$result
        }

        $result.Status = 'Ready'
        return [pscustomobject]$result
    } catch {
        $result.Reason = 'candidate-validation-failed'
        return [pscustomobject]$result
    }
}

function Get-P35StageStatus {
    param(
        [Parameter(Mandatory = $true)][object[]]$Checks,
        [Parameter(Mandatory = $true)][object]$Candidate,
        [Parameter(Mandatory = $true)][bool]$CandidateListSuccess,
        [Parameter(Mandatory = $true)][bool]$CandidateGetSuccess
    )

    if ($Candidate.Status -ne 'Ready') { return 'Blocked' }
    $accountVerify = @($Checks | Where-Object { $_.Check -ceq 'account-token-verify' } | Select-Object -First 1)
    $accountGet = @($Checks | Where-Object { $_.Check -ceq 'account-get' } | Select-Object -First 1)
    $zoneGet = @($Checks | Where-Object { $_.Check -ceq 'zone-get' } | Select-Object -First 1)
    $dnsExport = @($Checks | Where-Object { $_.Check -ceq 'dns-export' } | Select-Object -First 1)
    $wrongAuth = @($Checks | Where-Object { $_.Check -ceq 'wrong-auth' } | Select-Object -First 1)
    $missingAuth = @($Checks | Where-Object { $_.Check -ceq 'missing-auth' } | Select-Object -First 1)
    $required = @(
        ($null -ne $accountVerify -and $accountVerify.CloudflareSuccess -eq $true),
        ($null -ne $accountGet -and $accountGet.CloudflareSuccess -eq $true),
        ($null -ne $zoneGet -and $zoneGet.CloudflareSuccess -eq $true),
        $CandidateListSuccess,
        $CandidateGetSuccess,
        ($null -ne $dnsExport -and $dnsExport.HttpStatus -eq 200),
        ($null -ne $wrongAuth -and [int]$wrongAuth.HttpStatus -in @(400, 401, 403)),
        ($null -ne $missingAuth -and [int]$missingAuth.HttpStatus -in @(400, 401, 403))
    )
    if (@($required | Where-Object { -not $_ }).Count -eq 0) { return 'Complete' }
    return 'Partial'
}

$candidate = if ([string]::IsNullOrWhiteSpace($CandidateModulePath)) {
    [pscustomobject][ordered]@{
        Status = 'Blocked'
        ModulePathProvided = $false
        CandidateManifestPresent = $false
        SourceRevisionMatchesHead = $false
        PublicCmdletPresent = $false
        HelpDiscovered = $false
        AssemblyProvenancePresent = $false
        SourceRevision = ''
        Reason = 'candidate-module-path-required'
    }
} else {
    Test-P35Candidate -ModulePath $CandidateModulePath
}

$missing = @()
if ([string]::IsNullOrWhiteSpace($token)) { $missing += $credentialName }
if ([string]::IsNullOrWhiteSpace($accountId)) { $missing += $accountScopeName }
if ([string]::IsNullOrWhiteSpace($zoneId)) { $missing += $zoneScopeName }

$output = [ordered]@{
    Stage = 'P3.5a'
    Status = 'Blocked'
    TokenKind = 'Account API Token'
    CredentialEnvironmentVariable = $credentialName
    ScopeSelection = 'explicit environment variables only'
    MissingConfiguration = @($missing)
    Candidate = $candidate
    LiveRequestCount = 0
    Checks = @()
    CandidateList = $null
    CandidateGet = $null
    Pagination = [ordered]@{
        Status = 'not-observed'
        RequestedPerPage = 5
        DirectPagesRequested = 0
        AggregateCount = $null
        DirectTotalCount = $null
        UniqueIdCount = $null
        DuplicateIds = $null
    }
    ErrorObservation = [ordered]@{
        InvalidDnsRecordGet = 'not-observed'
        ScopeMismatch = 'not-observed-no-second-approved-scope'
    }
    Findings = @()
}

if ($missing.Count -ne 0 -or $candidate.Status -ne 'Ready') {
    if ($missing.Count -eq 0 -and $candidate.Status -ne 'Ready') {
        $output.MissingConfiguration = @('candidate-module-path-or-provenance')
    }
    $output.LiveRequestCount = $liveRequestCount
    $output | ConvertTo-Json -Depth 12
    exit 2
}

$checks = [Collections.Generic.List[object]]::new()
$checks.Add((Invoke-P35ReadOnlyHttpGet -Check 'account-token-verify' -PathTemplate '/accounts/{account_id}/tokens/verify' -RequestPath ("/accounts/{0}/tokens/verify" -f [Uri]::EscapeDataString($accountId)) -AuthMode Bearer))
$checks.Add((Invoke-P35ReadOnlyHttpGet -Check 'account-get' -PathTemplate '/accounts/{account_id}' -RequestPath ("/accounts/{0}" -f [Uri]::EscapeDataString($accountId)) -AuthMode Bearer))
$checks.Add((Invoke-P35ReadOnlyHttpGet -Check 'zone-get' -PathTemplate '/zones/{zone_id}' -RequestPath ("/zones/{0}" -f [Uri]::EscapeDataString($zoneId)) -AuthMode Bearer))
$checks.Add((Invoke-P35ReadOnlyHttpGet -Check 'zone-list-for-account' -PathTemplate '/zones?account.id={account_id}&per_page=5' -RequestPath ("/zones?account.id={0}&per_page=5" -f [Uri]::EscapeDataString($accountId)) -AuthMode Bearer))
$checks.Add((Invoke-P35ReadOnlyHttpGet -Check 'wrong-auth' -PathTemplate '/zones/{zone_id}' -RequestPath ("/zones/{0}" -f [Uri]::EscapeDataString($zoneId)) -AuthMode Wrong))
$checks.Add((Invoke-P35ReadOnlyHttpGet -Check 'missing-auth' -PathTemplate '/zones/{zone_id}' -RequestPath ("/zones/{0}" -f [Uri]::EscapeDataString($zoneId)) -AuthMode Missing))
$checks.Add((Invoke-P35ReadOnlyHttpGet -Check 'dns-list-page-1' -PathTemplate '/zones/{zone_id}/dns_records?page=1&per_page=5' -RequestPath ("/zones/{0}/dns_records?page=1&per_page=5" -f [Uri]::EscapeDataString($zoneId)) -AuthMode Bearer))
$checks.Add((Invoke-P35ReadOnlyHttpGet -Check 'dns-list-page-2' -PathTemplate '/zones/{zone_id}/dns_records?page=2&per_page=5' -RequestPath ("/zones/{0}/dns_records?page=2&per_page=5" -f [Uri]::EscapeDataString($zoneId)) -AuthMode Bearer))
$checks.Add((Invoke-P35ReadOnlyHttpGet -Check 'dns-export' -PathTemplate '/zones/{zone_id}/dns_records/export' -RequestPath ("/zones/{0}/dns_records/export" -f [Uri]::EscapeDataString($zoneId)) -AuthMode Bearer -InspectExport))

$candidateListSuccess = $false
$candidateGetSuccess = $false
$candidateList = $null
$candidateGet = $null
$candidateRecordIds = @()
try {
    $script:liveRequestCount++
    $records = @(Get-CfDnsRecord -ZoneId $zoneId -PerPage 5 -Page 1 -BaseUrl $BaseUrl -Token $token -ErrorAction Stop)
    $candidateRecordIds = @($records | ForEach-Object {
        $value = Get-P35PropertyValue -InputObject $_ -Name 'Id'
        if ($null -ne $value) { [string]$value }
    })
    $uniqueIds = @($candidateRecordIds | Sort-Object -Unique)
    $candidateListSuccess = $true
    $candidateList = [pscustomobject][ordered]@{
        Success = $true
        TypedOutput = (@($records | Where-Object { $_.GetType().FullName -like '*CfDnsRecord' }).Count -eq $records.Count)
        RecordCount = $records.Count
        UniqueIdCount = $uniqueIds.Count
        DuplicateIds = ($uniqueIds.Count -ne $candidateRecordIds.Count)
    }
    if ($candidateRecordIds.Count -gt 0) {
        $selectedId = $candidateRecordIds[0]
        try {
            $script:liveRequestCount++
            $got = @(Get-CfDnsRecord -ZoneId $zoneId -DnsRecordId $selectedId -BaseUrl $BaseUrl -Token $token -ErrorAction Stop)
            $candidateGetSuccess = ($got.Count -eq 1 -and [string](Get-P35PropertyValue -InputObject $got[0] -Name 'Id') -ceq $selectedId)
            $candidateGet = [pscustomobject][ordered]@{
                Success = $candidateGetSuccess
                TypedOutput = ($got.Count -eq 1 -and $got[0].GetType().FullName -like '*CfDnsRecord')
                ReturnedCount = $got.Count
                IdMatch = $candidateGetSuccess
            }
        } catch {
            $candidateGet = [pscustomobject][ordered]@{
                Success = $false
                Error = Get-P35SafeErrorMetadata -ErrorRecord $_ -TargetKind 'dns-record-get'
            }
        }
    } else {
        $candidateGet = [pscustomobject][ordered]@{
            Success = $null
            Status = 'insufficient-live-data-no-record-id'
        }
        $candidateGetSuccess = $false
    }
} catch {
    $candidateList = [pscustomobject][ordered]@{
        Success = $false
        Error = Get-P35SafeErrorMetadata -ErrorRecord $_ -TargetKind 'dns-record-list'
    }
}

$invalidId = [Guid]::NewGuid().ToString('N')
$invalidError = $null
try {
    $script:liveRequestCount++
    $null = @(Get-CfDnsRecord -ZoneId $zoneId -DnsRecordId $invalidId -BaseUrl $BaseUrl -Token $token -ErrorAction Stop)
    $invalidError = [pscustomobject][ordered]@{
        Status = 'unexpected-success'
        Error = $null
    }
} catch {
    $invalidError = [pscustomobject][ordered]@{
        Status = 'observed'
        Error = Get-P35SafeErrorMetadata -ErrorRecord $_ -TargetKind 'invalid-dns-record-get'
    }
}

$pageOne = @($checks | Where-Object Check -eq 'dns-list-page-1' | Select-Object -First 1)
$pageTwo = @($checks | Where-Object Check -eq 'dns-list-page-2' | Select-Object -First 1)
$directTotalRow = @($pageOne, $pageTwo) |
    Where-Object { $null -ne $_ -and $null -ne $_.TotalCount } |
    Select-Object -First 1
$directTotal = if ($null -ne $directTotalRow) { $directTotalRow.TotalCount } else { $null }
$candidateCount = if ($null -ne $candidateList) {
    Get-P35PropertyValue -InputObject $candidateList -Name 'RecordCount'
} else {
    $null
}
$candidateDuplicateIds = if ($null -ne $candidateList) {
    Get-P35PropertyValue -InputObject $candidateList -Name 'DuplicateIds'
} else {
    $null
}
$paginationStatus = if ($candidateListSuccess -and $null -ne $directTotal -and $candidateCount -eq [int]$directTotal -and -not $candidateDuplicateIds) {
    'observed-basic-aggregate-and-unique-id-parity'
} else {
    'insufficient-live-evidence'
}

$exportCheck = @($checks | Where-Object Check -eq 'dns-export' | Select-Object -First 1)
$findings = [Collections.Generic.List[object]]::new()
if ($null -ne $exportCheck -and -not [string]::IsNullOrWhiteSpace($exportCheck.ContentType) -and
    $exportCheck.ContentType -notmatch '(?i)^text/plain(?:;|$)') {
    $findings.Add([pscustomobject][ordered]@{
        Finding = 'dns-export-live-media-type-diff'
        ExpectedPinnedMediaType = 'text/plain'
        ObservedMediaType = $exportCheck.ContentType
        Classification = 'E-still-insufficient-evidence'
    })
}

$output.Checks = @($checks)
$output.CandidateList = $candidateList
$output.CandidateGet = $candidateGet
$output.Pagination = [ordered]@{
    Status = $paginationStatus
    RequestedPerPage = 5
    DirectPagesRequested = 2
    AggregateCount = $candidateCount
    DirectTotalCount = $directTotal
    UniqueIdCount = if ($null -ne $candidateList) {
        Get-P35PropertyValue -InputObject $candidateList -Name 'UniqueIdCount'
    } else {
        $null
    }
    DuplicateIds = $candidateDuplicateIds
}
$output.ErrorObservation = [ordered]@{
    InvalidDnsRecordGet = $invalidError
    ScopeMismatch = 'not-observed-no-second-approved-scope'
}
$output.Findings = @($findings)
$output.LiveRequestCount = $liveRequestCount
$output.Status = Get-P35StageStatus -Checks @($checks) -Candidate $candidate -CandidateListSuccess $candidateListSuccess -CandidateGetSuccess $candidateGetSuccess
$output | ConvertTo-Json -Depth 16

if ($output.Status -eq 'Blocked') { exit 2 }
if ($output.Status -eq 'Partial') { exit 3 }
