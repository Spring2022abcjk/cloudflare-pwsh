[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$BeforeJsonPath = (Join-Path $ProjectRoot 'artifacts/coverage/before-global-coverage.json'),
    [string]$BeforeMarkdownPath = (Join-Path $ProjectRoot 'artifacts/coverage/before-global-coverage.md'),
    [string]$AfterJsonPath = (Join-Path $ProjectRoot 'artifacts/p3.3/coverage-baseline.json'),
    [string]$AfterMarkdownPath = (Join-Path $ProjectRoot 'artifacts/p3.3/coverage-baseline.md'),
    [string]$OutputRoot = (Join-Path $ProjectRoot 'artifacts/coverage')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
    param([Parameter(Mandatory)][string]$Path)
    return [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)
}

function Write-Utf8CrLf {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
    [IO.File]::WriteAllText($Path, $normalized, [Text.UTF8Encoding]::new($false))
}

function Get-RowMap {
    param([Parameter(Mandatory)][object]$Report)
    $map = @{}
    foreach ($row in @($Report.operations)) { $map[[string]$row.operationId] = $row }
    return $map
}

function Get-CountMap {
    param([Parameter(Mandatory)][object[]]$Rows, [Parameter(Mandatory)][string]$Property)
    $counts = [ordered]@{}
    foreach ($row in $Rows) {
        $value = [string]$row.$Property
        if (-not $counts.Contains($value)) { $counts[$value] = 0 }
        $counts[$value]++
    }
    return $counts
}

function New-Category {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][object[]]$Rows,
        [Parameter(Mandatory)][int]$Denominator,
        [Parameter(Mandatory)][string]$Reason,
        [Parameter(Mandatory)][string]$Evidence,
        [Parameter(Mandatory)][string]$ResolutionClass,
        [Parameter(Mandatory)][object]$BeforeMap,
        [Parameter(Mandatory)][object]$AfterMap
    )
    $sortedRows = @($Rows | Sort-Object operationId)
    $beforeCounts = Get-CountMap -Rows $sortedRows -Property classification
    $afterRows = @($sortedRows | ForEach-Object { $AfterMap[[string]$_.operationId] })
    $afterCounts = Get-CountMap -Rows $afterRows -Property classification
    $families = @($sortedRows | Group-Object resourceFamily | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name | Select-Object -First 10 | ForEach-Object {
            [ordered]@{ resourceFamily = [string]$_.Name; count = $_.Count }
        })
    $reasons = @($sortedRows | ForEach-Object { @($_.reasonCodes) } | Sort-Object -Unique)
    $evidenceValues = @($sortedRows | ForEach-Object { @($_.evidence) } | Sort-Object -Unique)
    [ordered]@{
        category = $Category
        count = $sortedRows.Count
        denominator = $Denominator
        percentage = if ($Denominator -eq 0) { 0.0 } else { [math]::Round((100.0 * $sortedRows.Count) / $Denominator, 2) }
        representativeOperations = @($sortedRows | Select-Object -First 5 | ForEach-Object operationId)
        resourceFamilies = $families
        currentClassification = [ordered]@{
            before = [pscustomobject]$beforeCounts
            after = [pscustomobject]$afterCounts
        }
        reason = $Reason
        evidence = [ordered]@{
            primary = $Evidence
            reportReasons = $reasons
            reportEvidence = $evidenceValues
        }
        possibleResolutionClass = $ResolutionClass
    }
}

$projectRoot = Resolve-FullPath $ProjectRoot
$beforeJsonPath = Resolve-FullPath $BeforeJsonPath
$beforeMarkdownPath = Resolve-FullPath $BeforeMarkdownPath
$afterJsonPath = Resolve-FullPath $AfterJsonPath
$afterMarkdownPath = Resolve-FullPath $AfterMarkdownPath
$outputRoot = if ([IO.Path]::IsPathRooted($OutputRoot)) { [IO.Path]::GetFullPath($OutputRoot) } else { [IO.Path]::GetFullPath((Join-Path $projectRoot $OutputRoot)) }

