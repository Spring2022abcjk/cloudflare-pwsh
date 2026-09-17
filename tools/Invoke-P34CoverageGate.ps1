[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ReportPath = (Join-Path $ProjectRoot 'artifacts/p3.3/coverage-baseline.json'),
    [string]$BaselinePath = (Join-Path $ProjectRoot 'artifacts/p3.3/coverage-baseline.json'),
    [string]$PolicyPath = (Join-Path $ProjectRoot 'build/p34-coverage-policy.json'),
    [string]$SecondReportPath,
    [string]$OutputPath = (Join-Path $ProjectRoot 'artifacts/p34/coverage-gate.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
function Resolve-P34CoveragePath {
    param([Parameter(Mandatory)][string]$Path)
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $root $Path))
}
function Read-P34CoverageJson {
    param([Parameter(Mandatory)][string]$Path)
    $resolved = Resolve-P34CoveragePath $Path
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Coverage report is missing: $resolved" }
    try { return (Get-Content -Raw -LiteralPath $resolved | ConvertFrom-Json) } catch { throw "Coverage report is not valid JSON: $resolved" }
}
function Get-P34CoverageHash { param([Parameter(Mandatory)][string]$Path); return ((Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash).ToLowerInvariant() }

$reportPath = Resolve-P34CoveragePath $ReportPath
$baselinePath = Resolve-P34CoveragePath $BaselinePath
$policyPath = Resolve-P34CoveragePath $PolicyPath
$outputPath = Resolve-P34CoveragePath $OutputPath
$report = Read-P34CoverageJson $reportPath
$baseline = Read-P34CoverageJson $baselinePath
if (-not (Test-Path -LiteralPath $policyPath -PathType Leaf)) { throw "P3.4 coverage policy is missing: $policyPath" }
$policy = Get-Content -Raw -LiteralPath $policyPath | ConvertFrom-Json
if ([int]$policy.version -ne 1 -or [string]$policy.stage -cne 'P3.4') { throw 'P3.4 coverage policy version/stage is unsupported.' }
$schemaManifestPath = Resolve-P34CoveragePath 'build/pinned-schema.json'
if (-not (Test-Path -LiteralPath $schemaManifestPath -PathType Leaf)) { throw "P3.4 pinned schema manifest is missing: $schemaManifestPath" }
$schemaManifest = Get-Content -Raw -LiteralPath $schemaManifestPath | ConvertFrom-Json
foreach ($field in @('revision', 'sourceRevision', 'sourcePath', 'sha256')) {
    if ([string]::IsNullOrWhiteSpace([string]$schemaManifest.$field)) { throw "P3.4 pinned schema manifest is missing '$field'." }
}

$allowed = @($policy.requiredClassifications | ForEach-Object { [string]$_ })
if ($allowed.Count -eq 0 -or @($allowed | Sort-Object -Unique).Count -ne $allowed.Count) { throw 'P3.4 coverage policy classifications must be present and unique.' }
function Assert-P34CoverageShape {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Label)
    if ([int]$Value.schemaVersion -ne 2 -or [string]$Value.stage -cne 'P3.3' -or $Value.deterministic -ne $true -or $null -ne $Value.generatedAt) { throw "$Label has an invalid deterministic report header." }
    $rows = @($Value.operations)
    if ($rows.Count -ne [int]$Value.totalOperations) { throw "$Label operation count does not match totalOperations." }
    if (@($rows.operationKey | Sort-Object -Unique).Count -ne $rows.Count) { throw "$Label operation keys are not unique." }
    if (@($rows | Where-Object { $allowed -notcontains [string]$_.classification }).Count -ne 0) { throw "$Label contains an unsupported final classification." }
    if (@($rows | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.operationId) -or [string]::IsNullOrWhiteSpace([string]$_.operationKey) }).Count -ne 0) { throw "$Label contains an incomplete operation row." }
    if ($null -eq $Value.classificationCounts) { throw "$Label is missing classificationCounts." }
    $reportedClassCounts = @{}
    foreach ($property in @($Value.classificationCounts.PSObject.Properties)) {
        if ($allowed -notcontains [string]$property.Name) { throw "$Label contains an unsupported classification count key '$($property.Name)'." }
        if ($property.Value -is [bool] -or $property.Value -isnot [byte] -and
            $property.Value -isnot [sbyte] -and $property.Value -isnot [int16] -and
            $property.Value -isnot [uint16] -and $property.Value -isnot [int32] -and
            $property.Value -isnot [uint32] -and $property.Value -isnot [int64] -and
            $property.Value -isnot [uint64]) {
            throw "$Label classification count '$($property.Name)' is not an integer."
        }
        try { $reportedCount = [int64]$property.Value } catch { throw "$Label classification count '$($property.Name)' is out of range." }
        if ($reportedCount -lt 0) { throw "$Label classification count '$($property.Name)' is negative." }
        $reportedClassCounts[[string]$property.Name] = $reportedCount
    }
    $recomputedClassCounts = @{}
    foreach ($classification in $allowed) { $recomputedClassCounts[$classification] = 0 }
    foreach ($row in $rows) { $recomputedClassCounts[[string]$row.classification]++ }
    foreach ($classification in $allowed) {
        $reportedCount = if ($reportedClassCounts.ContainsKey($classification)) { $reportedClassCounts[$classification] } else { 0 }
        if ($reportedCount -ne $recomputedClassCounts[$classification]) {
            throw "$Label classification histogram does not reconcile for '$classification': reported=$reportedCount recomputed=$($recomputedClassCounts[$classification])."
        }
    }
    $classSum = ($reportedClassCounts.Values | Measure-Object -Sum).Sum
    if ([int]$classSum -ne $rows.Count) { throw "$Label classification counts do not reconcile." }
    if ([int]$Value.countSemantics.normalizedSchemaCount -ne [int]$Value.normalizedSchemaCount -or
        [int]$Value.countSemantics.runtimeReadyStageCount -ne [int]$Value.stageCounts.runtimeReady -or
        [int]$Value.countSemantics.finalUnsupportedRuntimeCapabilityCount -ne [int]$Value.classificationCounts.UnsupportedRuntimeCapability) {
        throw "$Label count semantics do not reconcile."
    }
    return $rows
}
$rows = @(Assert-P34CoverageShape $report 'candidate coverage report')
$baselineRows = @(Assert-P34CoverageShape $baseline 'baseline coverage report')
if ([string]$report.sourceRevision -cne [string]$baseline.sourceRevision -or [string]$report.sourcePath -cne [string]$baseline.sourcePath) { throw 'Candidate coverage source identity differs from the baseline; update the pinned baseline explicitly.' }
if ([string]$report.sourceRevision -cne [string]$schemaManifest.sourceRevision -or [string]$report.sourcePath -cne ('ref/api-schemas/' + [string]$schemaManifest.sourcePath)) {
    throw 'Candidate coverage source identity differs from the pinned schema manifest.'
}
$reportSourceIdentity = $report.inputIdentity.source
if ($null -eq $reportSourceIdentity) { throw 'Candidate coverage report is missing inputIdentity.source.' }
if ([string]$reportSourceIdentity.path -cne [string]$report.sourcePath -or
    [string]$reportSourceIdentity.revision -cne [string]$schemaManifest.sourceRevision -or
    [string]$reportSourceIdentity.sha256 -cne [string]$schemaManifest.sha256) {
    throw 'Candidate coverage report inputIdentity.source does not match the pinned schema manifest.'
}
$reportIdentity = $report.inputIdentity | ConvertTo-Json -Depth 20 -Compress
$baselineIdentity = $baseline.inputIdentity | ConvertTo-Json -Depth 20 -Compress
if ($reportIdentity -cne $baselineIdentity) { throw 'Candidate coverage input identity differs from the baseline; update the pinned baseline explicitly.' }
if ([string]$policy.baselinePath -cne 'artifacts/p3.3/coverage-baseline.json') { throw 'P3.4 coverage policy must name the canonical baseline artifact.' }

