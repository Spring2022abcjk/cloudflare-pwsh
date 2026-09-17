[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot = (Join-Path $ProjectRoot 'artifacts/p34-schema-update-validation')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
$output = if ([IO.Path]::IsPathRooted($OutputRoot)) { [IO.Path]::GetFullPath($OutputRoot) } else { [IO.Path]::GetFullPath((Join-Path $root $OutputRoot)) }
if ((Test-Path -LiteralPath $output -PathType Container) -and @(Get-ChildItem -LiteralPath $output -Force).Count -ne 0) { throw "Schema-update validation output must be absent or empty: $output" }
$outputRelative = [IO.Path]::GetRelativePath($root, $output).Replace('\', '/')
$allowOutputStatus = $outputRelative -ne '.' -and -not $outputRelative.StartsWith('../', [StringComparison]::Ordinal) -and -not [IO.Path]::IsPathRooted($outputRelative)
$initial = @(& git -C $root status --short) -join "`n"
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p34-schema-update-' + [guid]::NewGuid().ToString('N'))

function Invoke-P34SchemaChecked {
    param([Parameter(Mandatory)][string]$FilePath, [Parameter(Mandatory)][string[]]$Arguments, [Parameter(Mandatory)][string]$Label)
    & $FilePath @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE." }
}
function Write-P34SchemaJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value)
    $json = $Value | ConvertTo-Json -Depth 30
    $json = $json.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

try {
    Invoke-P34SchemaChecked 'pwsh' @('-NoLogo', '-NoProfile', '-File', (Join-Path $root 'tools/Initialize-P34Schema.ps1'), '-ProjectRoot', $root) 'pinned schema bootstrap'
    New-Item -ItemType Directory -Force -Path $temporary | Out-Null
    $archive = Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p34-archive-' + [guid]::NewGuid().ToString('N') + '.zip')
    try {
        & git -C $root archive --format=zip --output=$archive HEAD
        if ($LASTEXITCODE -ne 0) { throw 'Could not archive the repository for isolated schema-update validation.' }
        Expand-Archive -LiteralPath $archive -DestinationPath $temporary -Force
    }
    finally { if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force } }
    New-Item -ItemType Directory -Force -Path (Join-Path $temporary 'ref/api-schemas') | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'ref/api-schemas/openapi.json') -Destination (Join-Path $temporary 'ref/api-schemas/openapi.json') -Force
    Copy-Item -LiteralPath (Join-Path $root 'Directory.Build.props') -Destination (Join-Path $temporary 'Directory.Build.props') -Force
    foreach ($path in @('build/p34-compatibility-policy.json', 'build/p34-coverage-policy.json', 'tools/Invoke-P34CompatibilityGate.ps1', 'tools/Invoke-P34CoverageGate.ps1', 'tests/P23Projection.Tests.ps1')) {
        $source = Join-Path $root $path
        $destination = Join-Path $temporary $path
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }
    $tempManifest = Join-Path $temporary 'fixtures/p2.4/openapi-previous-revision.json'
    $tempArtifactRoot = Join-Path $temporary 'artifacts/p34-schema-update'
    Invoke-P34SchemaChecked 'pwsh' @('-NoLogo', '-NoProfile', '-File', (Join-Path $temporary 'tools/Invoke-P24Tests.ps1'), '-ProjectRoot', $temporary, '-SchemaRoot', (Join-Path $temporary 'ref/api-schemas'), '-ArtifactRoot', $tempArtifactRoot, '-SchemaRevisionManifestPath', $tempManifest) 'isolated P1-P2.4 schema-update regression'
    $compatibilityReport = @(Get-ChildItem -LiteralPath $tempArtifactRoot -Filter '*.json' -File | ForEach-Object {
        try { $value = Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json } catch { return }
        if ([string]$value.stage -ceq 'P2.4') { $_.FullName }
    }) | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace([string]$compatibilityReport)) { throw 'Isolated schema-update validation did not produce a P2.4 compatibility report.' }
    $coverageRoot = Join-Path $temporary 'artifacts/p34-schema-update/coverage'
    $coverageOne = Join-Path $coverageRoot 'first'
    $coverageTwo = Join-Path $coverageRoot 'second'
    Invoke-P34SchemaChecked 'pwsh' @('-NoLogo', '-NoProfile', '-File', (Join-Path $temporary 'tools/Invoke-P33CoverageDiscovery.ps1'), '-ProjectRoot', $temporary, '-OutputRoot', $coverageOne, '-SkipBuild') 'first schema-update coverage discovery'
    Invoke-P34SchemaChecked 'pwsh' @('-NoLogo', '-NoProfile', '-File', (Join-Path $temporary 'tools/Invoke-P33CoverageDiscovery.ps1'), '-ProjectRoot', $temporary, '-OutputRoot', $coverageTwo, '-SkipBuild') 'second schema-update coverage discovery'
    $coverageCanonical = Join-Path $coverageRoot 'coverage-report.json'
    Copy-Item -LiteralPath (Join-Path $coverageOne 'coverage-baseline.json') -Destination $coverageCanonical -Force
    Copy-Item -LiteralPath (Join-Path $coverageOne 'coverage-baseline.md') -Destination (Join-Path $coverageRoot 'coverage-report.md') -Force
    Invoke-P34SchemaChecked 'pwsh' @('-NoLogo', '-NoProfile', '-File', (Join-Path $temporary 'tests/P33Coverage.Tests.ps1'), '-ProjectRoot', $temporary, '-ReportPath', $coverageCanonical) 'schema-update coverage schema validation'
    $compatibilityGate = Join-Path $temporary 'artifacts/p34-schema-update/compatibility-gate.json'
    $coverageGate = Join-Path $temporary 'artifacts/p34-schema-update/coverage-gate.json'
    Invoke-P34SchemaChecked 'pwsh' @('-NoLogo', '-NoProfile', '-File', (Join-Path $temporary 'tools/Invoke-P34CompatibilityGate.ps1'), '-ProjectRoot', $temporary, '-ReportPath', $compatibilityReport, '-OutputPath', $compatibilityGate) 'schema-update compatibility gate'
    Invoke-P34SchemaChecked 'pwsh' @('-NoLogo', '-NoProfile', '-File', (Join-Path $temporary 'tools/Invoke-P34CoverageGate.ps1'), '-ProjectRoot', $temporary, '-ReportPath', $coverageCanonical, '-BaselinePath', (Join-Path $temporary 'artifacts/p3.3/coverage-baseline.json'), '-SecondReportPath', (Join-Path $coverageTwo 'coverage-baseline.json'), '-OutputPath', $coverageGate) 'schema-update coverage gate'
    New-Item -ItemType Directory -Force -Path $output | Out-Null
    Copy-Item -LiteralPath $compatibilityReport -Destination (Join-Path $output 'compatibility-report.json') -Force
    Copy-Item -LiteralPath $compatibilityGate -Destination (Join-Path $output 'compatibility-gate.json') -Force
    Copy-Item -LiteralPath $coverageCanonical -Destination (Join-Path $output 'coverage-report.json') -Force
    Copy-Item -LiteralPath (Join-Path $coverageRoot 'coverage-report.md') -Destination (Join-Path $output 'coverage-report.md') -Force
    Copy-Item -LiteralPath $coverageGate -Destination (Join-Path $output 'coverage-gate.json') -Force
    $summary = [ordered]@{ schemaVersion = 1; stage = 'P3.4'; status = 'Passed'; mode = 'workflow-dispatch'; source = 'build/pinned-schema.json'; compatibilityReport = 'compatibility-report.json'; coverageReport = 'coverage-report.json'; gates = @('P1-P2.4 regression', 'coverage schema', 'compatibility policy', 'coverage policy', 'deterministic repeated discovery') }
    Write-P34SchemaJson (Join-Path $output 'summary.json') $summary
    $finalLines = @(& git -C $root status --short)
    if ($allowOutputStatus) {
        $outputStatusPattern = '^\?\?\s+' + [regex]::Escape($outputRelative) + '(?:/|$)'
        $finalLines = @($finalLines | Where-Object { $_ -notmatch $outputStatusPattern })
    }
    $final = $finalLines -join "`n"
    if ($final -cne $initial) { throw "Schema-update validation changed the worktree unexpectedly. Before:`n$initial`nAfter:`n$final" }
    Write-Output "PASS P3.4 schema-update validation output=$output"
}
catch {
    Write-Error "P3.4 schema-update validation failed: $($_.Exception.Message)"
    exit 1
}
finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue }
}
