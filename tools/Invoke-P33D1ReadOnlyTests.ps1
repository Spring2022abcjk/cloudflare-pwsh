[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$p33ProjectRoot = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
$p33TemporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p33-d1-readonly-' + [guid]::NewGuid().ToString('N'))
$p33InitialStatus = $null
$p33Failure = $null

$p33StagingLibrary = Join-Path $PSScriptRoot 'ReadOnlyStaging.ps1'
if (-not (Test-Path -LiteralPath $p33StagingLibrary -PathType Leaf)) { throw "Read-only staging helper is missing: $p33StagingLibrary" }
. $p33StagingLibrary -Library
$p33ContractLibrary = Join-Path $PSScriptRoot 'P33ReadOnlyStaging.ps1'
if (-not (Test-Path -LiteralPath $p33ContractLibrary -PathType Leaf)) { throw "P3.3 staging contract is missing: $p33ContractLibrary" }
. $p33ContractLibrary -Library

function Get-P33WorktreeStatus {
    $lines = @(& git -C $p33ProjectRoot status --short)
    if ($LASTEXITCODE -ne 0) { throw 'Could not read the repository worktree status.' }
    return ($lines | ForEach-Object { [string]$_ }) -join "`n"
}

function Invoke-P33Checked {
    param([Parameter(Mandatory)][string]$FilePath, [Parameter(Mandatory)][string[]]$Arguments, [Parameter(Mandatory)][string]$Label)
    & $FilePath @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE." }
}

function Assert-P33HashParity {
    param([Parameter(Mandatory)][string[]]$RelativePaths)
    foreach ($relativePath in $RelativePaths) {
        $expectedPath = Join-Path $p33ProjectRoot $relativePath
        $actualPath = Join-Path $p33TemporaryRoot $relativePath
        if (-not (Test-Path -LiteralPath $expectedPath -PathType Leaf) -or -not (Test-Path -LiteralPath $actualPath -PathType Leaf)) { throw "P3.3 reproducible file is missing: $relativePath" }
        $expected = (Get-FileHash -Algorithm SHA256 -LiteralPath $expectedPath).Hash
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $actualPath).Hash
        if ($expected -cne $actual) { throw "P3.3 isolated reproduction drifted for '$relativePath'." }
    }
}

