[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$BaselinePath = (Join-Path $ProjectRoot 'artifacts/p3.2/CmdletModel.json'),
    [string]$CandidatePath = (Join-Path $ProjectRoot 'artifacts/p3.3/healthchecks/CmdletModel.json'),
    [string]$OutputPath = (Join-Path $ProjectRoot 'artifacts/p3.3/healthchecks/d2-projection-compatibility.json'),
    [string]$MarkdownPath = (Join-Path $ProjectRoot 'artifacts/p3.3/healthchecks/d2-projection-compatibility.md')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$assembly = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'src/Cloudflare.Normalization/bin/Release') -Recurse -Filter Cloudflare.Normalization.dll -File | Where-Object FullName -match '[\\/]net10\.0[\\/]' | Select-Object -First 1
if ($null -eq $assembly) { throw 'Cloudflare.Normalization Release assembly is required before D2 compatibility can run.' }
Add-Type -Path $assembly.FullName
foreach ($path in @($BaselinePath,$CandidatePath)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Projection file not found: $path" } }
$old = Get-Content -Raw -LiteralPath $BaselinePath | ConvertFrom-Json
$d2 = Get-Content -Raw -LiteralPath $CandidatePath | ConvertFrom-Json
$combined = [ordered]@{
    version = 1
    stage = 'P3.3'
    sourcePolicy = 'P3.2-public-surface-plus-d2-healthchecks'
    semanticAlgorithm = 'SHA256-CanonicalJson-v1'
    sourceFiles = @()
    cmdlets = @(@($old.cmdlets) + @($d2.cmdlets))
    models = @(@($old.models) + @($d2.models))
    commonInfrastructureParameters = @($old.commonInfrastructureParameters)
}
$oldNode = [System.Text.Json.Nodes.JsonNode]::Parse(($old | ConvertTo-Json -Depth 100))
$newNode = [System.Text.Json.Nodes.JsonNode]::Parse(($combined | ConvertTo-Json -Depth 100))
$changes = [Cloudflare.Normalization.Compatibility.ProjectionCompatibility]::Compare($oldNode,$newNode)
$report = [Cloudflare.Normalization.Compatibility.CompatibilityReport]::Create('P3.3-projection','P3.2-public-surface','P3.3-d2-healthchecks',$changes)
$added = @($report.Changes | Where-Object Kind -eq 'CmdletAdded' | ForEach-Object Path)
$expected = @('Get-CfHealthCheck','New-CfHealthCheck','Remove-CfHealthCheck','Set-CfHealthCheck')
if ($report.Changes.Count -eq 0) { throw 'D2 compatibility report is empty.' }
foreach ($name in $expected) { if (@($added | Where-Object { [string]$_ -match [regex]::Escape($name) }).Count -eq 0) { throw "D2 compatibility report did not record CmdletAdded for '$name'." } }
$json = [System.Text.Json.JsonSerializer]::Serialize($report,[Cloudflare.Normalization.Compatibility.CompatibilityJson]::Options) + [Environment]::NewLine
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $MarkdownPath) | Out-Null
[IO.File]::WriteAllText($OutputPath,$json,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($MarkdownPath,[Cloudflare.Normalization.Compatibility.CompatibilityReportFormatter]::ToMarkdown($report),[Text.UTF8Encoding]::new($false))
Write-Output "PASS P3.3 D2 projection compatibility: changes=$($report.Changes.Count), added=$($added.Count) -> $OutputPath"