if (-not [string]::IsNullOrWhiteSpace($SecondReportPath)) {
    $secondPath = Resolve-P34CoveragePath $SecondReportPath
    if (-not (Test-Path -LiteralPath $secondPath -PathType Leaf)) { throw "Second deterministic coverage report is missing: $secondPath" }
    if ((Get-P34CoverageHash $reportPath) -cne (Get-P34CoverageHash $secondPath)) { throw 'Repeated coverage discovery produced different JSON bytes.' }
}

$baselineByKey = @{}
foreach ($row in $baselineRows) { $baselineByKey[[string]$row.operationKey] = $row }
$currentByKey = @{}
foreach ($row in $rows) { $currentByKey[[string]$row.operationKey] = $row }
$dropped = @($baselineByKey.Keys | Where-Object { -not $currentByKey.ContainsKey($_) } | Sort-Object)
$supported = @('Supported', 'SupportedWithOverride')
$supportedRegressions = [Collections.Generic.List[object]]::new()
foreach ($key in $baselineByKey.Keys) {
    $old = $baselineByKey[$key]
    if ($supported -contains [string]$old.classification -and $currentByKey.ContainsKey($key) -and $supported -notcontains [string]$currentByKey[$key].classification) {
        $supportedRegressions.Add([pscustomobject]@{ operationKey = $key; oldClassification = [string]$old.classification; newClassification = [string]$currentByKey[$key].classification })
    }
}
$newAmbiguous = @($rows | Where-Object { [string]$_.classification -eq 'AmbiguousSemantics' -and -not $baselineByKey.ContainsKey([string]$_.operationKey) } | ForEach-Object operationKey | Sort-Object)
$newManual = @($rows | Where-Object { [string]$_.classification -eq 'NeedsManualReview' -and -not $baselineByKey.ContainsKey([string]$_.operationKey) } | ForEach-Object operationKey | Sort-Object)
$manualIncrease = [int]$report.classificationCounts.NeedsManualReview - [int]$baseline.classificationCounts.NeedsManualReview
function Get-P34NonNegativeRule {
    param([Parameter(Mandatory)][string]$Name)
    $value = $policy.rules.PSObject.Properties[$Name].Value
    if ($null -eq $value -or [int]$value -lt 0) { throw "P3.4 coverage policy rule '$Name' must be a non-negative integer." }
    return [int]$value
}
$violations = [Collections.Generic.List[object]]::new()
if ($dropped.Count -gt (Get-P34NonNegativeRule 'maxDroppedBaselineOperations')) { $violations.Add([pscustomobject]@{ category = 'DroppedBaselineOperations'; count = $dropped.Count; values = $dropped }) }
if ($supportedRegressions.Count -gt (Get-P34NonNegativeRule 'maxSupportedOperationRegressions')) { $violations.Add([pscustomobject]@{ category = 'SupportedOperationRegression'; count = $supportedRegressions.Count; values = @($supportedRegressions | Sort-Object operationKey) }) }
if ($newAmbiguous.Count -gt (Get-P34NonNegativeRule 'maxNewAmbiguousSemantics')) { $violations.Add([pscustomobject]@{ category = 'NewAmbiguousSemantics'; count = $newAmbiguous.Count; values = $newAmbiguous }) }
if ($newManual.Count -gt (Get-P34NonNegativeRule 'maxNewManualReview')) { $violations.Add([pscustomobject]@{ category = 'NewManualReview'; count = $newManual.Count; values = $newManual }) }
if ($manualIncrease -gt (Get-P34NonNegativeRule 'maxManualReviewIncrease')) { $violations.Add([pscustomobject]@{ category = 'ManualReviewIncrease'; count = $manualIncrease; values = @() }) }

