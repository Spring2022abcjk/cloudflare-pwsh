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

    $pairs = @(
        @{ Generated = 'src/Cloudflare.PowerShell/Generated/CfDnsRecordModels.cs'; Golden = 'tests/golden/CfDnsRecordModels.cs' },
        @{ Generated = 'src/Cloudflare.PowerShell/Generated/CfDnsRecordOperations.cs'; Golden = 'tests/golden/CfDnsRecordOperations.cs' },
        @{ Generated = 'src/Cloudflare.PowerShell/Generated/Cmdlets/Get-CfDnsRecord.cs'; Golden = 'tests/golden/Get-CfDnsRecord.cs' },
        @{ Generated = 'src/Cloudflare.PowerShell/Generated/Cmdlets/New-CfDnsRecord.cs'; Golden = 'tests/golden/New-CfDnsRecord.cs' },
        @{ Generated = 'src/Cloudflare.PowerShell/Generated/Cmdlets/Remove-CfDnsRecord.cs'; Golden = 'tests/golden/Remove-CfDnsRecord.cs' },
        @{ Generated = 'src/Cloudflare.PowerShell/Generated/Cmdlets/Set-CfDnsRecord.cs'; Golden = 'tests/golden/Set-CfDnsRecord.cs' }
    )
    foreach ($pair in $pairs) {
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $pair.Generated).Hash
        $expected = (Get-FileHash -Algorithm SHA256 -LiteralPath $pair.Golden).Hash
        if ($actual -ne $expected) { throw "Golden mismatch: $($pair.Generated)" }
    }
    Write-Output 'PASS golden snapshots'
}
finally { Pop-Location }