try {
    $p33InitialStatus = Get-P33WorktreeStatus
    New-Item -ItemType Directory -Force -Path $p33TemporaryRoot | Out-Null
    $p33RequiredPaths = @(Get-P33RequiredInputPaths -ProjectRoot $p33ProjectRoot)
    Copy-ReadOnlyStagingFiles -SourceRoot $p33ProjectRoot -DestinationRoot $p33TemporaryRoot -RelativePaths $p33RequiredPaths
    $p33Inventory = @(Assert-ReadOnlyStagingInputContract -Root $p33TemporaryRoot -ExpectedRelativePaths $p33RequiredPaths)
    $p33Diagnostics = Get-ReadOnlyStagingDiagnostics -Root $p33TemporaryRoot
    Write-Output "PASS P3.3 explicit staging contract files=$($p33Diagnostics.FileCount), bytes=$($p33Diagnostics.TotalBytes); no VCS/build/cache/log/temp inputs"

    $fixture = Join-Path $p33TemporaryRoot 'tools/Generate-P33D1Fixture.ps1'
    $projector = Join-Path $p33TemporaryRoot 'tools/Project-P33D1Projection.ps1'
    $generator = Join-Path $p33TemporaryRoot 'tools/Generate-P33D1Source.ps1'
    $compatibility = Join-Path $p33TemporaryRoot 'tools/Invoke-P33D1Compatibility.ps1'
    Invoke-P33Checked 'pwsh' @('-NoLogo','-NoProfile','-File',$fixture,'-ProjectRoot',$p33TemporaryRoot) 'isolated D1 fixture generation'
    Invoke-P33Checked 'pwsh' @('-NoLogo','-NoProfile','-File',$projector,'-ProjectRoot',$p33TemporaryRoot) 'isolated D1 canonical projection'
    Invoke-P33Checked 'pwsh' @('-NoLogo','-NoProfile','-File',$generator,'-ProjectRoot',$p33TemporaryRoot) 'isolated D1 source generation'
    Invoke-P33Checked 'pwsh' @('-NoLogo','-NoProfile','-File',$generator,'-ProjectRoot',$p33TemporaryRoot,'-ValidateOnly') 'isolated D1 source drift validation'

    Invoke-P33Checked 'dotnet' @('build',(Join-Path $p33TemporaryRoot 'Cloudflare.P1.sln'),'--configuration','Release','--nologo') 'isolated Release build'
    Invoke-P33Checked 'pwsh' @('-NoLogo','-NoProfile','-File',$compatibility,'-ProjectRoot',$p33TemporaryRoot) 'isolated D1 projection compatibility'
    Invoke-P33Checked 'pwsh' @('-NoLogo','-NoProfile','-File',(Join-Path $p33TemporaryRoot 'tests/P33D1Projection.Tests.ps1'),'-ProjectRoot',$p33TemporaryRoot) 'isolated D1 projection tests'
    Invoke-P33Checked 'pwsh' @('-NoLogo','-NoProfile','-File',(Join-Path $p33TemporaryRoot 'tests/P33D1Smoke.ps1'),'-ProjectRoot',$p33TemporaryRoot) 'isolated D1 mock/runtime smoke'
    Invoke-P33Checked 'pwsh' @('-NoLogo','-NoProfile','-File',(Join-Path $p33TemporaryRoot 'tests/P33Coverage.Tests.ps1'),'-ProjectRoot',$p33TemporaryRoot) 'isolated P3.3 coverage contract'

    Assert-P33HashParity @(
        'fixtures/p3.3/d1-database/document.json',
        'artifacts/p3.3/CmdletModel.json',
        'artifacts/p3.3/d1-projection-compatibility.json',
        'src/Cloudflare.PowerShell/Generated/Cmdlets/P33D1DatabaseCmdlets.cs',
        'src/Cloudflare.PowerShell/Generated/Metadata/CfD1DatabaseOperationMetadata.cs',
        'src/Cloudflare.PowerShell/Generated/Metadata/CfD1DatabaseRuntimeMetadata.cs',
        'src/Cloudflare.PowerShell/Generated/Models/CfD1Database.cs',
        'src/Cloudflare.PowerShell/Generated/Models/CfD1DatabaseCreateRequest.cs',
        'src/Cloudflare.PowerShell/Generated/Models/CfD1DatabaseUpdateRequest.cs',
        'src/Cloudflare.PowerShell/Generated/Models/CfD1DatabasePartialUpdateRequest.cs',
        'src/Cloudflare.PowerShell/Generated/Models/CfD1ReadReplicationDetails.cs'
    )
    Write-Output 'PASS P3.3 D1 isolated artifact/source/model reproduction; current worktree was not the build target.'
}
catch {
    $p33Failure = $_.Exception
}
finally {
    if (Test-Path -LiteralPath $p33TemporaryRoot) { Remove-Item -LiteralPath $p33TemporaryRoot -Recurse -Force }
    try {
        $p33FinalStatus = Get-P33WorktreeStatus
        if ($null -ne $p33InitialStatus -and $p33FinalStatus -cne $p33InitialStatus) {
            $statusMessage = "P3.3 read-only acceptance changed the worktree unexpectedly. Before:`n$p33InitialStatus`nAfter:`n$p33FinalStatus"
            if ($null -eq $p33Failure) { $p33Failure = [InvalidOperationException]::new($statusMessage) } else { Write-Error $statusMessage }
        }
    }
    catch {
        if ($null -eq $p33Failure) { $p33Failure = $_.Exception } else { Write-Error $_.Exception.Message }
    }
}

if ($null -ne $p33Failure) {
    Write-Error "P3.3 D1 independent read-only acceptance failed: $($p33Failure.Message)"
    exit 1
}
