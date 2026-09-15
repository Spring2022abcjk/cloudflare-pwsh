[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Push-Location $ProjectRoot
try {
    & pwsh -NoLogo -NoProfile -File .\tools\Generate-DnsSource.ps1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Generator failed.' }

    dotnet build .\Cloudflare.P1.sln --configuration Release --no-restore | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'dotnet build failed.' }
    dotnet run --project .\tests\Cloudflare.PowerShell.Tests\Cloudflare.PowerShell.Tests.csproj --configuration Release --no-build | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'runtime contract tests failed.' }

    & pwsh -NoLogo -NoProfile -File .\tests\ModuleSmoke.ps1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'module smoke failed.' }
    & pwsh -NoLogo -NoProfile -File .\tests\ProjectionModel.Tests.ps1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'projection model tests failed.' }

    $openApiPath = Join-Path $ProjectRoot 'ref/api-schemas/openapi.json'
    if (-not (Test-Path -LiteralPath $openApiPath)) { throw 'P1.2 requires the pinned local OpenAPI reference at ref/api-schemas/openapi.json.' }
    dotnet run --project .\tests\Cloudflare.Normalization.Tests\Cloudflare.Normalization.Tests.csproj --configuration Release --no-build -- $openApiPath (Join-Path $ProjectRoot 'artifacts/generated-normalized/dns-records') | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'OpenAPI normalization/semantic diff tests failed.' }

    & pwsh -NoLogo -NoProfile -File .\tools\Generate-DnsSource.ps1 -FixtureRoot (Join-Path $ProjectRoot 'artifacts/generated-normalized/dns-records') | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Projection regression from normalized OpenAPI output failed.' }

    $pairs = @(
        @{ Generated = 'src/Cloudflare.PowerShell/Generated/Models/CfDnsRecordModels.cs'; Golden = 'tests/golden/CfDnsRecordModels.cs' },
        @{ Generated = 'src/Cloudflare.PowerShell/Generated/Metadata/CfDnsRecordOperationMetadata.cs'; Golden = 'tests/golden/CfDnsRecordOperations.cs' },
        @{ Generated = 'src/Cloudflare.PowerShell/Generated/Metadata/Projection_Get_CfDnsRecord.cs'; Golden = 'tests/golden/Projection_Get_CfDnsRecord.cs' },
        @{ Generated = 'src/Cloudflare.PowerShell/Generated/Metadata/Projection_New_CfDnsRecord.cs'; Golden = 'tests/golden/Projection_New_CfDnsRecord.cs' },
        @{ Generated = 'src/Cloudflare.PowerShell/Generated/Metadata/Projection_Remove_CfDnsRecord.cs'; Golden = 'tests/golden/Projection_Remove_CfDnsRecord.cs' },
        @{ Generated = 'src/Cloudflare.PowerShell/Generated/Metadata/Projection_Set_CfDnsRecord.cs'; Golden = 'tests/golden/Projection_Set_CfDnsRecord.cs' }
    )
    foreach ($pair in $pairs) {
        $actual = ((Get-Content -Raw -LiteralPath $pair.Generated) -replace "`r`n", "`n").Replace("`r", "")
        $expected = ((Get-Content -Raw -LiteralPath $pair.Golden) -replace "`r`n", "`n").Replace("`r", "")
        if ($actual -ne $expected) { throw "Golden mismatch: $($pair.Generated)" }
    }
    Write-Output 'PASS golden snapshots'
}
finally { Pop-Location }
