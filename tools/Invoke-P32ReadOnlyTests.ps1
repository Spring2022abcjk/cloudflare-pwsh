[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p32-readonly-' + [guid]::NewGuid().ToString('N'))
$initialStatus = $null
$failure = $null

$stagingLibrary = Join-Path $PSScriptRoot 'ReadOnlyStaging.ps1'
if (-not (Test-Path -LiteralPath $stagingLibrary -PathType Leaf)) { throw "Read-only staging helper is missing: $stagingLibrary" }
. $stagingLibrary -Library
. (Join-Path $PSScriptRoot 'P32Hash.ps1')

function Get-WorktreeStatus {
    $lines = @(& git -C $projectRoot status --short)
    if ($LASTEXITCODE -ne 0) { throw 'Could not read the repository worktree status.' }
    if ($lines.Count -eq 0) { return '' }
    return ($lines | ForEach-Object { [string]$_ }) -join "`n"
}

function Write-Evidence {
    param([Parameter(Mandatory)][string]$Category, [Parameter(Mandatory)][string]$Message)
    Write-Output "[$Category] $Message"
}

function Invoke-PwshChecked {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][hashtable]$Parameters,
        [Parameter(Mandatory)][string]$Label
    )
    $arguments = @('-NoLogo', '-NoProfile', '-File', $ScriptPath)
    foreach ($key in @($Parameters.Keys | Sort-Object)) {
        $value = $Parameters[$key]
        if ($null -eq $value) { continue }
        $arguments += "-$key"
        $arguments += [string]$value
    }
    & pwsh @arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE." }
}

function Get-RequiredSourceFiles {
    param([Parameter(Mandatory)][string]$RelativeRoot)
    $sourceRoot = Join-Path $projectRoot $RelativeRoot
    if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) { throw "Required source root is missing: $sourceRoot" }
    foreach ($file in @(Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force)) {
        $relative = ([IO.Path]::GetRelativePath($sourceRoot, $file.FullName)).Replace('\', '/')
        $parts = $relative -split '/'
        if (@($parts | Where-Object { $_ -in @('bin', 'obj', '.git', '.svn', '.hg', '.bzr', 'cache', 'caches', 'logs', 'log', 'temp', 'tmp') }).Count -gt 0) { continue }
        if ($file.Extension -in @('.cs', '.csproj')) { Join-Path $RelativeRoot $relative }
    }
}

