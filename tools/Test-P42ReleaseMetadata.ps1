[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$RequirePinnedSchemaCheckout,
    [switch]$RequireCleanWorktree,
    [string]$CandidateRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)

function Assert-P42Metadata {
    param([bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}
function Get-P42Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    return ((Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash).ToLowerInvariant()
}
function Get-P42Json {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Label)
    Assert-P42Metadata (Test-Path -LiteralPath $Path -PathType Leaf) "$Label is missing: $Path"
    try { return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json } catch { throw "$Label is not valid JSON: $Path" }
}

try {
    $global = Get-P42Json (Join-Path $root 'global.json') 'global.json'
    Assert-P42Metadata ([string]$global.sdk.version -ceq '10.0.400') 'global.json SDK version must be 10.0.400.'
    Assert-P42Metadata ([string]$global.sdk.rollForward -ceq 'latestPatch') 'global.json rollForward must be latestPatch.'
    Assert-P42Metadata ($global.sdk.allowPrerelease -eq $false) 'global.json must disallow prerelease SDKs.'

    $props = [xml](Get-Content -Raw -LiteralPath (Join-Path $root 'Directory.Build.props'))
    $versionText = [string]$props.Project.PropertyGroup.VersionPrefix
    Assert-P42Metadata ($versionText -match '^\d+\.\d+\.\d+$') "VersionPrefix must be a stable three-part version, found '$versionText'."
    $version = [version]$versionText
    $versionString = $version.ToString(3)
    Assert-P42Metadata ([string]$props.Project.PropertyGroup.Version -ceq '$(VersionPrefix)') 'Directory.Build.props Version must derive from VersionPrefix.'
    Assert-P42Metadata ([string]$props.Project.PropertyGroup.AssemblyVersion -ceq '$(VersionPrefix).0') 'AssemblyVersion must derive from VersionPrefix.'
    Assert-P42Metadata ([string]$props.Project.PropertyGroup.FileVersion -ceq '$(VersionPrefix).0') 'FileVersion must derive from VersionPrefix.'
    Assert-P42Metadata ([string]$props.Project.PropertyGroup.RestorePackagesWithLockFile -ceq 'true') 'NuGet lock-file restore must be enabled.'

    $manifestPath = Join-Path $root 'module/Cloudflare.PowerShell/Cloudflare.PowerShell.psd1'
    $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
    Assert-P42Metadata ([string]$manifest.ModuleVersion -ceq $versionString) "ModuleVersion '$($manifest.ModuleVersion)' does not match VersionPrefix '$versionString'."
    Assert-P42Metadata (@($manifest.RequiredAssemblies | ForEach-Object { [string]$_ }) -contains 'Cloudflare.PowerShell.dll') 'Module manifest must require the package assembly.'
    $projectFiles = @(Get-ChildItem -LiteralPath $root -Recurse -Filter '*.csproj' -File)
    foreach ($projectFile in $projectFiles) {
        $project = [xml](Get-Content -Raw -LiteralPath $projectFile.FullName)
        Assert-P42Metadata (@($project.Project.PropertyGroup.TargetFramework | ForEach-Object { [string]$_ }) -contains 'net10.0') "$($projectFile.Name) must target net10.0."
        $lockPath = Join-Path $projectFile.DirectoryName 'packages.lock.json'
        $lock = Get-P42Json $lockPath "NuGet lock file for $($projectFile.Name)"
        Assert-P42Metadata ([int]$lock.version -eq 1) "NuGet lock file for $($projectFile.Name) has an unsupported schema version."
        foreach ($framework in @($lock.dependencies.PSObject.Properties | ForEach-Object Value)) {
            foreach ($package in @($framework.PSObject.Properties | ForEach-Object Value)) {
                if ([string]$package.type -ceq 'Project') { continue }
                Assert-P42Metadata (-not [string]::IsNullOrWhiteSpace([string]$package.resolved)) "NuGet lock entry in $($projectFile.Name) has no resolved version."
                Assert-P42Metadata (-not [string]::IsNullOrWhiteSpace([string]$package.contentHash)) "NuGet lock entry '$($package.resolved)' in $($projectFile.Name) has no content hash."
            }
        }
    }
    $powerShellProject = [xml](Get-Content -Raw -LiteralPath (Join-Path $root 'src/Cloudflare.PowerShell/Cloudflare.PowerShell.csproj'))
    $sma = @($powerShellProject.Project.ItemGroup.PackageReference | Where-Object { [string]$_.Include -ceq 'System.Management.Automation' }) | Select-Object -First 1
    Assert-P42Metadata ($null -ne $sma -and [string]$sma.Version -ceq '7.6.0') 'System.Management.Automation must remain pinned to 7.6.0.'

    $pin = Get-P42Json (Join-Path $root 'build/pinned-schema.json') 'pinned schema manifest'
    Assert-P42Metadata ([int]$pin.version -eq 1) 'Pinned schema manifest version must be 1.'
    foreach ($field in @('repository', 'revision', 'sourcePath', 'sourceRevision', 'sha256')) { Assert-P42Metadata (-not [string]::IsNullOrWhiteSpace([string]$pin.$field)) "Pinned schema manifest field '$field' is missing." }
    Assert-P42Metadata ([string]$pin.revision -cmatch '^[0-9a-f]{40}$') 'Pinned schema revision must be a lowercase full commit SHA.'
    Assert-P42Metadata ([string]$pin.sha256 -cmatch '^[0-9a-f]{64}$') 'Pinned schema hash must be a lowercase SHA-256.'
    Assert-P42Metadata ([string]$pin.repository -ceq 'https://github.com/cloudflare/api-schemas.git') 'Schema source repository is not the approved upstream.'

    $sourceRevision = ((& git -C $root rev-parse HEAD 2>$null) -join "`n").Trim()
    Assert-P42Metadata ($LASTEXITCODE -eq 0 -and $sourceRevision -cmatch '^[0-9a-f]{40}$') 'Current source revision is not a canonical Git SHA.'
    if ($RequireCleanWorktree) {
        $status = @(& git -C $root status --porcelain --untracked-files=all)
        Assert-P42Metadata ($status.Count -eq 0) "Release metadata requires a clean worktree; found $($status.Count) tracked/untracked change row(s)."
    }
    if ($RequirePinnedSchemaCheckout) {
        & pwsh -NoLogo -NoProfile -File (Join-Path $root 'tools/Initialize-P34Schema.ps1') -ProjectRoot $root -VerifyOnly | Out-Host
        Assert-P42Metadata ($LASTEXITCODE -eq 0) 'Pinned schema checkout verification failed.'
    }

    if (-not [string]::IsNullOrWhiteSpace($CandidateRoot)) {
        $candidate = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $CandidateRoot).Path)
        $candidateManifest = Get-P42Json (Join-Path $candidate 'candidate-manifest.json') 'candidate manifest'
        Assert-P42Metadata ([string]$candidateManifest.packageVersion -ceq $versionString) 'Candidate package version does not match VersionPrefix.'
        Assert-P42Metadata ([string]$candidateManifest.sourceRevision -ceq $sourceRevision) 'Candidate source revision does not match HEAD.'
        Assert-P42Metadata ((Get-P42Sha256 (Join-Path $candidate ([string]$candidateManifest.archivePath))) -ceq [string]$candidateManifest.archiveSha256) 'Candidate archive hash does not match its provenance manifest.'
    }
    Write-Output "PASS P4.2 release metadata version=$versionString sourceRevision=$sourceRevision"
}
catch {
    Write-Error "P4.2 release metadata validation failed: $($_.Exception.Message)"
    exit 1
}
