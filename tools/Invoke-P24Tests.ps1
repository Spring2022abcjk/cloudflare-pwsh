[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$SchemaRoot = (Join-Path $ProjectRoot 'ref/api-schemas'),
    [string]$ArtifactRoot = (Join-Path $ProjectRoot 'artifacts/compatibility')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$powershellHome = Split-Path -Parent (Get-Command pwsh).Source
Push-Location $ProjectRoot
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p24-' + [guid]::NewGuid().ToString('N'))
try {
    $revisions = @(& git -C $SchemaRoot rev-list --max-count=2 HEAD -- openapi.json)
    if ($LASTEXITCODE -ne 0 -or $revisions.Count -ne 2) { throw 'Could not resolve two schema revisions for the P2.4 real diff.' }
    $newRevision = [string]$revisions[0]
    $oldRevision = [string]$revisions[1]
    $null = New-Item -ItemType Directory -Path $temporaryRoot -Force
    $oldPath = Join-Path $temporaryRoot ($oldRevision + '-openapi.json')
    $newPath = Join-Path $temporaryRoot ($newRevision + '-openapi.json')
    & git -C $SchemaRoot show "$oldRevision`:openapi.json" | Set-Content -LiteralPath $oldPath -Encoding utf8 -NoNewline
    if ($LASTEXITCODE -ne 0) { throw "Could not materialize old schema revision $oldRevision." }
    Copy-Item -LiteralPath (Join-Path $SchemaRoot 'openapi.json') -Destination $newPath -Force

    dotnet restore .\Cloudflare.P1.sln | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'dotnet restore failed.' }
    dotnet clean .\Cloudflare.P1.sln --configuration Release "-p:PowerShellHome=$powershellHome" | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'dotnet clean failed.' }
    dotnet restore .\Cloudflare.P1.sln | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'dotnet restore after clean failed.' }
    dotnet build .\Cloudflare.P1.sln --configuration Release --no-restore "-p:PowerShellHome=$powershellHome" | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'dotnet build failed.' }

    dotnet run --project .\tests\Cloudflare.P24.Tests\Cloudflare.P24.Tests.csproj --configuration Release --no-build | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'P2.4 synthetic compatibility suite failed.' }
    & pwsh -NoLogo -NoProfile -File .\tools\Invoke-P23Tests.ps1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'P2.3 and earlier regression suites failed.' }

    $null = New-Item -ItemType Directory -Path $ArtifactRoot -Force
    $projectionPolicyPath = Join-Path $ProjectRoot 'overrides/powershell-p23-projection.json'
    $projectionArtifactRoot = Join-Path $ArtifactRoot 'projection'
    dotnet run --project .\tests\Cloudflare.P24.Tests\Cloudflare.P24.Tests.csproj --configuration Release --no-build -- $oldPath $newPath $ArtifactRoot $oldRevision $newRevision $projectionPolicyPath $projectionArtifactRoot | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'P2.4 real schema revision diff failed.' }
    Write-Output "PASS P2.4 including net10 baseline, P2.3 and earlier regression suites"
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
    Pop-Location
}
