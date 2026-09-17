[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

$before = Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'artifacts/coverage/before-global-coverage.json') | ConvertFrom-Json
$after = Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'artifacts/coverage/after-global-coverage.json') | ConvertFrom-Json
$taxonomy = Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'artifacts/coverage/blocker-taxonomy.json') | ConvertFrom-Json

Assert-True ([int]$before.totalOperations -eq [int]$after.totalOperations) 'projection reduction changed operation population.'
Assert-True ([string]$before.sourceRevision -ceq [string]$after.sourceRevision) 'projection reduction changed source revision.'
Assert-True ([int]$before.stageCounts.projectionConflicts -eq 568) 'unexpected pinned before projection conflict count.'
Assert-True ([int]$after.stageCounts.projectionConflicts -eq 57) 'after projection conflict count did not stop at unresolved ambiguity.'
Assert-True ([int]$before.classificationCounts.UnsupportedProjectionCapability -eq 491) 'unexpected pinned before unsupported projection count.'
Assert-True ([int]$after.classificationCounts.UnsupportedProjectionCapability -eq 53) 'after unsupported projection count did not reconcile.'
Assert-True ([int]$after.stageCounts.projectionReady -eq 3350) 'after projection-ready stage count did not reconcile.'
Assert-True ([int]$after.projectionResolutionCounts.ScopeKey -eq 458) 'scope-key resolution count did not reconcile.'
Assert-True ([int]$after.projectionResolutionCounts.HttpMethod -eq 53) 'HTTP-method resolution count did not reconcile.'
Assert-True ([int]$after.classificationCounts.NeedsManualReview -eq 617) 'manual review was reduced without semantic evidence.'

$beforeKeys = @($before.operations | ForEach-Object operationKey | Sort-Object)
$afterKeys = @($after.operations | ForEach-Object operationKey | Sort-Object)
Assert-True (($beforeKeys -join "`n") -ceq ($afterKeys -join "`n")) 'before/after operation identity set drifted.'
Assert-True ([int]$before.stageCounts.currentPublicSurface -eq [int]$after.stageCounts.currentPublicSurface) 'projection reduction changed public surface membership.'
Assert-True (@($after.operations | Where-Object { $_.projectionStatus -eq 'ResolvedByGenericRule' -and $_.currentPublicSurface }).Count -eq 0) 'generic projection resolution auto-admitted a public operation.'

$categories = @($taxonomy.categories)
foreach ($expected in @(
        @{ name = 'ScopeProjectionAmbiguity'; count = 458; percentage = 80.63 },
        @{ name = 'MethodVariantParameterSetCollision'; count = 53; percentage = 9.33 },
        @{ name = 'ParameterSetIndistinguishability'; count = 57; percentage = 10.04 },
        @{ name = 'LowConfidenceSemanticInference'; count = 617; percentage = 100.0 }
    )) {
    $category = $categories | Where-Object category -eq $expected.name
    Assert-True ($null -ne $category) "taxonomy category '$($expected.name)' is missing."
    Assert-True ([int]$category.count -eq $expected.count) "taxonomy category '$($expected.name)' count drifted."
    Assert-True ([double]$category.percentage -eq $expected.percentage) "taxonomy category '$($expected.name)' percentage drifted."
}
Assert-True ([int]$taxonomy.population.projectionConflictManualOverlapBefore -eq 77) 'taxonomy projection/manual overlap did not reconcile.'

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p33-reduction-taxonomy-' + [guid]::NewGuid().ToString('N'))
$secondRoot = Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p33-reduction-taxonomy-' + [guid]::NewGuid().ToString('N'))
try {
    $tool = Join-Path $ProjectRoot 'tools/Invoke-P33ProjectionReduction.ps1'
    & pwsh -NoLogo -NoProfile -File $tool -ProjectRoot $ProjectRoot -OutputRoot $temporaryRoot | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'first taxonomy generation failed.' }
    & pwsh -NoLogo -NoProfile -File $tool -ProjectRoot $ProjectRoot -OutputRoot $secondRoot | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'second taxonomy generation failed.' }
    foreach ($name in @('blocker-taxonomy.json', 'blocker-taxonomy.md', 'after-global-coverage.json', 'after-global-coverage.md')) {
        $left = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $temporaryRoot $name)).Hash
        $right = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $secondRoot $name)).Hash
        Assert-True ($left -ceq $right) "projection reduction artifact '$name' is not deterministic."
    }
}
finally {
    foreach ($path in @($temporaryRoot, $secondRoot)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
    }
}

Write-Output 'PASS P3.3 projection reduction before/after delta, taxonomy, public-boundary, and determinism contracts'
