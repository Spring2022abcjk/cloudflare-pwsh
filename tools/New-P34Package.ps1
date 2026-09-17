[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot = (Join-Path $ProjectRoot 'artifacts/p34-candidate'),
    [string]$Configuration = 'Release',
    [Parameter(Mandatory)][string]$CompatibilityReportPath,
    [Parameter(Mandatory)][string]$CompatibilityGatePath,
    [Parameter(Mandatory)][string]$CoverageJsonPath,
    [Parameter(Mandatory)][string]$CoverageMarkdownPath,
    [Parameter(Mandatory)][string]$CoverageGatePath,
    [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
function Resolve-P34PackagePath {
    param([Parameter(Mandatory)][string]$Path)
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $root $Path))
}
function Write-P34Utf8CrLf {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content)
    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
    [IO.File]::WriteAllText($Path, $normalized, [Text.UTF8Encoding]::new($false))
}
function Write-P34Json {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value)
    Write-P34Utf8CrLf $Path ($Value | ConvertTo-Json -Depth 30)
}
function Get-P34Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    return ((Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash).ToLowerInvariant()
}
function Read-P34PackageJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label is missing: $Path" }
    try { return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json) } catch { throw "$Label is not valid JSON: $Path" }
}
function Get-P34ObjectProperty {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Label)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) { throw "$Label is missing '$Name'." }
    return $Object.PSObject.Properties[$Name].Value
}
function Get-P34CurrentSourceRevision {
    $revision = ((& git -C $root rev-parse HEAD 2>$null) -join "`n").Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($revision)) { throw 'Could not resolve the current Git source revision.' }
    return $revision
}
function Assert-P34GitRevision {
    param([Parameter(Mandatory)][string]$Value, [Parameter(Mandatory)][string]$Label)
    if ($Value -cnotmatch '^[0-9a-f]{40}$') { throw "$Label is not a canonical lowercase Git SHA-1 revision: '$Value'." }
    return $Value
}
function Assert-P34GateReceipt {
    param(
        [Parameter(Mandatory)][string]$GatePath,
        [Parameter(Mandatory)][string]$ReportPath,
        [Parameter(Mandatory)][string]$PolicyPath,
        [Parameter(Mandatory)][string]$ExpectedGateName,
        [Parameter(Mandatory)][string]$ExpectedGateType,
        [Parameter(Mandatory)]$SchemaManifest
    )
    $gate = Read-P34PackageJson $GatePath "$ExpectedGateType gate receipt"
    $report = Read-P34PackageJson $ReportPath "$ExpectedGateType input report"
    if ([int](Get-P34ObjectProperty $gate 'schemaVersion' "$ExpectedGateType gate receipt") -ne 1 -or
        [string](Get-P34ObjectProperty $gate 'gateName' "$ExpectedGateType gate receipt") -cne $ExpectedGateName -or
        [string](Get-P34ObjectProperty $gate 'gateType' "$ExpectedGateType gate receipt") -cne $ExpectedGateType) {
        throw "$ExpectedGateType gate receipt has an invalid gate schema identity."
    }
    if ([string](Get-P34ObjectProperty $gate 'status' "$ExpectedGateType gate receipt") -cne 'Passed') {
        throw "$ExpectedGateType gate receipt is not Passed."
    }
    $violations = Get-P34ObjectProperty $gate 'violations' "$ExpectedGateType gate receipt"
    if (@($violations).Count -ne 0) { throw "$ExpectedGateType gate receipt contains violations despite Passed status." }

    $policyIdentity = Get-P34ObjectProperty $gate 'policyIdentity' "$ExpectedGateType gate receipt"
    $expectedPolicyPath = [IO.Path]::GetRelativePath($root, $PolicyPath).Replace('\', '/')
    if ([string](Get-P34ObjectProperty $policyIdentity 'path' "$ExpectedGateType policy identity") -cne $expectedPolicyPath -or
        [string](Get-P34ObjectProperty $policyIdentity 'sha256' "$ExpectedGateType policy identity") -cne (Get-P34Sha256 $PolicyPath)) {
        throw "$ExpectedGateType gate policy identity does not match the canonical checked-in policy."
    }

    $inputIdentity = Get-P34ObjectProperty $gate 'inputReportIdentity' "$ExpectedGateType gate receipt"
    $expectedReportHash = Get-P34Sha256 $ReportPath
    $expectedReportFileName = [IO.Path]::GetFileName($ReportPath)
    if ([string](Get-P34ObjectProperty $inputIdentity 'fileName' "$ExpectedGateType input report identity") -cne $expectedReportFileName -or
        [string](Get-P34ObjectProperty $inputIdentity 'sha256' "$ExpectedGateType input report identity") -cne $expectedReportHash) {
        throw "$ExpectedGateType gate input report identity does not match the report being packaged."
    }

    $schemaIdentity = Get-P34ObjectProperty $gate 'schemaIdentity' "$ExpectedGateType gate receipt"
    foreach ($field in @('revision', 'sourceRevision', 'sourcePath', 'sha256')) {
        if ([string](Get-P34ObjectProperty $schemaIdentity $field "$ExpectedGateType schema identity") -cne [string]$SchemaManifest.$field) {
            throw "$ExpectedGateType gate schema identity field '$field' does not match the pinned schema manifest."
        }
    }
    if ($ExpectedGateType -ceq 'Compatibility') {
        $comparisonIdentity = Get-P34ObjectProperty $gate 'comparisonIdentity' "$ExpectedGateType gate receipt"
        $receiptOldRevision = Assert-P34GitRevision -Value ([string](Get-P34ObjectProperty $comparisonIdentity 'oldRevision' "$ExpectedGateType comparison identity")) -Label "$ExpectedGateType receipt oldRevision"
        $receiptNewRevision = Assert-P34GitRevision -Value ([string](Get-P34ObjectProperty $comparisonIdentity 'newRevision' "$ExpectedGateType comparison identity")) -Label "$ExpectedGateType receipt newRevision"
        $reportOldRevision = Assert-P34GitRevision -Value ([string](Get-P34ObjectProperty $report 'oldSourceRevision' "$ExpectedGateType input report")) -Label "$ExpectedGateType report oldSourceRevision"
        $reportNewRevision = Assert-P34GitRevision -Value ([string](Get-P34ObjectProperty $report 'newSourceRevision' "$ExpectedGateType input report")) -Label "$ExpectedGateType report newSourceRevision"
        if ($receiptOldRevision -ceq $receiptNewRevision) { throw "$ExpectedGateType comparison revisions must differ." }
        if ($receiptOldRevision -cne $reportOldRevision -or $receiptNewRevision -cne $reportNewRevision) { throw "$ExpectedGateType receipt comparison identity does not match the input report revisions." }
        $previousFixturePath = Join-Path $root 'fixtures/p2.4/openapi-previous-revision.json'
        $previousFixture = Read-P34PackageJson $previousFixturePath 'P2.4 previous-revision fixture'
        $fixtureOldRevision = Assert-P34GitRevision -Value ([string](Get-P34ObjectProperty $previousFixture 'previousRevision' 'P2.4 previous-revision fixture')) -Label 'P2.4 previous-revision fixture previousRevision'
        $fixtureCurrentRevision = Assert-P34GitRevision -Value ([string](Get-P34ObjectProperty $previousFixture 'currentRevision' 'P2.4 previous-revision fixture')) -Label 'P2.4 previous-revision fixture currentRevision'
        if ($fixtureCurrentRevision -cne [string]$SchemaManifest.revision) { throw 'P2.4 previous-revision fixture currentRevision does not match the pinned schema revision.' }
        if ($reportOldRevision -cne $fixtureOldRevision) { throw 'Compatibility input report oldSourceRevision does not match the approved previous-revision fixture.' }
        if ([string](Get-P34ObjectProperty $report 'stage' "$ExpectedGateType input report") -cne 'P2.4' -or
            $reportNewRevision -cne [string]$SchemaManifest.revision) {
            throw 'Compatibility input report does not match the pinned schema revision.'
        }
    } else {
        if ([string](Get-P34ObjectProperty $report 'stage' "$ExpectedGateType input report") -cne 'P3.3' -or
            [string](Get-P34ObjectProperty $report 'sourceRevision' "$ExpectedGateType input report") -cne [string]$SchemaManifest.sourceRevision -or
            [string](Get-P34ObjectProperty $report 'sourcePath' "$ExpectedGateType input report") -cne ('ref/api-schemas/' + [string]$SchemaManifest.sourcePath)) {
            throw 'Coverage input report does not match the pinned schema source revision/path.'
        }
        $sourceIdentity = Get-P34ObjectProperty (Get-P34ObjectProperty $report 'inputIdentity' "$ExpectedGateType input report") 'source' "$ExpectedGateType report source identity"
        foreach ($field in @('path', 'revision', 'sha256')) {
            $expected = if ($field -ceq 'path') { [string]$report.sourcePath } elseif ($field -ceq 'revision') { [string]$SchemaManifest.sourceRevision } else { [string]$SchemaManifest.sha256 }
            if ([string](Get-P34ObjectProperty $sourceIdentity $field "$ExpectedGateType report source identity") -cne $expected) {
                throw "Coverage report source identity field '$field' does not match the pinned schema."
            }
        }
    }
    return $gate
}
function Get-P34AssemblyProvenance {
    param([Parameter(Mandatory)][string]$Path)
    try { $assembly = [Reflection.Assembly]::LoadFile($Path) } catch { throw "Could not read assembly metadata: $Path" }
    $informational = @($assembly.GetCustomAttributes($false) | Where-Object { $_ -is [Reflection.AssemblyInformationalVersionAttribute] })
    if ($informational.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$informational[0].InformationalVersion)) { throw 'Assembly is missing a unique informational-version provenance value.' }
    $framework = @($assembly.GetCustomAttributes($false) | Where-Object { $_ -is [Runtime.Versioning.TargetFrameworkAttribute] })
    if ($framework.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$framework[0].FrameworkName)) { throw 'Assembly is missing a unique target-framework metadata value.' }
    return [ordered]@{ informationalVersion = [string]$informational[0].InformationalVersion; targetFramework = [string]$framework[0].FrameworkName }
}

