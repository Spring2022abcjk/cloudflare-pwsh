[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ReportPath,
    [string]$PolicyPath = (Join-Path $ProjectRoot 'build/p34-compatibility-policy.json'),
    [string]$OutputPath = (Join-Path $ProjectRoot 'artifacts/p34/compatibility-gate.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
function Resolve-P34Path {
    param([Parameter(Mandatory)][string]$Path)
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $root $Path))
}

$policyPath = Resolve-P34Path $PolicyPath
if (-not (Test-Path -LiteralPath $policyPath -PathType Leaf)) { throw "P3.4 compatibility policy is missing: $policyPath" }
$policy = Get-Content -Raw -LiteralPath $policyPath | ConvertFrom-Json
if ([int]$policy.version -ne 1 -or [string]$policy.stage -cne 'P3.4') { throw 'P3.4 compatibility policy version/stage is unsupported.' }

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $manifestPath = Resolve-P34Path 'fixtures/p2.4/openapi-previous-revision.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "P2.4 revision manifest is missing: $manifestPath" }
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    $artifactRoot = Resolve-P34Path 'artifacts/compatibility'
    $candidates = @()
    foreach ($candidate in @(Get-ChildItem -LiteralPath $artifactRoot -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        try { $value = Get-Content -Raw -LiteralPath $candidate.FullName | ConvertFrom-Json } catch { continue }
        if ([string]$value.stage -ceq 'P2.4' -and [string]$value.newSourceRevision -ceq [string]$manifest.currentRevision) { $candidates += $candidate.FullName }
    }
    if ($candidates.Count -ne 1) { throw "Could not resolve exactly one P2.4 compatibility report for revision '$($manifest.currentRevision)'; found $($candidates.Count)." }
    $ReportPath = $candidates[0]
}
$reportPath = Resolve-P34Path $ReportPath
$outputPath = Resolve-P34Path $OutputPath
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw "P2.4 compatibility report is missing: $reportPath" }
$report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
if ([string]$report.stage -cne 'P2.4' -or $null -eq $report.changes -or $null -eq $report.severitySummary) { throw 'P2.4 compatibility report has an unsupported schema.' }

$impactNames = @('None', 'NonBreaking', 'Behavioral', 'PotentiallyBreaking', 'Breaking', 'Unknown')
$identityFields = @('kind', 'resourcePath', 'operationId', 'schemaName', 'path', 'oldValue', 'newValue', 'apiImpact', 'sdkImpact', 'powerShellImpact')
function Get-P34Field {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) { return '' }
    return [string]$Object.PSObject.Properties[$Name].Value
}
function Get-P34ChangeKey {
    param([Parameter(Mandatory)]$Change)
    return (($identityFields | ForEach-Object { "$_=$(Get-P34Field $Change $_)" }) -join '|')
}
function Test-P34ApprovedChange {
    param([Parameter(Mandatory)]$Change, [Parameter(Mandatory)]$Approval)
    foreach ($field in @('kind', 'path', 'oldValue', 'newValue', 'apiImpact', 'sdkImpact', 'powerShellImpact')) {
        if ((Get-P34Field $Change $field) -cne (Get-P34Field $Approval $field)) { return $false }
    }
    foreach ($field in @('resourcePath', 'operationId', 'schemaName')) {
        if ($null -ne $Approval.PSObject.Properties[$field] -and (Get-P34Field $Change $field) -cne (Get-P34Field $Approval $field)) { return $false }
    }
    return $true
}

$approvals = @($policy.approvedChanges)
$approvalKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($approval in $approvals) {
    foreach ($field in @('kind', 'path', 'oldValue', 'newValue', 'apiImpact', 'sdkImpact', 'powerShellImpact')) {
        if ([string]::IsNullOrWhiteSpace((Get-P34Field $approval $field))) { throw "Compatibility allowlist entry is missing '$field'." }
    }
    $key = Get-P34ChangeKey $approval
    if (-not $approvalKeys.Add($key)) { throw "Compatibility allowlist contains a duplicate entry: $key" }
}

$approved = [Collections.Generic.List[string]]::new()
$violations = [Collections.Generic.List[object]]::new()
$seenApprovalKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($change in @($report.changes)) {
    foreach ($field in @('kind', 'path', 'oldValue', 'newValue', 'apiImpact', 'sdkImpact', 'powerShellImpact')) {
        if ([string]::IsNullOrWhiteSpace((Get-P34Field $change $field))) { throw "Compatibility change is missing '$field'." }
    }
    foreach ($field in @('apiImpact', 'sdkImpact', 'powerShellImpact')) {
        if ($impactNames -notcontains (Get-P34Field $change $field)) { throw "Compatibility change has an invalid $field value." }
    }
    $key = Get-P34ChangeKey $change
    $approval = @($approvals | Where-Object { Test-P34ApprovedChange $change $_ })
    if ($approval.Count -gt 1) { throw "Compatibility allowlist is ambiguous for change: $key" }
    $isApproved = $approval.Count -eq 1
    if ($isApproved) {
        [void]$seenApprovalKeys.Add($key)
        $approved.Add($key)
    }
    $impacts = @((Get-P34Field $change 'apiImpact'), (Get-P34Field $change 'sdkImpact'), (Get-P34Field $change 'powerShellImpact'))
    if ($impacts -contains 'Unknown') {
        $violations.Add([pscustomobject]@{ category = 'UnknownImpact'; key = $key; path = Get-P34Field $change 'path' })
    } elseif (-not $isApproved -and $impacts -contains 'Breaking') {
        $violations.Add([pscustomobject]@{ category = 'UnexpectedBreaking'; key = $key; path = Get-P34Field $change 'path' })
    } elseif (-not $isApproved -and $impacts -contains 'PotentiallyBreaking') {
        $violations.Add([pscustomobject]@{ category = 'ManualReviewRequired'; key = $key; path = Get-P34Field $change 'path' })
    }
}

$unusedApprovals = @($approvalKeys | Where-Object { -not $seenApprovalKeys.Contains($_) } | Sort-Object)
foreach ($key in $unusedApprovals) { $violations.Add([pscustomobject]@{ category = 'UnusedAllowlistEntry'; key = $key; path = '' }) }
$approved = @($approved | Sort-Object)
$violations = @($violations | Sort-Object category, key)
$summary = [ordered]@{
    schemaVersion = 1
    stage = 'P3.4'
    status = if ($violations.Count -eq 0) { 'Passed' } else { 'Failed' }
    reportPath = [IO.Path]::GetRelativePath($root, $reportPath).Replace('\', '/')
    policyPath = [IO.Path]::GetRelativePath($root, $policyPath).Replace('\', '/')
    changeCount = @($report.changes).Count
    approvedChangeCount = $approved.Count
    approvedChanges = $approved
    violations = $violations
    policy = [ordered]@{
        unknownImpact = [string]$policy.rules.unknownImpact
        unexpectedBreaking = [string]$policy.rules.unexpectedBreaking
        unexpectedPotentiallyBreaking = [string]$policy.rules.unexpectedPotentiallyBreaking
    }
}
$outputDirectory = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$json = $summary | ConvertTo-Json -Depth 20
$normalized = $json.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
[IO.File]::WriteAllText($outputPath, $normalized, [Text.UTF8Encoding]::new($false))
if ($violations.Count -ne 0) { throw "P3.4 compatibility gate failed with $($violations.Count) violation(s); see $outputPath." }
Write-Output "PASS P3.4 compatibility gate changes=$(@($report.changes).Count) approved=$($approved.Count) -> $outputPath"
