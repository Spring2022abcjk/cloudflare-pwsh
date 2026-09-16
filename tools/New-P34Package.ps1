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

$output = Resolve-P34PackagePath $OutputRoot
if ((Test-Path -LiteralPath $output -PathType Container) -and @(Get-ChildItem -LiteralPath $output -Force).Count -ne 0) {
    throw "Package output directory must be absent or empty so stale candidate files cannot be carried forward: $output"
}
New-Item -ItemType Directory -Force -Path $output | Out-Null

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
$buildOutput = Join-Path $root "src/Cloudflare.PowerShell/bin/$Configuration/$targetFramework/Cloudflare.PowerShell.dll"
if (-not $SkipBuild) {
    & dotnet build $projectPath --configuration $Configuration --nologo | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "P3.4 package build failed with exit code $LASTEXITCODE." }
}
if (-not (Test-Path -LiteralPath $buildOutput -PathType Leaf)) { throw "P3.4 package assembly is missing: $buildOutput" }
$assemblyName = [Reflection.AssemblyName]::GetAssemblyName($buildOutput)
$expectedAssemblyVersion = [version]($versionString + '.0')
if ($assemblyName.Version -ne $expectedAssemblyVersion) { throw "Assembly version '$($assemblyName.Version)' does not match source version '$expectedAssemblyVersion'." }

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
    @{ Source = (Resolve-P34PackagePath $CompatibilityReportPath); Name = 'compatibility-report.json' },
    @{ Source = (Resolve-P34PackagePath $CompatibilityGatePath); Name = 'compatibility-gate.json' },
    @{ Source = (Resolve-P34PackagePath $CoverageJsonPath); Name = 'coverage-baseline.json' },
    @{ Source = (Resolve-P34PackagePath $CoverageMarkdownPath); Name = 'coverage-baseline.md' },
    @{ Source = (Resolve-P34PackagePath $CoverageGatePath); Name = 'coverage-gate.json' }
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
    targetFramework = $targetFramework
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
    targetFramework = $targetFramework
    versionSource = 'Directory.Build.props:VersionPrefix'
    modulePath = 'package/Cloudflare.PowerShell'
    archivePath = "$moduleName.$versionString.zip"
    archiveSha256 = Get-P34Sha256 $archivePath
    moduleFiles = @($moduleSources | Sort-Object Name | ForEach-Object {
        $target = Join-Path $moduleStage $_.Name
        [ordered]@{ path = "package/$moduleName/$($_.Name)"; sha256 = Get-P34Sha256 $target; length = (Get-Item -LiteralPath $target).Length }
    })
    reportsPath = 'reports'
    buildTestSummaryPath = 'build-test-summary.json'
}
$candidateManifestPath = Join-Path $output 'candidate-manifest.json'
Write-P34Json $candidateManifestPath $manifestOutput
Write-Output "PASS P3.4 package candidate version=$versionString moduleFiles=$($actualModuleFiles.Count) archive=$archivePath"
Write-Output "P3.4 package candidate root: $output"
