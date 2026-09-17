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
function Get-P34TestSha256 {
    param([Parameter(Mandatory)][string]$Path)
    return ((Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash).ToLowerInvariant()
}
function Assert-P34ScriptParses {
    param([Parameter(Mandatory)][string]$Path)
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors) | Out-Null
    if (@($errors).Count -ne 0) { throw "PowerShell parse errors in '$Path': $(@($errors | ForEach-Object Message) -join '; ')" }
}
function Assert-P34CoverageWorkflowCanonicalContract {
    $workflowPath = Join-Path $root '.github/workflows/p34-ci.yml'
    $workflow = Get-Content -Raw -LiteralPath $workflowPath
    foreach ($fragment in @(
        "`$canonicalJson = Join-Path `$root 'coverage-report.json'",
        "Copy-Item -LiteralPath (Join-Path `$first 'coverage-baseline.json') -Destination `$canonicalJson -Force",
        "P33Coverage.Tests.ps1 -ReportPath `$canonicalJson",
        "Invoke-P34CoverageGate.ps1 -ReportPath `$canonicalJson",
        '${{ runner.temp }}/p34-coverage/coverage-report.json',
        '${{ runner.temp }}/p34-coverage/coverage-gate.json',
        "CoverageJsonPath (Join-Path `$env:RUNNER_TEMP 'p34-coverage/coverage-report.json')"
    )) {
        if ($workflow.IndexOf($fragment, [StringComparison]::Ordinal) -lt 0) { throw "P3.4 CI workflow is missing canonical coverage contract fragment: $fragment" }
    }
    Write-Output 'PASS P3.4 CI workflow binds coverage validation, gate, upload, and package to coverage-report.json'
}
function Invoke-P34ProvenanceBuild {
    param([Parameter(Mandatory)][string]$SourceRevision)
    & dotnet build (Join-Path $root 'src/Cloudflare.PowerShell/Cloudflare.PowerShell.csproj') --configuration Release --no-incremental --nologo "/p:P34SourceRevision=$SourceRevision" | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "P3.4 provenance build failed with exit code $LASTEXITCODE." }
}
function Assert-P34PackageRejects {
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][string]$CompatibilityGate, [Parameter(Mandatory)][string]$CoverageGate, [string]$CompatibilityReport, [string]$CoverageReport)
    $arguments = [object[]]$packageArguments.Clone()
    $arguments[3] = Join-Path $temporary ('reject-' + $Label)
    if (-not [string]::IsNullOrWhiteSpace($CompatibilityReport)) { $arguments[5] = $CompatibilityReport }
    $arguments[7] = $CompatibilityGate
    if (-not [string]::IsNullOrWhiteSpace($CoverageReport)) { $arguments[9] = $CoverageReport }
    $arguments[13] = $CoverageGate
    Assert-P34TestChildFails $packageScript ([string[]]$arguments) $Label
}
function Assert-P34CompatibilityRejects {
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)]$Value, [string]$PolicyPath)
    $path = Join-Path $temporary ('compat-' + $Label + '.json')
    Write-P34TestJson $path $Value
    $output = Join-Path $temporary ('compat-' + $Label + '-gate.json')
    $arguments = @('-ProjectRoot', $root, '-ReportPath', $path, '-OutputPath', $output)
    if (-not [string]::IsNullOrWhiteSpace($PolicyPath)) { $arguments += @('-PolicyPath', $PolicyPath) }
    Assert-P34TestChildFails (Join-Path $root 'tools/Invoke-P34CompatibilityGate.ps1') $arguments $Label
}
function Assert-P34CoverageRejects {
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)]$Value)
    $path = Join-Path $temporary ('coverage-' + $Label + '.json')
    Write-P34TestJson $path $Value
    Assert-P34TestChildFails (Join-Path $root 'tools/Invoke-P34CoverageGate.ps1') @('-ProjectRoot', $root, '-ReportPath', $path, '-BaselinePath', $coverageReport, '-OutputPath', (Join-Path $temporary ('coverage-' + $Label + '-gate.json'))) $Label
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
    Assert-P34CoverageWorkflowCanonicalContract
    Invoke-P34TestChild (Join-Path $root 'tools/Initialize-P34Schema.ps1') @('-ProjectRoot', $root, '-VerifyOnly') 'pinned schema verification'
    Invoke-P34TestChild (Join-Path $root 'tools/Test-P34Host.ps1') @() 'formal host baseline verification'

    $compatibilityGate = Join-Path $temporary 'compatibility-gate.json'
    $coverageGate = Join-Path $temporary 'coverage-gate.json'
    $compatibilityReport = Join-Path $root 'artifacts/compatibility/0b726721291ca19bfcc3add9e3c2b3f57b9d94e6-to-28bfb054e5fa106464e9fbbf0ffbf362bc85234d.json'
    $coverageBaseline = Join-Path $root 'artifacts/p3.3/coverage-baseline.json'
    $coverageBaselineMarkdown = Join-Path $root 'artifacts/p3.3/coverage-baseline.md'
    $coverageDiscoveryFirst = Join-Path $temporary 'coverage-discovery/first'
    New-Item -ItemType Directory -Force -Path $coverageDiscoveryFirst | Out-Null
    Copy-Item -LiteralPath $coverageBaseline -Destination (Join-Path $coverageDiscoveryFirst 'coverage-baseline.json') -Force
    Copy-Item -LiteralPath $coverageBaselineMarkdown -Destination (Join-Path $coverageDiscoveryFirst 'coverage-baseline.md') -Force
    $coverageReport = Join-Path $temporary 'coverage-report.json'
    $coverageMarkdown = Join-Path $temporary 'coverage-report.md'
    Copy-Item -LiteralPath (Join-Path $coverageDiscoveryFirst 'coverage-baseline.json') -Destination $coverageReport -Force
    Copy-Item -LiteralPath (Join-Path $coverageDiscoveryFirst 'coverage-baseline.md') -Destination $coverageMarkdown -Force
    Invoke-P34TestChild (Join-Path $root 'tools/Invoke-P34CompatibilityGate.ps1') @('-ProjectRoot', $root, '-ReportPath', $compatibilityReport, '-OutputPath', $compatibilityGate) 'compatibility gate'
    Invoke-P34TestChild (Join-Path $root 'tools/Invoke-P34CoverageGate.ps1') @('-ProjectRoot', $root, '-ReportPath', $coverageReport, '-BaselinePath', $coverageBaseline, '-OutputPath', $coverageGate) 'coverage gate'

    $sourceRevision = ((& git -C $root rev-parse HEAD 2>$null) -join "`n").Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($sourceRevision)) { throw 'P3.4 CI tests could not resolve the current source revision.' }
    Invoke-P34ProvenanceBuild $sourceRevision

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
    $coverageReceipt = Get-Content -Raw -LiteralPath $coverageGate | ConvertFrom-Json
    if ([string]$coverageReceipt.inputReportIdentity.fileName -cne 'coverage-report.json') { throw 'Coverage receipt did not bind the canonical coverage-report.json filename.' }
    if ((Get-P34TestSha256 $coverageReport) -cne [string]$coverageReceipt.inputReportIdentity.sha256) { throw 'Coverage receipt hash does not match the canonical gated report.' }
    $candidateCoverage = Join-Path $firstCandidate 'reports/coverage-report.json'
    if ((Get-P34TestSha256 $candidateCoverage) -cne [string]$coverageReceipt.inputReportIdentity.sha256) { throw 'Candidate coverage report does not match the gated canonical report.' }
    if (Test-Path -LiteralPath (Join-Path $firstCandidate 'reports/coverage-baseline.json')) { throw 'Candidate retained the discovery-internal coverage-baseline.json name.' }
    Invoke-P34TestChild (Join-Path $root 'tests/P34PackageSmoke.ps1') @('-ModulePath', (Join-Path $firstCandidate 'package/Cloudflare.PowerShell')) 'candidate package smoke'

    $failedCompatibilityGate = Join-Path $temporary 'failed-compatibility-gate.json'
    $failedCompatibilityValue = Get-Content -Raw -LiteralPath $compatibilityGate | ConvertFrom-Json
    $failedCompatibilityValue.status = 'Failed'
    Write-P34TestJson $failedCompatibilityGate $failedCompatibilityValue
    Assert-P34PackageRejects 'failed-compatibility-gate' $failedCompatibilityGate $coverageGate

    $failedCoverageGate = Join-Path $temporary 'failed-coverage-gate.json'
    $failedCoverageValue = Get-Content -Raw -LiteralPath $coverageGate | ConvertFrom-Json
    $failedCoverageValue.status = 'Failed'
    Write-P34TestJson $failedCoverageGate $failedCoverageValue
    Assert-P34PackageRejects 'failed-coverage-gate' $compatibilityGate $failedCoverageGate

    $mismatchedReportHashGate = Join-Path $temporary 'mismatched-report-hash-gate.json'
    $mismatchedReportHashValue = Get-Content -Raw -LiteralPath $compatibilityGate | ConvertFrom-Json
    $mismatchedReportHashValue.inputReportIdentity.sha256 = ('0' * 64)
    Write-P34TestJson $mismatchedReportHashGate $mismatchedReportHashValue
    Assert-P34PackageRejects 'mismatched-report-hash' $mismatchedReportHashGate $coverageGate

    $mismatchedPolicyGate = Join-Path $temporary 'mismatched-policy-gate.json'
    $mismatchedPolicyValue = Get-Content -Raw -LiteralPath $compatibilityGate | ConvertFrom-Json
    $mismatchedPolicyValue.policyIdentity.sha256 = ('1' * 64)
    Write-P34TestJson $mismatchedPolicyGate $mismatchedPolicyValue
    Assert-P34PackageRejects 'mismatched-policy-identity' $mismatchedPolicyGate $coverageGate

    $mismatchedSchemaGate = Join-Path $temporary 'mismatched-schema-gate.json'
    $mismatchedSchemaValue = Get-Content -Raw -LiteralPath $compatibilityGate | ConvertFrom-Json
    $mismatchedSchemaValue.schemaIdentity.revision = ('2' * 40)
    Write-P34TestJson $mismatchedSchemaGate $mismatchedSchemaValue
    Assert-P34PackageRejects 'mismatched-schema-revision' $mismatchedSchemaGate $coverageGate

    $mismatchedFilenameGate = Join-Path $temporary 'mismatched-report-filename-gate.json'
    $mismatchedFilenameValue = Get-Content -Raw -LiteralPath $compatibilityGate | ConvertFrom-Json
    $mismatchedFilenameValue.inputReportIdentity.fileName = 'unrelated-report.json'
    Write-P34TestJson $mismatchedFilenameGate $mismatchedFilenameValue
    Assert-P34PackageRejects 'mismatched-report-filename' $mismatchedFilenameGate $coverageGate

    $mismatchedCoverageFilenameGate = Join-Path $temporary 'mismatched-coverage-report-filename-gate.json'
    $mismatchedCoverageFilenameValue = Get-Content -Raw -LiteralPath $coverageGate | ConvertFrom-Json
    $mismatchedCoverageFilenameValue.inputReportIdentity.fileName = 'coverage-baseline.json'
    Write-P34TestJson $mismatchedCoverageFilenameGate $mismatchedCoverageFilenameValue
    Assert-P34PackageRejects 'mismatched-coverage-report-filename' $compatibilityGate $mismatchedCoverageFilenameGate

    $legacyCoverageReport = Join-Path $temporary 'coverage-baseline.json'
    Copy-Item -LiteralPath $coverageReport -Destination $legacyCoverageReport -Force
    $legacyCoverageGate = Join-Path $temporary 'legacy-coverage-report-gate.json'
    $legacyCoverageGateValue = Get-Content -Raw -LiteralPath $coverageGate | ConvertFrom-Json
    $legacyCoverageGateValue.inputReportIdentity.fileName = 'coverage-baseline.json'
    $legacyCoverageGateValue.inputReportIdentity.sha256 = Get-P34TestSha256 $legacyCoverageReport
    Write-P34TestJson $legacyCoverageGate $legacyCoverageGateValue
    Assert-P34PackageRejects 'noncanonical-coverage-input' $compatibilityGate $legacyCoverageGate '' $legacyCoverageReport

    $mismatchedReceiptOldGate = Join-Path $temporary 'mismatched-receipt-old-revision-gate.json'
    $mismatchedReceiptOldValue = Get-Content -Raw -LiteralPath $compatibilityGate | ConvertFrom-Json
    $mismatchedReceiptOldValue.comparisonIdentity.oldRevision = ('1' * 40)
    Write-P34TestJson $mismatchedReceiptOldGate $mismatchedReceiptOldValue
    Assert-P34PackageRejects 'mismatched-receipt-old-revision' $mismatchedReceiptOldGate $coverageGate

    $mismatchedReceiptNewGate = Join-Path $temporary 'mismatched-receipt-new-revision-gate.json'
    $mismatchedReceiptNewValue = Get-Content -Raw -LiteralPath $compatibilityGate | ConvertFrom-Json
    $mismatchedReceiptNewValue.comparisonIdentity.newRevision = ('2' * 40)
    Write-P34TestJson $mismatchedReceiptNewGate $mismatchedReceiptNewValue
    Assert-P34PackageRejects 'mismatched-receipt-new-revision' $mismatchedReceiptNewGate $coverageGate

    $wrongPreviousReport = Get-Content -Raw -LiteralPath $compatibilityReport | ConvertFrom-Json
    $wrongPreviousRevision = '3' * 40
    $wrongPreviousReport.oldSourceRevision = $wrongPreviousRevision
    $wrongPreviousReportPath = Join-Path $temporary 'wrong-previous-revision-report.json'
    Write-P34TestJson $wrongPreviousReportPath $wrongPreviousReport
    $wrongPreviousGate = Get-Content -Raw -LiteralPath $compatibilityGate | ConvertFrom-Json
    $wrongPreviousGate.comparisonIdentity.oldRevision = $wrongPreviousRevision
    $wrongPreviousGate.inputReportIdentity.fileName = [IO.Path]::GetFileName($wrongPreviousReportPath)
    $wrongPreviousGate.inputReportIdentity.sha256 = Get-P34TestSha256 $wrongPreviousReportPath
    $wrongPreviousGatePath = Join-Path $temporary 'wrong-previous-revision-gate.json'
    Write-P34TestJson $wrongPreviousGatePath $wrongPreviousGate
    Assert-P34PackageRejects 'wrong-previous-revision' $wrongPreviousGatePath $coverageGate $wrongPreviousReportPath

    $wrongPinnedNewReport = Get-Content -Raw -LiteralPath $compatibilityReport | ConvertFrom-Json
    $wrongPinnedNewRevision = '4' * 40
    $wrongPinnedNewReport.newSourceRevision = $wrongPinnedNewRevision
    $wrongPinnedNewReportPath = Join-Path $temporary 'wrong-pinned-new-revision-report.json'
    Write-P34TestJson $wrongPinnedNewReportPath $wrongPinnedNewReport
    $wrongPinnedNewGate = Get-Content -Raw -LiteralPath $compatibilityGate | ConvertFrom-Json
    $wrongPinnedNewGate.comparisonIdentity.newRevision = $wrongPinnedNewRevision
    $wrongPinnedNewGate.inputReportIdentity.fileName = [IO.Path]::GetFileName($wrongPinnedNewReportPath)
    $wrongPinnedNewGate.inputReportIdentity.sha256 = Get-P34TestSha256 $wrongPinnedNewReportPath
    $wrongPinnedNewGatePath = Join-Path $temporary 'wrong-pinned-new-revision-gate.json'
    Write-P34TestJson $wrongPinnedNewGatePath $wrongPinnedNewGate
    Assert-P34PackageRejects 'wrong-pinned-new-revision' $wrongPinnedNewGatePath $coverageGate $wrongPinnedNewReportPath

    $staleRevision = 'a' * 40
    Invoke-P34ProvenanceBuild $staleRevision
    Assert-P34PackageRejects 'stale-assembly-provenance' $compatibilityGate $coverageGate
    Invoke-P34ProvenanceBuild $sourceRevision

    $mutatedCompatibility = Join-Path $temporary 'mutated-compatibility.json'
    $compatibilityValue = Get-Content -Raw -LiteralPath $compatibilityReport | ConvertFrom-Json
    $compatibilityValue.changes[0].newValue = 'unexpected-value'
    Write-P34TestJson $mutatedCompatibility $compatibilityValue
    Assert-P34TestChildFails (Join-Path $root 'tools/Invoke-P34CompatibilityGate.ps1') @('-ProjectRoot', $root, '-ReportPath', $mutatedCompatibility, '-OutputPath', (Join-Path $temporary 'mutated-compatibility-gate.json')) 'unexpected compatibility change rejection'

    $identityRemoved = Get-Content -Raw -LiteralPath $compatibilityReport | ConvertFrom-Json
    $identityRemoved.changes[0].PSObject.Properties.Remove('schemaName')
    Assert-P34CompatibilityRejects 'missing-identity-field' $identityRemoved

    $operationIdChanged = Get-Content -Raw -LiteralPath $compatibilityReport | ConvertFrom-Json
    (@($operationIdChanged.changes | Where-Object kind -eq 'ParameterTypeChanged')[0]).operationId = 'ChangedOperation'
    Assert-P34CompatibilityRejects 'changed-operation-id' $operationIdChanged

    $resourcePathChanged = Get-Content -Raw -LiteralPath $compatibilityReport | ConvertFrom-Json
    (@($resourcePathChanged.changes | Where-Object kind -eq 'ParameterTypeChanged')[0]).resourcePath = 'other/resource'
    Assert-P34CompatibilityRejects 'changed-resource-path' $resourcePathChanged

    $schemaNameChanged = Get-Content -Raw -LiteralPath $compatibilityReport | ConvertFrom-Json
    (@($schemaNameChanged.changes | Where-Object kind -eq 'EnumValueAdded')[0]).schemaName = 'OtherSchema'
    Assert-P34CompatibilityRejects 'changed-schema-name' $schemaNameChanged

    $impactChanged = Get-Content -Raw -LiteralPath $compatibilityReport | ConvertFrom-Json
    $impactChanged.changes[0].apiImpact = 'Behavioral'
    Assert-P34CompatibilityRejects 'changed-impact-dimension' $impactChanged

    $duplicateCompatibility = Get-Content -Raw -LiteralPath $compatibilityReport | ConvertFrom-Json
    $duplicateCompatibility.changes = @($duplicateCompatibility.changes) + $duplicateCompatibility.changes[0]
    Assert-P34CompatibilityRejects 'duplicate-report-change' $duplicateCompatibility

    $duplicatePolicy = Get-Content -Raw -LiteralPath (Join-Path $root 'build/p34-compatibility-policy.json') | ConvertFrom-Json
    $duplicatePolicy.approvedChanges = @($duplicatePolicy.approvedChanges) + $duplicatePolicy.approvedChanges[0]
    $duplicatePolicyPath = Join-Path $temporary 'duplicate-compatibility-policy.json'
    Write-P34TestJson $duplicatePolicyPath $duplicatePolicy
    Assert-P34CompatibilityRejects 'duplicate-allowlist-entry' (Get-Content -Raw -LiteralPath $compatibilityReport | ConvertFrom-Json) $duplicatePolicyPath

    $similarBreaking = Get-Content -Raw -LiteralPath $compatibilityReport | ConvertFrom-Json
    $similarBreakingChange = @($similarBreaking.changes | Where-Object kind -eq 'ParameterTypeChanged')[0]
    $similarBreakingChange.path = "$($similarBreakingChange.path).unexpected"
    Assert-P34CompatibilityRejects 'similar-nonidentical-breaking-change' $similarBreaking

    $staleAllowlist = Get-Content -Raw -LiteralPath $compatibilityReport | ConvertFrom-Json
    $staleAllowlist.changes = @($staleAllowlist.changes | Select-Object -Skip 1)
    Assert-P34CompatibilityRejects 'stale-allowlist-entry' $staleAllowlist

    $unknownImpact = Get-Content -Raw -LiteralPath $compatibilityReport | ConvertFrom-Json
    $unknownImpact.changes[0].apiImpact = 'Unknown'
    Assert-P34CompatibilityRejects 'unknown-impact' $unknownImpact

    $mutatedCoverage = Join-Path $temporary 'mutated-coverage.json'
    $coverageValue = Get-Content -Raw -LiteralPath $coverageReport | ConvertFrom-Json
    $supportedRow = @($coverageValue.operations | Where-Object classification -in @('Supported', 'SupportedWithOverride') | Select-Object -First 1)
    if ($supportedRow.Count -ne 1) { throw 'Coverage test could not find a supported baseline operation.' }
    $supportedRow[0].classification = 'NeedsManualReview'
    Write-P34TestJson $mutatedCoverage $coverageValue
    Assert-P34TestChildFails (Join-Path $root 'tools/Invoke-P34CoverageGate.ps1') @('-ProjectRoot', $root, '-ReportPath', $mutatedCoverage, '-BaselinePath', $coverageBaseline, '-OutputPath', (Join-Path $temporary 'mutated-coverage-gate.json')) 'supported-to-manual coverage regression rejection'

    $tamperedHistogram = Get-Content -Raw -LiteralPath $coverageReport | ConvertFrom-Json
    $tamperedHistogram.classificationCounts.UnsupportedProjectionCapability--
    $tamperedHistogram.classificationCounts.ExcludedByPolicy++
    Assert-P34CoverageRejects 'tampered-classification-histogram' $tamperedHistogram

    $unknownClassification = Get-Content -Raw -LiteralPath $coverageReport | ConvertFrom-Json
    $unknownClassification.operations[0].classification = 'FutureClassification'
    Assert-P34CoverageRejects 'unknown-classification' $unknownClassification

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