$summary = [ordered]@{
    schemaVersion = 1
    stage = 'P3.4'
    gateName = 'P3.4.CoverageGate'
    gateType = 'Coverage'
    status = if ($violations.Count -eq 0) { 'Passed' } else { 'Failed' }
    policyIdentity = [ordered]@{
        path = [IO.Path]::GetRelativePath($root, $policyPath).Replace('\', '/')
        sha256 = Get-P34CoverageHash $policyPath
    }
    inputReportIdentity = [ordered]@{
        fileName = [IO.Path]::GetFileName($reportPath)
        sha256 = Get-P34CoverageHash $reportPath
    }
    schemaIdentity = [ordered]@{
        revision = [string]$schemaManifest.revision
        sourceRevision = [string]$schemaManifest.sourceRevision
        sourcePath = [string]$schemaManifest.sourcePath
        sha256 = [string]$schemaManifest.sha256
    }
    reportPath = [IO.Path]::GetRelativePath($root, $reportPath).Replace('\', '/')
    baselinePath = [IO.Path]::GetRelativePath($root, $baselinePath).Replace('\', '/')
    reportSha256 = Get-P34CoverageHash $reportPath
    deterministicComparison = if ([string]::IsNullOrWhiteSpace($SecondReportPath)) { 'not-requested' } else { 'passed' }
    totalOperations = [int]$report.totalOperations
    baselineOperations = [int]$baseline.totalOperations
    newAmbiguousSemantics = $newAmbiguous
    newManualReview = $newManual
    manualReviewIncrease = $manualIncrease
    droppedBaselineOperations = $dropped
    supportedOperationRegressions = @($supportedRegressions | Sort-Object operationKey)
    violations = @($violations)
}
$outputDirectory = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$json = $summary | ConvertTo-Json -Depth 30
$normalized = $json.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
[IO.File]::WriteAllText($outputPath, $normalized, [Text.UTF8Encoding]::new($false))
if ($violations.Count -ne 0) { throw "P3.4 coverage gate failed with $($violations.Count) violation(s); see $outputPath." }
Write-Output "PASS P3.4 coverage gate operations=$($report.totalOperations) -> $outputPath"