$output = Resolve-P34PackagePath $OutputRoot
if ((Test-Path -LiteralPath $output -PathType Container) -and @(Get-ChildItem -LiteralPath $output -Force).Count -ne 0) {
    throw "Package output directory must be absent or empty so stale candidate files cannot be carried forward: $output"
}

$versionPropsPath = Join-Path $root 'Directory.Build.props'
if (-not (Test-Path -LiteralPath $versionPropsPath -PathType Leaf)) { throw "P3.4 version source is missing: $versionPropsPath" }
$versionProps = [xml](Get-Content -Raw -LiteralPath $versionPropsPath)
$versionText = [string]$versionProps.Project.PropertyGroup.VersionPrefix
try { $version = [version]$versionText } catch { throw "P3.4 version source is not a valid version: $versionText" }
if ($version.Revision -ne -1 -or $version.Build -lt 0) { throw "P3.4 package version must be a stable three-part version: $versionText" }
$versionString = $version.ToString(3)

$projectPath = Join-Path $root 'src/Cloudflare.PowerShell/Cloudflare.PowerShell.csproj'
$projectXml = [xml](Get-Content -Raw -LiteralPath $projectPath)
$targetFramework = [string]$projectXml.Project.PropertyGroup.TargetFramework
if ($targetFramework -cne 'net10.0') { throw "P3.4 package target framework must be net10.0; found '$targetFramework'." }
$sourceRevision = Assert-P34GitRevision -Value (Get-P34CurrentSourceRevision) -Label 'Current source revision'
$buildOutput = Join-Path $root "src/Cloudflare.PowerShell/bin/$Configuration/$targetFramework/Cloudflare.PowerShell.dll"
if (-not $SkipBuild) {
    & dotnet build $projectPath --configuration $Configuration --nologo "/p:P34SourceRevision=$sourceRevision" | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "P3.4 package build failed with exit code $LASTEXITCODE." }
}
if (-not (Test-Path -LiteralPath $buildOutput -PathType Leaf)) { throw "P3.4 package assembly is missing: $buildOutput" }
$assemblyName = [Reflection.AssemblyName]::GetAssemblyName($buildOutput)
$expectedAssemblyVersion = [version]($versionString + '.0')
if ($assemblyName.Version -ne $expectedAssemblyVersion) { throw "Assembly version '$($assemblyName.Version)' does not match source version '$expectedAssemblyVersion'." }
$assemblyProvenance = Get-P34AssemblyProvenance $buildOutput
$expectedInformationalVersion = "$versionString+source.$sourceRevision"
if ($assemblyProvenance.informationalVersion -cne $expectedInformationalVersion) { throw "Assembly provenance '$($assemblyProvenance.informationalVersion)' does not match current source revision '$sourceRevision'." }
if ($assemblyProvenance.targetFramework -cne '.NETCoreApp,Version=v10.0') { throw "Assembly target framework '$($assemblyProvenance.targetFramework)' is not net10.0." }

