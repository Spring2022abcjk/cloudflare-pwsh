[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Push-Location $ProjectRoot
try {
    $solution = Join-Path $ProjectRoot 'Cloudflare.P1.sln'
    dotnet restore $solution | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'dotnet restore failed.' }

    dotnet build $solution --configuration Release --no-restore | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'dotnet build failed.' }

    dotnet run --project .\tests\Cloudflare.P2.Tests\Cloudflare.P2.Tests.csproj --configuration Release --no-build -- (Join-Path $ProjectRoot 'ref/api-schemas/openapi.json') | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'CrossResourceNormalizationTests failed.' }

    & pwsh -NoLogo -NoProfile -File .\tools\Project-P21Normalized.ps1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'ProjectionGeneralizationTests generation failed.' }

    foreach ($resource in @('zones', 'd1-database', 'ai-search-jobs')) {
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $ProjectRoot "artifacts/p2.1/projection/$resource.json")).Hash
        $expected = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $ProjectRoot "tests/golden/p2.1/$resource.json")).Hash
        if ($actual -ne $expected) { throw "Projection snapshot mismatch: $resource" }
    }
    foreach ($golden in Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'tests/golden/p2.1') -Filter 'P21_*.cs' -File) {
        $generated = Join-Path $ProjectRoot "src/Cloudflare.PowerShell/Generated/Metadata/$($golden.Name)"
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $generated).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $golden.FullName).Hash) { throw "Generated metadata mismatch: $($golden.Name)" }
    }
    Write-Output 'PASS ProjectionGeneralizationTests'

    & pwsh -NoLogo -NoProfile -File .\tools\Invoke-P1Tests.ps1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'P1 regression suite failed.' }
    Write-Output 'PASS P2.1 including P1 regression suite'
}
finally { Pop-Location }
