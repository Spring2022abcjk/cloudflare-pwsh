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

function Copy-IsolatedProject {
    param([Parameter(Mandatory)][string]$Destination)
    $null = New-Item -ItemType Directory -Path $Destination -Force
    $entries = @(
        'Cloudflare.P1.sln',
        'README.md',
        '.gitattributes',
        '.gitignore',
        'artifacts',
        'experiments',
        'fixtures',
        'module',
        'overrides',
        'src',
        'tests',
        'tools'
    )
    foreach ($entry in $entries) {
        $source = Join-Path $projectRoot $entry
        if (-not (Test-Path -LiteralPath $source)) { throw "Required project entry is missing: $source" }
        Copy-Item -LiteralPath $source -Destination (Join-Path $Destination $entry) -Recurse -Force
    }

    $schemaSource = Join-Path $projectRoot 'ref/api-schemas'
    if (-not (Test-Path -LiteralPath $schemaSource -PathType Container)) { throw "P2.4 schema repository is missing: $schemaSource" }
    $schemaDestination = Join-Path $Destination 'ref/api-schemas'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $schemaDestination) -Force
    Copy-Item -LiteralPath $schemaSource -Destination $schemaDestination -Recurse -Force

    $generatedDirectories = @(Get-ChildItem -LiteralPath $Destination -Directory -Recurse -Force | Where-Object Name -in @('bin', 'obj') | Sort-Object FullName -Descending)
    foreach ($directory in $generatedDirectories) {
        Remove-Item -LiteralPath $directory.FullName -Recurse -Force
    }
}

function Assert-IsolatedHashParity {
    param([Parameter(Mandatory)][string[]]$RelativePaths)
    foreach ($relativePath in $RelativePaths) {
        $expectedPath = Join-Path $projectRoot $relativePath
        $actualPath = Join-Path $temporaryRoot $relativePath
        if (-not (Test-Path -LiteralPath $expectedPath -PathType Leaf)) { throw "Expected reproducible file is missing: $expectedPath" }
        if (-not (Test-Path -LiteralPath $actualPath -PathType Leaf)) { throw "Isolated reproducible file is missing: $actualPath" }
        $expectedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $expectedPath).Hash
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $actualPath).Hash
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

    $powershellHome = Split-Path -Parent (Get-Command pwsh).Source
    Push-Location $temporaryRoot
    try {
        dotnet build .\Cloudflare.P1.sln --configuration Release --nologo "-p:PowerShellHome=$powershellHome" | Out-Host
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
