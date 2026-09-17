[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

function Copy-AdmissionFixture {
    param([Parameter(Mandatory)][string]$Destination)
    $policyPath = Join-Path $ProjectRoot 'overrides/public-admission-policy.json'
    $policy = Get-Content -Raw -LiteralPath $policyPath | ConvertFrom-Json
    $relativePaths = @(
        'overrides/public-admission-policy.json',
        [string]$policy.canonicalSurface.publicCmdletModelPath,
        [string]$policy.canonicalSurface.coverageReportPath,
        [string]$policy.canonicalSurface.p24CompatibilitySurfacePath,
        [string]$policy.canonicalSurface.moduleManifestPath,
        [string]$policy.canonicalSurface.moduleScriptPath,
        [string]$policy.canonicalSurface.generatedHelpPath
    ) + @($policy.canonicalSurface.generatedPublicSourcePaths | ForEach-Object { [string]$_ })
    foreach ($relativePath in @($relativePaths | Sort-Object -Unique)) {
        $source = Join-Path $ProjectRoot $relativePath
        $target = Join-Path $Destination $relativePath
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
}

function Invoke-Gate {
    param([Parameter(Mandatory)][string]$FixtureRoot)
    $gate = Join-Path $ProjectRoot 'tools/Invoke-P33AdmissionParity.ps1'
    $assembly = Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/bin/Release/net10.0/Cloudflare.PowerShell.dll'
    & pwsh -NoLogo -NoProfile -File $gate -ProjectRoot $FixtureRoot -AssemblyPath $assembly 2>&1 | Out-Null
    return [int]$LASTEXITCODE
}

function Assert-GateFails {
    param([Parameter(Mandatory)][scriptblock]$Mutation, [Parameter(Mandatory)][string]$Label)
    $fixture = Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p33-admission-negative-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Force -Path $fixture | Out-Null
        Copy-AdmissionFixture $fixture
        & $Mutation $fixture
        Assert-True ((Invoke-Gate $fixture) -ne 0) "$Label mutation bypassed admission parity."
    }
    finally {
        if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
    }
}

$baseline = Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p33-admission-baseline-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path $baseline | Out-Null
    Copy-AdmissionFixture $baseline
    Assert-True ((Invoke-Gate $baseline) -eq 0) 'baseline canonical admission parity did not pass.'
}
finally {
    if (Test-Path -LiteralPath $baseline) { Remove-Item -LiteralPath $baseline -Recurse -Force }
}

Assert-GateFails {
    param($root)
    $path = Join-Path $root 'module/Cloudflare.PowerShell/Cloudflare.PowerShell.psd1'
    $text = Get-Content -Raw -LiteralPath $path
    $mutated = $text.Replace("'Set-CfDnsRecord')", "'Set-CfDnsRecord', 'Get-CfNotAdmitted')")
    if ($mutated -ceq $text) { throw 'manifest mutation did not apply.' }
    [IO.File]::WriteAllText($path, $mutated, [Text.UTF8Encoding]::new($false))
} 'module manifest extra command'

Assert-GateFails {
    param($root)
    $path = Join-Path $root 'module/Cloudflare.PowerShell/Cloudflare.PowerShell.psd1'
    $text = Get-Content -Raw -LiteralPath $path
    $mutated = $text.Replace(", 'Set-CfDnsRecord'", '')
    if ($mutated -ceq $text) { throw 'manifest missing-command mutation did not apply.' }
    [IO.File]::WriteAllText($path, $mutated, [Text.UTF8Encoding]::new($false))
} 'module manifest missing admitted command'

Assert-GateFails {
    param($root)
    $path = Join-Path $root 'module/Cloudflare.PowerShell/Cloudflare.PowerShell.psm1'
    $text = Get-Content -Raw -LiteralPath $path
    $mutated = $text.Replace("'Set-CfDnsRecord')", "'Set-CfDnsRecord', 'Get-CfNotAdmitted')")
    if ($mutated -ceq $text) { throw 'module script mutation did not apply.' }
    [IO.File]::WriteAllText($path, $mutated, [Text.UTF8Encoding]::new($false))
} 'module script extra command'

Assert-GateFails {
    param($root)
    $path = Join-Path $root 'module/Cloudflare.PowerShell/Cloudflare.PowerShell-help.xml'
    $text = Get-Content -Raw -LiteralPath $path
    $extra = @'
  <command:command xmlns:maml="http://schemas.microsoft.com/maml/2004/10" xmlns:command="http://schemas.microsoft.com/maml/dev/command/2004/10">
    <command:details><command:name>Get-CfNotAdmitted</command:name></command:details>
  </command:command>
'@
    $mutated = $text.Replace('</helpItems>', "$extra</helpItems>")
    [IO.File]::WriteAllText($path, $mutated, [Text.UTF8Encoding]::new($false))
} 'generated help extra command'

Assert-GateFails {
    param($root)
    $path = Join-Path $root 'module/Cloudflare.PowerShell/Cloudflare.PowerShell-help.xml'
    $text = Get-Content -Raw -LiteralPath $path
    $mutated = $text.Replace('<command:name>Set-CfDnsRecord</command:name>', '')
    if ($mutated -ceq $text) { throw 'help missing-command mutation did not apply.' }
    [IO.File]::WriteAllText($path, $mutated, [Text.UTF8Encoding]::new($false))
} 'generated help missing admitted command'

Assert-GateFails {
    param($root)
    $path = Join-Path $root 'src/Cloudflare.PowerShell/Generated/Cmdlets/P32RepresentativeCmdlets.cs'
    $extra = @'
[Cmdlet(VerbsCommon.Get, "CfNotAdmitted")]
public sealed class GetCfNotAdmittedCommand : CloudflareCmdletBase { }
'@
    Add-Content -LiteralPath $path -Value $extra -Encoding utf8NoBOM
} 'generated public source extra command'

Assert-GateFails {
    param($root)
    $path = Join-Path $root 'artifacts/p3.2/CmdletModel.json'
    $artifact = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    $artifact.cmdlets = @($artifact.cmdlets) + [pscustomobject]@{ cmdletName = 'Get-CfNotAdmitted' }
    [IO.File]::WriteAllText($path, ($artifact | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
} 'canonical public artifact extra command'

Assert-GateFails {
    param($root)
    $path = Join-Path $root 'artifacts/p3.3/coverage-baseline.json'
    $coverage = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    $row = @($coverage.operations)[0]
    $row.currentPublicSurface = $true
    $row.currentPublicCmdlet = 'Get-CfNotAdmitted'
    [IO.File]::WriteAllText($path, ($coverage | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
} 'coverage public classification extra command'

Write-Output 'PASS P3.3 admission parity baseline and extra-surface negative contracts'
