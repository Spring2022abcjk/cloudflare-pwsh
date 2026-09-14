[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $ProjectRoot 'tools/ReadOnlyStaging.ps1') -Library
. (Join-Path $ProjectRoot 'tools/P33ReadOnlyStaging.ps1') -Library

$declared = @(Get-P33RequiredInputPaths -ProjectRoot $ProjectRoot)
foreach ($required in @(
    'Cloudflare.P1.sln',
    'artifacts/p2.3/projection/d1-database.json',
    'artifacts/p3.3/coverage-baseline.json',
    'ref/api-schemas/openapi.json',
    'tools/Generate-P33D1Fixture.ps1'
)) {
    if ($declared -notcontains $required) { throw "P3.3 staging declaration omitted required input: $required" }
}
foreach ($notP33 in @('fixtures/dns-records/create.json', 'artifacts/p3.3/CmdletModel.json', 'src/Cloudflare.PowerShell/Generated/Cmdlets/P33D1DatabaseCmdlets.cs')) {
    if ($declared -contains $notP33) { throw "P3.3 staging declaration unexpectedly stages P3.2/generated input: $notP33" }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('p33-staging-contract-' + [guid]::NewGuid().ToString('N'))
try {
    $inputRoot = Join-Path $root 'input'
    $stagingRoot = Join-Path $root 'staging'
    New-Item -ItemType Directory -Path (Join-Path $inputRoot '.git/objects/pack'), (Join-Path $inputRoot 'bin'), (Join-Path $inputRoot 'cache') -Force | Out-Null
    'required' | Set-Content -LiteralPath (Join-Path $inputRoot 'required.cs') -Encoding utf8NoBOM
    'fake-pack' | Set-Content -LiteralPath (Join-Path $inputRoot '.git/objects/pack/fake-pack') -Encoding utf8NoBOM
    'build' | Set-Content -LiteralPath (Join-Path $inputRoot 'bin/output.dll') -Encoding utf8NoBOM
    'cache' | Set-Content -LiteralPath (Join-Path $inputRoot 'cache/entry') -Encoding utf8NoBOM
    'unrelated' | Set-Content -LiteralPath (Join-Path $inputRoot 'unrelated.cs') -Encoding utf8NoBOM

    $expected = @('required.cs')
    Copy-ReadOnlyStagingFiles -SourceRoot $inputRoot -DestinationRoot $stagingRoot -RelativePaths $expected
    $inventory = @(Assert-ReadOnlyStagingInputContract -Root $stagingRoot -ExpectedRelativePaths $expected)
    if ($inventory.Count -ne 1 -or -not (Test-Path -LiteralPath (Join-Path $stagingRoot 'required.cs') -PathType Leaf)) { throw 'P3.3 required input was not staged.' }
    foreach ($forbidden in @('.git', 'bin', 'cache', 'unrelated.cs')) {
        if (Test-Path -LiteralPath (Join-Path $stagingRoot $forbidden) -PathType Any) { throw "P3.3 staging admitted forbidden/unrelated input: $forbidden" }
    }

    $missingFailed = $false
    try { Copy-ReadOnlyStagingFiles -SourceRoot $inputRoot -DestinationRoot (Join-Path $root 'missing') -RelativePaths @('missing-required.json') }
    catch { $missingFailed = $true }
    if (-not $missingFailed) { throw 'P3.3 staging did not fail for a missing required input.' }
    Write-Output 'PASS P3.3 staging declaration and shared exact-set/VCS/build/cache/missing-input contract'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