$pinnedSchemaPath = Join-Path $root 'build/pinned-schema.json'
$pinnedSchema = Read-P34PackageJson $pinnedSchemaPath 'P3.4 pinned schema manifest'
if ([int](Get-P34ObjectProperty $pinnedSchema 'version' 'P3.4 pinned schema manifest') -ne 1) { throw 'P3.4 pinned schema manifest version is unsupported.' }
$compatibilityPolicyPath = Join-Path $root 'build/p34-compatibility-policy.json'
$coveragePolicyPath = Join-Path $root 'build/p34-coverage-policy.json'
$compatibilityReport = Resolve-P34PackagePath $CompatibilityReportPath
$compatibilityGate = Resolve-P34PackagePath $CompatibilityGatePath
$coverageReport = Resolve-P34PackagePath $CoverageJsonPath
$coverageGate = Resolve-P34PackagePath $CoverageGatePath
Assert-P34GateReceipt $compatibilityGate $compatibilityReport $compatibilityPolicyPath 'P3.4.CompatibilityGate' 'Compatibility' $pinnedSchema | Out-Null
Assert-P34GateReceipt $coverageGate $coverageReport $coveragePolicyPath 'P3.4.CoverageGate' 'Coverage' $pinnedSchema | Out-Null

New-Item -ItemType Directory -Force -Path $output | Out-Null

