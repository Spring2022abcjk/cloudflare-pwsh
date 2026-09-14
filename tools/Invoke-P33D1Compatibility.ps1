[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$BaselinePath = (Join-Path $ProjectRoot 'artifacts/p2.3/projection/d1-database.json'),
    [string]$CandidatePath = (Join-Path $ProjectRoot 'artifacts/p3.3/CmdletModel.json'),
    [string]$OutputPath = (Join-Path $ProjectRoot 'artifacts/p3.3/d1-projection-compatibility.json'),
    [string]$MarkdownPath = (Join-Path $ProjectRoot 'artifacts/p3.3/d1-projection-compatibility.md')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$normalizationAssembly = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'src/Cloudflare.Normalization/bin/Release') -Recurse -Filter 'Cloudflare.Normalization.dll' -File |
    Where-Object FullName -match '[\\/]net10\.0[\\/]' |
    Select-Object -First 1
if ($null -eq $normalizationAssembly) { throw 'Cloudflare.Normalization Release assembly is required before projection compatibility can run.' }
Add-Type -Path $normalizationAssembly.FullName

function Read-Projection {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Projection file not found: $Path" }
    return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Get-ProjectionCompatibilityReport {
    param(
        [Parameter(Mandatory)]$OldProjection,
        [Parameter(Mandatory)]$NewProjection
    )
    $oldNode = [System.Text.Json.Nodes.JsonNode]::Parse(($OldProjection | ConvertTo-Json -Depth 100))
    $newNode = [System.Text.Json.Nodes.JsonNode]::Parse(($NewProjection | ConvertTo-Json -Depth 100))
    $changes = [Cloudflare.Normalization.Compatibility.ProjectionCompatibility]::Compare($oldNode, $newNode)
    return [Cloudflare.Normalization.Compatibility.CompatibilityReport]::Create('P3.3-projection', 'P2.3-d1-database', 'P3.3-d1-database', $changes)
}

$oldProjection = Read-Projection -Path $BaselinePath
$newProjection = Read-Projection -Path $CandidatePath
$report = Get-ProjectionCompatibilityReport -OldProjection $oldProjection -NewProjection $newProjection
$json = [System.Text.Json.JsonSerializer]::Serialize($report, [Cloudflare.Normalization.Compatibility.CompatibilityJson]::Options) + [Environment]::NewLine
$outputDirectory = Split-Path -Parent $OutputPath
$markdownDirectory = Split-Path -Parent $MarkdownPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $markdownDirectory -Force | Out-Null
[IO.File]::WriteAllText($OutputPath, $json, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($MarkdownPath, [Cloudflare.Normalization.Compatibility.CompatibilityReportFormatter]::ToMarkdown($report), [Text.UTF8Encoding]::new($false))

$parameterSetChanges = @($report.Changes | Where-Object Kind -eq 'PowerShellParameterSetChanged')
if ($report.Changes.Count -eq 0) { throw 'P3.3 D1 projection compatibility did not observe any public projection change.' }
if ($parameterSetChanges.Count -eq 0) { throw 'P3.3 D1 projection compatibility did not observe the partial-update parameter-set change.' }
Write-Output "PASS P3.3 D1 projection compatibility: changes=$($report.Changes.Count), parameterSetChanges=$($parameterSetChanges.Count) -> $OutputPath"