function Get-P32RequiredInputPaths {
    $paths = [Collections.Generic.List[string]]::new()
    foreach ($path in @(
        'Cloudflare.P1.sln',
        'artifacts/generated-normalized/document.json',
        'artifacts/p2.3/projection/zones.json',
        'experiments/p2.3/Cloudflare.P23.GeneratedCmdlet/Cloudflare.P23.GeneratedCmdlet.csproj',
        'fixtures/dns-records/create.json',
        'fixtures/dns-records/delete.json',
        'fixtures/dns-records/edit.json',
        'fixtures/dns-records/get.json',
        'fixtures/dns-records/list.json',
        'fixtures/dns-records/schemas.json',
        'fixtures/dns-records/update.json',
        'fixtures/p2.1/ai-search-jobs/document.json',
        'fixtures/p2.1/ai-search-jobs/operations/ai-search-namespace-instance-change-job-status.json',
        'fixtures/p2.1/ai-search-jobs/operations/ai-search-namespace-instance-create-job.json',
        'fixtures/p2.1/ai-search-jobs/operations/ai-search-namespace-instance-get-job.json',
        'fixtures/p2.1/ai-search-jobs/operations/ai-search-namespace-instance-list-jobs.json',
        'fixtures/p2.1/d1-database/document.json',
        'fixtures/p2.1/d1-database/operations/d1-create-database.json',
        'fixtures/p2.1/d1-database/operations/d1-delete-database.json',
        'fixtures/p2.1/d1-database/operations/d1-get-database.json',
        'fixtures/p2.1/d1-database/operations/d1-list-databases.json',
        'fixtures/p2.1/d1-database/operations/d1-update-database.json',
        'fixtures/p2.1/zones/document.json',
        'fixtures/p2.1/zones/operations/zones-0-delete.json',
        'fixtures/p2.1/zones/operations/zones-0-get.json',
        'fixtures/p2.1/zones/operations/zones-0-patch.json',
        'fixtures/p2.1/zones/operations/zones-get.json',
        'fixtures/p2.1/zones/operations/zones-post.json',
        'fixtures/p2.2/ai-search-download/document.json',
        'fixtures/p2.2/ai-search-download/operations/ai-search-namespace-instance-get-item-content.json',
        'fixtures/p2.2/ai-search-upload/document.json',
        'fixtures/p2.2/ai-search-upload/operations/ai-search-namespace-instance-upload-item.json',
        'fixtures/p2.2/dns-export/document.json',
        'fixtures/p2.2/dns-export/operations/dns-records-for-a-zone-export-dns-records.json',
        'fixtures/p2.2/dns-import/document.json',
        'fixtures/p2.2/dns-import/operations/dns-records-for-a-zone-import-dns-records.json',
        'fixtures/p2.4/openapi-previous-revision.json',
        'module/Cloudflare.PowerShell/Cloudflare.PowerShell-help.xml',
        'module/Cloudflare.PowerShell/Cloudflare.PowerShell.psd1',
        'module/Cloudflare.PowerShell/Cloudflare.PowerShell.psm1',
        'overrides/api-corrections.json',
        'overrides/powershell-projection.json',
        'overrides/powershell-p23-projection.json',
        'overrides/powershell-p32-projection.json',
        'tests/fixtures/openapi-mini.json',
        'tests/golden/CfDnsRecordModels.cs',
        'tests/golden/CfDnsRecordOperations.cs',
        'tests/golden/Projection_Get_CfDnsRecord.cs',
        'tests/golden/Projection_New_CfDnsRecord.cs',
        'tests/golden/Projection_Remove_CfDnsRecord.cs',
        'tests/golden/Projection_Set_CfDnsRecord.cs',
        'tests/golden/p2.1/ai-search-jobs-semantic.json',
        'tests/golden/p2.1/ai-search-jobs.json',
        'tests/golden/p2.1/d1-database-semantic.json',
        'tests/golden/p2.1/d1-database.json',
        'tests/golden/p2.1/P21_ai_search_jobsProjection.cs',
        'tests/golden/p2.1/P21_d1_databaseProjection.cs',
        'tests/golden/p2.1/P21_zonesProjection.cs',
        'tests/golden/p2.1/zones-semantic.json',
        'tests/golden/p2.1/zones.json',
        'tests/golden/p2.2/ai-search-download-semantic.json',
        'tests/golden/p2.2/ai-search-upload-semantic.json',
        'tests/golden/p2.2/dns-export-semantic.json',
        'tests/golden/p2.2/dns-import-semantic.json',
        'tests/ModuleSmoke.ps1',
        'tests/P23Projection.Tests.ps1',
        'tests/P32Projection.Tests.ps1',
        'tests/P32Smoke.ps1',
        'tests/ProjectionModel.Tests.ps1',
        'tools/Generate-DnsSource.ps1',
        'tools/Generate-P32Source.ps1',
        'tools/Invoke-P1Tests.ps1',
        'tools/Invoke-P22Tests.ps1',
        'tools/Invoke-P23Tests.ps1',
        'tools/Invoke-P24Tests.ps1',
        'tools/Invoke-P2Tests.ps1',
        'tools/P32Hash.ps1',
        'tools/Project-P21Normalized.ps1',
        'tools/Project-P23Projection.ps1',
        'tools/Project-P32Projection.ps1',
        'tools/ReadOnlyStaging.ps1',
        'tools/templates/P32RepresentativeCmdlets.cs.tmpl'
    )) { $paths.Add($path) }
    foreach ($root in @('src', 'tests')) {
        foreach ($path in @(Get-RequiredSourceFiles -RelativeRoot $root)) { $paths.Add($path) }
    }
    $paths.Add('ref/api-schemas/openapi.json')
    return @($paths | Sort-Object -Unique)
}

function Copy-IsolatedProject {
    param([Parameter(Mandatory)][string]$Destination)
    $requiredPaths = @(Get-P32RequiredInputPaths)
    Copy-ReadOnlyStagingFiles -SourceRoot $projectRoot -DestinationRoot $Destination -RelativePaths $requiredPaths
    $inventory = @(Assert-ReadOnlyStagingInputContract -Root $Destination -ExpectedRelativePaths $requiredPaths)
    Write-Evidence 'staging' "PASS explicit P3.2 input allowlist; files=$($inventory.Count), bytes=$(($inventory | Measure-Object -Property Length -Sum).Sum); no VCS/build/cache/log/temp inputs."
}