$manifestPath = Join-Path $root 'module/Cloudflare.PowerShell/Cloudflare.PowerShell.psd1'
$manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
if ([string]$manifest.ModuleVersion -cne $versionString) { throw "Module manifest version '$($manifest.ModuleVersion)' does not match source version '$versionString'." }
if (@($manifest.RequiredAssemblies | ForEach-Object { [string]$_ }) -notcontains 'Cloudflare.PowerShell.dll') { throw 'Module manifest does not require Cloudflare.PowerShell.dll.' }

$moduleName = 'Cloudflare.PowerShell'
$moduleStage = Join-Path $output "package/$moduleName"
$reportStage = Join-Path $output 'reports'
New-Item -ItemType Directory -Force -Path $moduleStage,$reportStage | Out-Null
$moduleSources = @(
    @{ Source = $manifestPath; Name = 'Cloudflare.PowerShell.psd1' },
    @{ Source = (Join-Path $root 'module/Cloudflare.PowerShell/Cloudflare.PowerShell.psm1'); Name = 'Cloudflare.PowerShell.psm1' },
    @{ Source = (Join-Path $root 'module/Cloudflare.PowerShell/Cloudflare.PowerShell-help.xml'); Name = 'Cloudflare.PowerShell-help.xml' },
    @{ Source = $buildOutput; Name = 'Cloudflare.PowerShell.dll' }
)
foreach ($item in $moduleSources) {
    if (-not (Test-Path -LiteralPath $item.Source -PathType Leaf)) { throw "Required package input is missing: $($item.Source)" }
    Copy-Item -LiteralPath $item.Source -Destination (Join-Path $moduleStage $item.Name) -Force
}
$expectedModuleFiles = @($moduleSources | ForEach-Object Name | Sort-Object)
$actualModuleFiles = @(Get-ChildItem -LiteralPath $moduleStage -File | ForEach-Object Name | Sort-Object)
if (($actualModuleFiles -join '|') -cne ($expectedModuleFiles -join '|')) { throw "Package module content is not exact. Expected '$($expectedModuleFiles -join ',')', actual '$($actualModuleFiles -join ',')'." }

$reportInputs = @(
    @{ Source = $compatibilityReport; Name = 'compatibility-report.json' },
    @{ Source = $compatibilityGate; Name = 'compatibility-gate.json' },
    @{ Source = $coverageReport; Name = 'coverage-baseline.json' },
    @{ Source = (Resolve-P34PackagePath $CoverageMarkdownPath); Name = 'coverage-baseline.md' },
    @{ Source = $coverageGate; Name = 'coverage-gate.json' }
)
foreach ($item in $reportInputs) {
    if (-not (Test-Path -LiteralPath $item.Source -PathType Leaf)) { throw "Required candidate report is missing: $($item.Source)" }
    Copy-Item -LiteralPath $item.Source -Destination (Join-Path $reportStage $item.Name) -Force
}