foreach ($path in @($beforeJsonPath, $beforeMarkdownPath, $afterJsonPath, $afterMarkdownPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Projection reduction input is missing: $path" }
}

$before = Get-Content -Raw -LiteralPath $beforeJsonPath | ConvertFrom-Json
$after = Get-Content -Raw -LiteralPath $afterJsonPath | ConvertFrom-Json
$beforeMap = Get-RowMap $before
$afterMap = Get-RowMap $after
$beforeRows = @($before.operations)
$afterRows = @($after.operations)
$beforeProjectionConflicts = @($beforeRows | Where-Object projectionStatus -eq 'Conflict')
$beforeManual = @($beforeRows | Where-Object classification -eq 'NeedsManualReview')
$beforeConflictById = @{}
foreach ($row in $beforeProjectionConflicts) { $beforeConflictById[[string]$row.operationId] = $row }

$scopeRows = @($afterRows | Where-Object {
        [string]$_.projectionResolution -eq 'ScopeKey' -and $beforeConflictById.ContainsKey([string]$_.operationId)
    } | ForEach-Object { $beforeConflictById[[string]$_.operationId] })
$methodRows = @($afterRows | Where-Object {
        [string]$_.projectionResolution -eq 'HttpMethod' -and $beforeConflictById.ContainsKey([string]$_.operationId)
    } | ForEach-Object { $beforeConflictById[[string]$_.operationId] })
$unresolvedRows = @($afterRows | Where-Object {
        [string]$_.projectionStatus -eq 'Conflict' -and $beforeConflictById.ContainsKey([string]$_.operationId)
    } | ForEach-Object { $beforeConflictById[[string]$_.operationId] })

$categories = @(
    (New-Category -Category 'ScopeProjectionAmbiguity' -Rows $scopeRows -Denominator $beforeProjectionConflicts.Count `
        -Reason 'Operations sharing a projected cmdlet and semantic parameter-set name have distinct normalized scope-binding signatures; the generic scope-key rule gives each binding a deterministic parameter-set identity.' `
        -Evidence 'normalized scope bindings are distinct within the projected cmdlet/parameter-set collision group' `
        -ResolutionClass 'Projection capability rule: scope-key parameter-set disambiguation' -BeforeMap $beforeMap -AfterMap $afterMap),
    (New-Category -Category 'MethodVariantParameterSetCollision' -Rows $methodRows -Denominator $beforeProjectionConflicts.Count `
        -Reason 'Operations sharing a projected cmdlet and semantic parameter-set name have distinct HTTP methods; the generic method rule gives each method a deterministic parameter-set identity.' `
        -Evidence 'normalized HTTP methods are distinct within the remaining collision group after scope-key resolution' `
        -ResolutionClass 'Projection capability rule: HTTP-method parameter-set disambiguation' -BeforeMap $beforeMap -AfterMap $afterMap),
    (New-Category -Category 'ParameterSetIndistinguishability' -Rows $unresolvedRows -Denominator $beforeProjectionConflicts.Count `
        -Reason 'The remaining operations share the same projected cmdlet, semantic parameter-set name, and no unique generic scope or method discriminator; a public selector or noun decision would require product/UX evidence.' `
        -Evidence 'projection remains Conflict after deterministic scope-key and HTTP-method rules' `
        -ResolutionClass 'Manual product/UX decision; retain UnsupportedProjectionCapability until an explicit policy is evidenced' -BeforeMap $beforeMap -AfterMap $afterMap),
    (New-Category -Category 'LowConfidenceSemanticInference' -Rows $beforeManual -Denominator $beforeManual.Count `
        -Reason 'The normalizer used only a method heuristic for semantic kind; automatic public verb/noun admission would guess action versus CRUD meaning.' `
        -Evidence 'semanticConfidence=Low and semanticSource=MethodHeuristic' `
        -ResolutionClass 'Manual semantic/product decision or evidence-backed correction; do not resolve by projection override alone' -BeforeMap $beforeMap -AfterMap $afterMap)
)

$overlap = @($beforeProjectionConflicts | Where-Object { [string]$_.classification -eq 'NeedsManualReview' }).Count
$taxonomy = [ordered]@{
    schemaVersion = 1
    stage = 'P3.3-projection-reduction'
    deterministic = $true
    generatedAt = $null
    sourceRevision = [string]$before.sourceRevision
    population = [ordered]@{
        totalOperations = [int]$before.totalOperations
        projectionConflictsBefore = $beforeProjectionConflicts.Count
        needsManualReviewBefore = $beforeManual.Count
        projectionConflictManualOverlapBefore = $overlap
        projectionConflictsAfter = @($afterRows | Where-Object projectionStatus -eq 'Conflict').Count
        needsManualReviewAfter = @($afterRows | Where-Object classification -eq 'NeedsManualReview').Count
    }
    categories = @($categories | Sort-Object category)
    resolutionSummary = [ordered]@{
        scopeKeyRows = $scopeRows.Count
        httpMethodRows = $methodRows.Count
        unresolvedProjectionRows = $unresolvedRows.Count
        manualSemanticRows = $beforeManual.Count
    }
    inputIdentity = [ordered]@{
        beforeJson = [IO.Path]::GetRelativePath($projectRoot, $beforeJsonPath).Replace('\', '/')
        beforeMarkdown = [IO.Path]::GetRelativePath($projectRoot, $beforeMarkdownPath).Replace('\', '/')
        afterJson = [IO.Path]::GetRelativePath($projectRoot, $afterJsonPath).Replace('\', '/')
        afterMarkdown = [IO.Path]::GetRelativePath($projectRoot, $afterMarkdownPath).Replace('\', '/')
    }
}

$afterJsonOutput = Join-Path $outputRoot 'after-global-coverage.json'
$afterMarkdownOutput = Join-Path $outputRoot 'after-global-coverage.md'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
Copy-Item -LiteralPath $afterJsonPath -Destination $afterJsonOutput -Force
Copy-Item -LiteralPath $afterMarkdownPath -Destination $afterMarkdownOutput -Force
$jsonOutput = Join-Path $outputRoot 'blocker-taxonomy.json'
$markdownOutput = Join-Path $outputRoot 'blocker-taxonomy.md'
Write-Utf8CrLf $jsonOutput (($taxonomy | ConvertTo-Json -Depth 100) + "`n")

$md = [Text.StringBuilder]::new()
[void]$md.AppendLine('# P3.3 Projection Blocker Taxonomy')
[void]$md.AppendLine()
[void]$md.AppendLine('- Source revision: `' + $taxonomy.sourceRevision + '`')
[void]$md.AppendLine('- Total operations: `' + $taxonomy.population.totalOperations + '`')
[void]$md.AppendLine('- Projection conflicts: `' + $taxonomy.population.projectionConflictsBefore + '` before → `' + $taxonomy.population.projectionConflictsAfter + '` after')
[void]$md.AppendLine('- NeedsManualReview: `' + $taxonomy.population.needsManualReviewBefore + '` before → `' + $taxonomy.population.needsManualReviewAfter + '` after')
[void]$md.AppendLine('- Projection/manual overlap before: `' + $taxonomy.population.projectionConflictManualOverlapBefore + '`')
[void]$md.AppendLine()
[void]$md.AppendLine('Percentages for the first three categories use the before projection-conflict population as denominator; the semantic category uses the before manual-review population.')
[void]$md.AppendLine()
[void]$md.AppendLine('## Categories')
[void]$md.AppendLine()
[void]$md.AppendLine('| Category | Count | Percentage | Before classification | After classification | Resolution class |')
[void]$md.AppendLine('| --- | ---: | ---: | --- | --- | --- |')
foreach ($category in @($taxonomy.categories)) {
    $beforeCounts = @($category.currentClassification.before.PSObject.Properties | ForEach-Object { $_.Name + '=' + $_.Value }) -join '; '
    $afterCounts = @($category.currentClassification.after.PSObject.Properties | ForEach-Object { $_.Name + '=' + $_.Value }) -join '; '
    [void]$md.AppendLine('| `' + $category.category + '` | ' + $category.count + ' | ' + $category.percentage + '% | ' + $beforeCounts + ' | ' + $afterCounts + ' | ' + $category.possibleResolutionClass + ' |')
}
[void]$md.AppendLine()
foreach ($category in @($taxonomy.categories)) {
    [void]$md.AppendLine('## `' + $category.category + '`')
    [void]$md.AppendLine()
    [void]$md.AppendLine($category.reason)
    [void]$md.AppendLine()
    [void]$md.AppendLine('- Evidence: ' + $category.evidence.primary)
    [void]$md.AppendLine('- Representative operations: `' + (@($category.representativeOperations) -join '`, `') + '`')
    [void]$md.AppendLine('- Resource families: ' + (@($category.resourceFamilies | ForEach-Object { '`' + $_.resourceFamily + '`=' + $_.count }) -join ', '))
    [void]$md.AppendLine('- Report reason codes: `' + (@($category.evidence.reportReasons) -join '`, `') + '`')
    [void]$md.AppendLine('- Possible resolution: ' + $category.possibleResolutionClass)
    [void]$md.AppendLine()
}
[void]$md.AppendLine('The taxonomy is diagnostic. A resolved projection identity does not auto-admit an operation to the public module; the separate admission policy remains authoritative.')
Write-Utf8CrLf $markdownOutput $md.ToString()
Write-Output "PASS P3.3 projection reduction taxonomy -> $jsonOutput"
Write-Output "PASS P3.3 after coverage -> $afterJsonOutput"
