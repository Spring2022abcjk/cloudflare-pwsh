[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ReportPath = (Join-Path $ProjectRoot 'artifacts/p3.3/coverage-baseline.json'),
    [switch]$VerifyDeterminism
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) { throw "Coverage report is missing: $ReportPath" }
$report = Get-Content -Raw -LiteralPath $ReportPath | ConvertFrom-Json
$allowed = @('Supported', 'SupportedWithOverride', 'UnsupportedRuntimeCapability', 'UnsupportedProjectionCapability', 'UnsupportedNormalizationCapability', 'AmbiguousSemantics', 'ExcludedByPolicy', 'NeedsManualReview')
$rows = @($report.operations)

Assert-True ($report.schemaVersion -eq 1) 'unexpected coverage report schema version'
Assert-True ($report.stage -eq 'P3.3') 'unexpected coverage report stage'
Assert-True ($report.deterministic -eq $true) 'coverage report is not marked deterministic'
Assert-True ($null -eq $report.generatedAt) 'coverage report contains a wall-clock timestamp'
Assert-True ($rows.Count -eq [int]$report.totalOperations) 'operation count does not match report total'
Assert-True (@($rows.operationKey | Sort-Object -Unique).Count -eq $rows.Count) 'operation keys are not unique'
Assert-True (@($rows | Where-Object { $_.classification -notin $allowed }).Count -eq 0) 'report contains an unknown classification'
Assert-True (@($rows | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.resourceFamily) -or [string]::IsNullOrWhiteSpace([string]$_.operationId) }).Count -eq 0) 'report contains an incomplete operation row'

$classificationSum = @($report.classificationCounts.PSObject.Properties | Measure-Object -Property Value -Sum).Sum
Assert-True ([int]$classificationSum -eq $rows.Count) 'classification counts do not reconcile to total operations'
$familySum = @($report.resourceFamilyCounts | Measure-Object -Property totalOperations -Sum).Sum
Assert-True ([int]$familySum -eq $rows.Count) 'resource-family counts do not reconcile to total operations'
Assert-True ((@($rows | Where-Object normalizedStatus -eq 'Succeeded').Count) -eq [int]$report.stageCounts.normalizedSucceeded) 'normalization stage count does not reconcile'
Assert-True ((@($rows | Where-Object runtimeStatus -eq 'Ready').Count) -eq [int]$report.stageCounts.runtimeReady) 'runtime stage count does not reconcile'
Assert-True ((@($rows | Where-Object currentPublicSurface).Count) -eq [int]$report.stageCounts.currentPublicSurface) 'public-surface count does not reconcile'
Assert-True ($null -ne $report.inputIdentity -and $null -ne $report.inputIdentity.source -and -not [string]::IsNullOrWhiteSpace([string]$report.inputIdentity.source.sha256)) 'coverage report is missing deterministic input identity'
Assert-True ([string]$report.sourceRevision -ceq [string]$report.inputIdentity.source.revision) 'coverage source revision does not match input identity'
Assert-True ([int]$report.countSemantics.normalizedSchemaCount -eq [int]$report.normalizedSchemaCount) 'normalized schema count semantics do not reconcile'
Assert-True ([int]$report.countSemantics.runtimeReadyStageCount -eq [int]$report.stageCounts.runtimeReady) 'runtime-ready stage count semantics do not reconcile'
Assert-True ([int]$report.countSemantics.finalUnsupportedRuntimeCapabilityCount -eq [int]$report.classificationCounts.UnsupportedRuntimeCapability) 'final UnsupportedRuntimeCapability count semantics do not reconcile'

Write-Output "PASS P3.3 coverage schema and count reconciliation operations=$($rows.Count)"

