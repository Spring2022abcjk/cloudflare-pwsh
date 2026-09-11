[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Push-Location $ProjectRoot
try {
    & pwsh -NoLogo -NoProfile -File .\tools\Project-P23Projection.ps1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'P2.3 projection generation failed.' }
    & pwsh -NoLogo -NoProfile -File .\tests\P23Projection.Tests.ps1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'P2.3 projection/experiment tests failed.' }
    & pwsh -NoLogo -NoProfile -File .\tools\Invoke-P22Tests.ps1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'P2.2 regression suite failed.' }
    Write-Output 'PASS P2.3 including P2.2, P2.1, and P1 regression suites'
}
finally { Pop-Location }
