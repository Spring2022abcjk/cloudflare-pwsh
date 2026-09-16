[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p34-tests-' + [guid]::NewGuid().ToString('N'))
$initial = @(& git -C $root status --short) -join "`n"

function Invoke-P34TestChild {
    param([Parameter(Mandatory)][string]$ScriptPath, [string[]]$Arguments, [Parameter(Mandatory)][string]$Label)
    & pwsh -NoLogo -NoProfile -File $ScriptPath @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE." }
}
function Assert-P34TestChildFails {
    param([Parameter(Mandatory)][string]$ScriptPath, [string[]]$Arguments, [Parameter(Mandatory)][string]$Label)
    & pwsh -NoLogo -NoProfile -File $ScriptPath @Arguments | Out-Host
    if ($LASTEXITCODE -eq 0) { throw "$Label unexpectedly passed." }
}
function Write-P34TestJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value)
    $json = $Value | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}
function Assert-P34ScriptParses {
    param([Parameter(Mandatory)][string]$Path)
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors) | Out-Null
    if (@($errors).Count -ne 0) { throw "PowerShell parse errors in '$Path': $(@($errors | ForEach-Object Message) -join '; ')" }
}

try {
    New-Item -ItemType Directory -Force -Path $temporary | Out-Null
    foreach ($script in @(
        'tools/Initialize-P34Schema.ps1',
        'tools/Test-P34Host.ps1',
        'tools/Invoke-P34CompatibilityGate.ps1',
        'tools/Invoke-P34CoverageGate.ps1',
        'tools/New-P34Package.ps1',
        'tools/Invoke-P34DeterministicValidation.ps1',
        'tools/Invoke-P34SchemaUpdateValidation.ps1',
        'tests/P34PackageSmoke.ps1'
    )) { Assert-P34ScriptParses (Join-Path $root $script) }
    Invoke-P34TestChild (Join-Path $root 'tools/Initialize-P34Schema.ps1') @('-ProjectRoot', $root, '-VerifyOnly') 'pinned schema verification'
    Invoke-P34TestChild (Join-Path $root 'tools/Test-P34Host.ps1') @() 'formal host baseline verification'

    $compatibilityGate = Join-Path $temporary 'compatibility-gate.json'
    $coverageGate = Join-Path $temporary 'coverage-gate.json'
    $compatibilityReport = Join-Path $root 'artifacts/compatibility/0b726721291ca19bfcc3add9e3c2b3f57b9d94e6-to-28bfb054e5fa106464e9fbbf0ffbf362bc85234d.json'
    $coverageReport = Join-Path $root 'artifacts/p3.3/coverage-baseline.json'
    $coverageMarkdown = Join-Path $root 'artifacts/p3.3/coverage-baseline.md'
    Invoke-P34TestChild (Join-Path $root 'tools/Invoke-P34CompatibilityGate.ps1') @('-ProjectRoot', $root, '-ReportPath', $compatibilityReport, '-OutputPath', $compatibilityGate) 'compatibility gate'
    Invoke-P34TestChild (Join-Path $root 'tools/Invoke-P34CoverageGate.ps1') @('-ProjectRoot', $root, '-ReportPath', $coverageReport, '-BaselinePath', $coverageReport, '-OutputPath', $coverageGate) 'coverage gate'

    $firstCandidate = Join-Path $temporary 'candidate-one'
    $secondCandidate = Join-Path $temporary 'candidate-two'
    $packageScript = Join-Path $root 'tools/New-P34Package.ps1'
    $packageArguments = @(
        '-ProjectRoot', $root,
        '-OutputRoot', $firstCandidate,
        '-CompatibilityReportPath', $compatibilityReport,
        '-CompatibilityGatePath', $compatibilityGate,
        '-CoverageJsonPath', $coverageReport,
        '-CoverageMarkdownPath', $coverageMarkdown,
        '-CoverageGatePath', $coverageGate,
        '-SkipBuild'
    )
    Invoke-P34TestChild $packageScript $packageArguments 'first package candidate assembly'
    $packageArguments[3] = $secondCandidate
    Invoke-P34TestChild $packageScript $packageArguments 'second package candidate assembly'
    $firstArchive = Join-Path $firstCandidate 'Cloudflare.PowerShell.0.1.0.zip'
    $secondArchive = Join-Path $secondCandidate 'Cloudflare.PowerShell.0.1.0.zip'
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $firstArchive).Hash -cne (Get-FileHash -Algorithm SHA256 -LiteralPath $secondArchive).Hash) { throw 'Repeated package assembly produced different archive bytes.' }
    $firstManifest = Get-Content -Raw -LiteralPath (Join-Path $firstCandidate 'candidate-manifest.json')
    $secondManifest = Get-Content -Raw -LiteralPath (Join-Path $secondCandidate 'candidate-manifest.json')
    if ($firstManifest -cne $secondManifest) { throw 'Repeated package assembly produced different candidate manifests.' }
    Invoke-P34TestChild (Join-Path $root 'tests/P34PackageSmoke.ps1') @('-ModulePath', (Join-Path $firstCandidate 'package/Cloudflare.PowerShell')) 'candidate package smoke'

    $mutatedCompatibility = Join-Path $temporary 'mutated-compatibility.json'
    $compatibilityValue = Get-Content -Raw -LiteralPath $compatibilityReport | ConvertFrom-Json
    $compatibilityValue.changes[0].newValue = 'unexpected-value'
    Write-P34TestJson $mutatedCompatibility $compatibilityValue
    Assert-P34TestChildFails (Join-Path $root 'tools/Invoke-P34CompatibilityGate.ps1') @('-ProjectRoot', $root, '-ReportPath', $mutatedCompatibility, '-OutputPath', (Join-Path $temporary 'mutated-compatibility-gate.json')) 'unexpected compatibility change rejection'

    $mutatedCoverage = Join-Path $temporary 'mutated-coverage.json'
    $coverageValue = Get-Content -Raw -LiteralPath $coverageReport | ConvertFrom-Json
    $supportedRow = @($coverageValue.operations | Where-Object classification -in @('Supported', 'SupportedWithOverride') | Select-Object -First 1)
    if ($supportedRow.Count -ne 1) { throw 'Coverage test could not find a supported baseline operation.' }
    $supportedRow[0].classification = 'NeedsManualReview'
    Write-P34TestJson $mutatedCoverage $coverageValue
    Assert-P34TestChildFails (Join-Path $root 'tools/Invoke-P34CoverageGate.ps1') @('-ProjectRoot', $root, '-ReportPath', $mutatedCoverage, '-BaselinePath', $coverageReport, '-OutputPath', (Join-Path $temporary 'mutated-coverage-gate.json')) 'supported-to-manual coverage regression rejection'

    $final = @(& git -C $root status --short) -join "`n"
    if ($final -cne $initial) { throw "P3.4 gate tests changed the worktree unexpectedly. Before:`n$initial`nAfter:`n$final" }
    Write-Output 'PASS P3.4 CI gate scripts, deterministic package assembly, candidate smoke, and negative policy tests'
}
catch {
    Write-Error "P3.4 CI gate tests failed: $($_.Exception.Message)"
    exit 1
}
finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue }
}