$summary = [ordered]@{
    schemaVersion = 1
    stage = 'P3.4'
    status = 'Passed'
    packageName = $moduleName
    packageVersion = $versionString
    sourceRevision = $sourceRevision
    assemblyInformationalVersion = [string]$assemblyProvenance.informationalVersion
    targetFramework = $targetFramework
    schemaIdentity = [ordered]@{
        revision = [string]$pinnedSchema.revision
        sourceRevision = [string]$pinnedSchema.sourceRevision
        sourcePath = [string]$pinnedSchema.sourcePath
        sha256 = [string]$pinnedSchema.sha256
    }
    gates = @('Build', 'DeterministicGeneration', 'UnitRuntime', 'Regression', 'Compatibility', 'Coverage')
    moduleFileCount = $actualModuleFiles.Count
    reportFiles = @($reportInputs | ForEach-Object {
        $target = Join-Path $reportStage $_.Name
        [ordered]@{ path = "reports/$($_.Name)"; sha256 = Get-P34Sha256 $target; length = (Get-Item -LiteralPath $target).Length }
    })
}
$summaryPath = Join-Path $output 'build-test-summary.json'
Write-P34Json $summaryPath $summary

Add-Type -AssemblyName System.IO.Compression
$archivePath = Join-Path $output "$moduleName.$versionString.zip"
$archive = [IO.Compression.ZipArchive]::new([IO.File]::Open($archivePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None), [IO.Compression.ZipArchiveMode]::Create, $false)
try {
    $fixedTime = [DateTimeOffset]::new([DateTime]::SpecifyKind([DateTime]'1980-01-01T00:00:00', [DateTimeKind]::Utc))
    foreach ($file in @(Get-ChildItem -LiteralPath $moduleStage -File | Sort-Object Name)) {
        $entry = $archive.CreateEntry("$moduleName/$($file.Name)", [IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = $fixedTime
        $input = [IO.File]::OpenRead($file.FullName)
        $entryStream = $entry.Open()
        try { $input.CopyTo($entryStream) } finally { $entryStream.Dispose(); $input.Dispose() }
    }
} finally { $archive.Dispose() }

$manifestOutput = [ordered]@{
    schemaVersion = 1
    stage = 'P3.4'
    status = 'Candidate'
    packageName = $moduleName
    packageVersion = $versionString
    sourceRevision = $sourceRevision
    assemblyInformationalVersion = [string]$assemblyProvenance.informationalVersion
    targetFramework = $targetFramework
    versionSource = 'Directory.Build.props:VersionPrefix'
    schemaIdentity = [ordered]@{
        revision = [string]$pinnedSchema.revision
        sourceRevision = [string]$pinnedSchema.sourceRevision
        sourcePath = [string]$pinnedSchema.sourcePath
        sha256 = [string]$pinnedSchema.sha256
    }
    modulePath = 'package/Cloudflare.PowerShell'
    archivePath = "$moduleName.$versionString.zip"
    archiveSha256 = Get-P34Sha256 $archivePath
    moduleFiles = @($moduleSources | Sort-Object Name | ForEach-Object {
        $target = Join-Path $moduleStage $_.Name
        [ordered]@{ path = "package/$moduleName/$($_.Name)"; sha256 = Get-P34Sha256 $target; length = (Get-Item -LiteralPath $target).Length }
    })
    gateReceipts = [ordered]@{
        compatibility = [ordered]@{
            path = 'reports/compatibility-gate.json'
            sha256 = Get-P34Sha256 (Join-Path $reportStage 'compatibility-gate.json')
            inputReportSha256 = Get-P34Sha256 (Join-Path $reportStage 'compatibility-report.json')
        }
        coverage = [ordered]@{
            path = 'reports/coverage-gate.json'
            sha256 = Get-P34Sha256 (Join-Path $reportStage 'coverage-gate.json')
            inputReportSha256 = Get-P34Sha256 (Join-Path $reportStage 'coverage-baseline.json')
        }
    }
    reportsPath = 'reports'
    buildTestSummaryPath = 'build-test-summary.json'
}
$candidateManifestPath = Join-Path $output 'candidate-manifest.json'
Write-P34Json $candidateManifestPath $manifestOutput
Write-Output "PASS P3.4 package candidate version=$versionString moduleFiles=$($actualModuleFiles.Count) archive=$archivePath"
Write-Output "P3.4 package candidate root: $output"
