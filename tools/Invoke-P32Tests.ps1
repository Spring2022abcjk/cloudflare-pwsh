[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$powershellHome = Split-Path -Parent (Get-Command pwsh).Source
Push-Location $ProjectRoot
try {
    & pwsh -NoLogo -NoProfile -File .\tools\Generate-P32Source.ps1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'P3.2 source generation failed.' }

    dotnet build .\Cloudflare.P1.sln --configuration Release --no-restore "-p:PowerShellHome=$powershellHome" | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'P3.2 solution build failed.' }

    & pwsh -NoLogo -NoProfile -File .\tests\P32Smoke.ps1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'P3.2 generated cmdlet smoke failed.' }

    & pwsh -NoLogo -NoProfile -File .\tools\Invoke-P24Tests.ps1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'P1 through P2.4 regression suite failed during P3.2 validation.' }

    Write-Output 'PASS P3.2 generated public surface and P1-P2.4 regression suite'
}
finally { Pop-Location }