function Assert-IsolatedHashParity {
    param([Parameter(Mandatory)][string[]]$RelativePaths)
    foreach ($relativePath in $RelativePaths) {
        $expectedPath = Join-Path $projectRoot $relativePath
        $actualPath = Join-Path $temporaryRoot $relativePath
        if (-not (Test-Path -LiteralPath $expectedPath -PathType Leaf)) { throw "Expected reproducible file is missing: $expectedPath" }
        if (-not (Test-Path -LiteralPath $actualPath -PathType Leaf)) { throw "Isolated reproducible file is missing: $actualPath" }
        $expectedHash = Get-P32PortableFileHash -Path $expectedPath
        $actualHash = Get-P32PortableFileHash -Path $actualPath
        if ($expectedHash -cne $actualHash) { throw "Isolated reproduction hash drifted for '$relativePath'. Expected '$expectedHash', actual '$actualHash'." }
    }
}

try {
    $initialStatus = Get-WorktreeStatus
    $null = New-Item -ItemType Directory -Path $temporaryRoot -Force
    Copy-IsolatedProject $temporaryRoot

    $dnsGenerator = Join-Path $temporaryRoot 'tools/Generate-DnsSource.ps1'
    $projector = Join-Path $temporaryRoot 'tools/Project-P32Projection.ps1'
    $generator = Join-Path $temporaryRoot 'tools/Generate-P32Source.ps1'
    $projectionTests = Join-Path $temporaryRoot 'tests/P32Projection.Tests.ps1'
    $smoke = Join-Path $temporaryRoot 'tests/P32Smoke.ps1'
    $regression = Join-Path $temporaryRoot 'tools/Invoke-P24Tests.ps1'
    $artifactPath = Join-Path $temporaryRoot 'artifacts/p3.2/CmdletModel.json'
    $sourcePath = Join-Path $temporaryRoot 'src/Cloudflare.PowerShell/Generated/Cmdlets/P32RepresentativeCmdlets.cs'
    $dnsRuntimePath = Join-Path $temporaryRoot 'src/Cloudflare.PowerShell/Generated/Metadata/CfDnsRecordRuntimeMetadata.cs'
    $zoneRuntimePath = Join-Path $temporaryRoot 'src/Cloudflare.PowerShell/Generated/Metadata/CfZoneRuntimeMetadata.cs'
    $templatePath = Join-Path $temporaryRoot 'tools/templates/P32RepresentativeCmdlets.cs.tmpl'
    $generatedRoot = Join-Path $temporaryRoot 'src/Cloudflare.PowerShell/Generated'

    Invoke-PwshChecked $dnsGenerator @{
        ProjectRoot = $temporaryRoot
        FixtureRoot = (Join-Path $temporaryRoot 'fixtures/dns-records')
    } 'Isolated DNS source generation'

    Invoke-PwshChecked $projector @{
        ProjectRoot = $temporaryRoot
        DnsNormalizedPath = (Join-Path $temporaryRoot 'artifacts/generated-normalized/document.json')
        ZoneNormalizedPath = (Join-Path $temporaryRoot 'fixtures/p2.1/zones/document.json')
        ZoneProjectionPath = (Join-Path $temporaryRoot 'artifacts/p2.3/projection/zones.json')
        ProjectionPath = (Join-Path $temporaryRoot 'overrides/powershell-projection.json')
        P23ProjectionPath = (Join-Path $temporaryRoot 'overrides/powershell-p23-projection.json')
        P32PolicyPath = (Join-Path $temporaryRoot 'overrides/powershell-p32-projection.json')
        ArtifactPath = $artifactPath
    } 'Isolated canonical projection'

    Invoke-PwshChecked $generator @{
        ProjectRoot = $temporaryRoot
        ArtifactPath = $artifactPath
        TemplatePath = $templatePath
        SourcePath = $sourcePath
        RuntimeSourcePath = $dnsRuntimePath
        ZoneRuntimeSourcePath = $zoneRuntimePath
        GeneratedRoot = $generatedRoot
    } 'Isolated P3.2 source and metadata generation'
    Write-Evidence 'static/generation' 'PASS isolated canonical projection and generated-source reproduction.'

    $reproduciblePaths = @(
        'artifacts/projection/CmdletModel.json',
        'artifacts/p3.2/CmdletModel.json',
        'src/Cloudflare.PowerShell/Generated/Cmdlets/P32RepresentativeCmdlets.cs',
        'src/Cloudflare.PowerShell/Generated/Metadata/CfDnsRecordOperationMetadata.cs',
        'src/Cloudflare.PowerShell/Generated/Metadata/CfDnsRecordRuntimeMetadata.cs',
        'src/Cloudflare.PowerShell/Generated/Metadata/CfZoneOperationMetadata.cs',
        'src/Cloudflare.PowerShell/Generated/Metadata/CfZoneRuntimeMetadata.cs',
        'src/Cloudflare.PowerShell/Generated/Metadata/P32CmdletHelpMetadata.cs',
        'module/Cloudflare.PowerShell/Cloudflare.PowerShell-help.xml',
        'src/Cloudflare.PowerShell/Generated/Metadata/Projection_Get_CfDnsRecord.cs',
        'src/Cloudflare.PowerShell/Generated/Metadata/Projection_New_CfDnsRecord.cs',
        'src/Cloudflare.PowerShell/Generated/Metadata/Projection_Remove_CfDnsRecord.cs',
        'src/Cloudflare.PowerShell/Generated/Metadata/Projection_Set_CfDnsRecord.cs',
        'src/Cloudflare.PowerShell/Generated/Models/CfDnsRecordModels.cs',
        'src/Cloudflare.PowerShell/Generated/Models/CfZoneModels.cs'
    )
    Assert-IsolatedHashParity $reproduciblePaths
    Write-Evidence 'static/generation' 'PASS canonical artifact, generated source, runtime/operation metadata, help, projection metadata, and models SHA-256 reproduction.'

    Invoke-PwshChecked $projectionTests @{ ProjectRoot = $temporaryRoot } 'P3.2 projection and negative contract tests'
    Write-Evidence 'static/generation' 'PASS stale, semantic, parameter-consumption, renderer-exact, and DNS/Zone runtime negative checks.'

    Push-Location $temporaryRoot
    try {
        dotnet build .\Cloudflare.P1.sln --configuration Release --nologo | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Isolated Release build failed with exit code $LASTEXITCODE." }
    }
    finally { Pop-Location }
    Write-Evidence 'static/generation' 'PASS isolated Release build; build and intermediate output stayed under the temporary project.'

    Invoke-PwshChecked $smoke @{ ProjectRoot = $temporaryRoot } 'P3.2 mock/runtime smoke and parity tests'
    Write-Evidence 'mock/runtime' 'PASS generated public routing, DNS/Zone runtime metadata parity, mock HTTP, pipeline, ShouldProcess, errors, paging, and handwritten parity.'

    Invoke-PwshChecked $regression @{
        ProjectRoot = $temporaryRoot
        SchemaRoot = (Join-Path $temporaryRoot 'ref/api-schemas')
        ArtifactRoot = (Join-Path $temporaryRoot 'artifacts/compatibility')
        SchemaRevisionManifestPath = (Join-Path $temporaryRoot 'fixtures/p2.4/openapi-previous-revision.json')
    } 'P1-P2.4 isolated regression suite'
    Write-Evidence 'static/generation' 'PASS isolated P1-P2.4 regression suite; its generated artifacts and build outputs stayed under the temporary project.'

    Push-Location $projectRoot
    try {
        git diff --check
        if ($LASTEXITCODE -ne 0) { throw 'git diff --check failed.' }
    }
    finally { Pop-Location }
    Write-Evidence 'static/generation' 'PASS git diff --check.'

    Write-Evidence 'host' 'NOT VERIFIED: no separately provisioned external host acceptance was run.'
    Write-Evidence 'device' 'NOT VERIFIED: no device acceptance was run.'
    Write-Evidence 'real-account' 'NOT VERIFIED: no real-account request or mutation was run.'
    Write-Evidence 'manual' 'NOT VERIFIED: no manual UX/help review was run.'
    Write-Evidence 'packaging/release' 'NOT VERIFIED: no packaging, publishing, or release acceptance was run.'
    Write-Output 'PASS P3.2 independent read-only acceptance; no worktree files were generated or modified by this entry point.'
}
catch {
    $failure = $_.Exception
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
    try {
        $finalStatus = Get-WorktreeStatus
        if ($null -ne $initialStatus -and $finalStatus -cne $initialStatus) {
            $statusMessage = "Read-only P3.2 acceptance changed the worktree unexpectedly. Before:`n$initialStatus`nAfter:`n$finalStatus"
            if ($null -eq $failure) { $failure = [InvalidOperationException]::new($statusMessage) }
            else { Write-Error $statusMessage }
        }
    }
    catch {
        if ($null -eq $failure) { $failure = $_.Exception }
        else { Write-Error $_.Exception.Message }
    }
}

if ($null -ne $failure) {
    Write-Error "P3.2 independent read-only acceptance failed: $($failure.Message)"
    exit 1
}
