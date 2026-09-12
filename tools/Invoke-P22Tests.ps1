[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$powershellHome = Split-Path -Parent (Get-Command pwsh).Source
Push-Location $ProjectRoot
try {
    $solution = Join-Path $ProjectRoot 'Cloudflare.P1.sln'
    dotnet restore $solution | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'dotnet restore failed.' }

    dotnet build $solution --configuration Release --no-restore "-p:PowerShellHome=$powershellHome" | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'dotnet build failed.' }

    dotnet run --project .\tests\Cloudflare.P22.Tests\Cloudflare.P22.Tests.csproj --configuration Release --no-build -- (Join-Path $ProjectRoot 'ref/api-schemas/openapi.json') | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'SpecialTransportNormalizationTests failed.' }

    & pwsh -NoLogo -NoProfile -File .\tools\Invoke-P2Tests.ps1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'P2.1 regression suite failed.' }
    Write-Output 'PASS P2.2 including P2.1 and P1 regression suites'
}
finally { Pop-Location }
