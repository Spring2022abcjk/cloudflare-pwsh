[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
$initial = @(& git -C $root status --short) -join "`n"

function Invoke-P34Checked {
    param([Parameter(Mandatory)][string]$FilePath, [Parameter(Mandatory)][string[]]$Arguments, [Parameter(Mandatory)][string]$Label)
    & $FilePath @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE." }
}

try {
    Push-Location $root
    try {
        Invoke-P34Checked 'dotnet' @('restore', 'Cloudflare.P1.sln', '--nologo') 'P3.4 restore'
        Invoke-P34Checked 'dotnet' @('build', 'Cloudflare.P1.sln', '--configuration', 'Release', '--no-restore', '--nologo') 'P3.4 Release build for coverage discovery'
        Invoke-P34Checked 'pwsh' @('-NoLogo', '-NoProfile', '-File', (Join-Path $root 'tools/Invoke-P32ReadOnlyTests.ps1'), '-ProjectRoot', $root) 'P3.2 deterministic read-only gate'
        Invoke-P34Checked 'pwsh' @('-NoLogo', '-NoProfile', '-File', (Join-Path $root 'tools/Invoke-P33D2ReadOnlyTests.ps1'), '-ProjectRoot', $root) 'P3.3 deterministic read-only gate'
        Invoke-P34Checked 'pwsh' @('-NoLogo', '-NoProfile', '-File', (Join-Path $root 'tests/P33Coverage.Tests.ps1'), '-ProjectRoot', $root, '-VerifyDeterminism') 'P3.3 coverage determinism and freshness gate'
        & git diff --check
        if ($LASTEXITCODE -ne 0) { throw 'P3.4 deterministic validation git diff --check failed.' }
    }
    finally { Pop-Location }
    $final = @(& git -C $root status --short) -join "`n"
    if ($final -cne $initial) { throw "P3.4 deterministic validation changed the worktree unexpectedly. Before:`n$initial`nAfter:`n$final" }
    Write-Output 'PASS P3.4 deterministic generation, golden/hash, regression, and clean-worktree foundation'
}
catch {
    Write-Error "P3.4 deterministic validation failed: $($_.Exception.Message)"
    exit 1
}