function Assert-CoverageFreshness {
    param(
        [Parameter(Mandatory)][string]$FreshJsonPath,
        [Parameter(Mandatory)][string]$FreshMarkdownPath,
        [Parameter(Mandatory)][string]$BaselineJsonPath,
        [Parameter(Mandatory)][string]$BaselineMarkdownPath
    )
    foreach ($path in @($FreshJsonPath, $FreshMarkdownPath, $BaselineJsonPath, $BaselineMarkdownPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "coverage freshness input is missing: $path" }
    }
    $freshHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $FreshJsonPath).Hash
    $baselineHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $BaselineJsonPath).Hash
    if ($freshHash -cne $baselineHash) { throw 'fresh coverage JSON does not match artifacts/p3.3/coverage-baseline.json.' }
    $freshMarkdownHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $FreshMarkdownPath).Hash
    $baselineMarkdownHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $BaselineMarkdownPath).Hash
    if ($freshMarkdownHash -cne $baselineMarkdownHash) { throw 'fresh coverage Markdown does not match artifacts/p3.3/coverage-baseline.md.' }

    $fresh = Get-Content -Raw -LiteralPath $FreshJsonPath | ConvertFrom-Json
    $baseline = Get-Content -Raw -LiteralPath $BaselineJsonPath | ConvertFrom-Json
    foreach ($field in @('sourcePath', 'sourceRevision', 'normalizedSchemaCount', 'totalOperations')) {
        if ([string]$fresh.$field -cne [string]$baseline.$field) { throw "fresh coverage $field does not match the checked-in baseline." }
    }
    foreach ($field in @('normalizedSchemaCount', 'runtimeReadyStageCount', 'finalUnsupportedRuntimeCapabilityCount')) {
        if ([string]$fresh.countSemantics.$field -cne [string]$baseline.countSemantics.$field) { throw "fresh coverage countSemantics.$field does not match the checked-in baseline." }
    }
    $freshIdentity = $fresh.inputIdentity | ConvertTo-Json -Depth 20 -Compress
    $baselineIdentity = $baseline.inputIdentity | ConvertTo-Json -Depth 20 -Compress
    if ($freshIdentity -cne $baselineIdentity) { throw 'fresh coverage input identity does not match the checked-in baseline.' }
}

function Assert-CoverageFreshnessRejects {
    param([Parameter(Mandatory)][string]$FreshJsonPath, [Parameter(Mandatory)][string]$BaselineJsonPath, [Parameter(Mandatory)][string]$Message, [Parameter(Mandatory)][scriptblock]$Mutate)
    $temporaryPath = Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p33-mutated-report-' + [guid]::NewGuid().ToString('N') + '.json')
    $temporaryMarkdownPath = Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p33-mutated-report-' + [guid]::NewGuid().ToString('N') + '.md')
    try {
        $mutated = Get-Content -Raw -LiteralPath $FreshJsonPath | ConvertFrom-Json
        & $Mutate $mutated
        [IO.File]::WriteAllText($temporaryPath, ($mutated | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $BaselineJsonPath) 'coverage-baseline.md') -Destination $temporaryMarkdownPath -Force
        $failed = $false
        try { Assert-CoverageFreshness $temporaryPath $temporaryMarkdownPath $BaselineJsonPath (Join-Path (Split-Path -Parent $BaselineJsonPath) 'coverage-baseline.md') }
        catch { $failed = $true }
        if (-not $failed) { throw $Message }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
        if (Test-Path -LiteralPath $temporaryMarkdownPath) { Remove-Item -LiteralPath $temporaryMarkdownPath -Force }
    }
}

if ($VerifyDeterminism) {
    $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p33-determinism-' + [guid]::NewGuid().ToString('N'))
    try {
        $first = Join-Path $temporaryRoot 'first'
        $second = Join-Path $temporaryRoot 'second'
        $discovery = Join-Path $ProjectRoot 'tools/Invoke-P33CoverageDiscovery.ps1'
        & pwsh -NoLogo -NoProfile -File $discovery -ProjectRoot $ProjectRoot -SkipBuild -OutputRoot $first | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'first discovery reproduction failed' }
        & pwsh -NoLogo -NoProfile -File $discovery -ProjectRoot $ProjectRoot -SkipBuild -OutputRoot $second | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'second discovery reproduction failed' }
        foreach ($name in @('coverage-baseline.json', 'coverage-baseline.md')) {
            $left = Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $first $name)
            $right = Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $second $name)
            Assert-True ($left.Hash -ceq $right.Hash) "determinism drifted for $name"
        }
        $baselineJsonPath = Join-Path (Split-Path -Parent $ReportPath) 'coverage-baseline.json'
        $baselineMarkdownPath = Join-Path (Split-Path -Parent $ReportPath) 'coverage-baseline.md'
        Assert-CoverageFreshness (Join-Path $first 'coverage-baseline.json') (Join-Path $first 'coverage-baseline.md') $baselineJsonPath $baselineMarkdownPath
        Assert-CoverageFreshnessRejects (Join-Path $first 'coverage-baseline.json') $baselineJsonPath 'coverage freshness accepted a mutated sourceRevision.' { param($value) $value.sourceRevision = ([string]$value.sourceRevision) + '-mutated' }
        Assert-CoverageFreshnessRejects (Join-Path $first 'coverage-baseline.json') $baselineJsonPath 'coverage freshness accepted a mutated operation count.' { param($value) $value.totalOperations = [int]$value.totalOperations + 1 }
        Write-Output 'PASS P3.3 coverage JSON/Markdown determinism, baseline freshness, input identity, and negative freshness regression'
    }
    finally {
        if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
    }
}
