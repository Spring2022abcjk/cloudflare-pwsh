[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$SchemaPath = (Join-Path $ProjectRoot 'ref/api-schemas/openapi.json'),
    [string]$CorrectionPath = (Join-Path $ProjectRoot 'overrides/api-corrections.json'),
    [string]$OutputPath = (Join-Path $ProjectRoot 'fixtures/p3.3/d1-database/document.json'),
    [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
$schemaPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $SchemaPath).Path)
$correctionPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $CorrectionPath).Path)
$outputPath = if ([IO.Path]::IsPathRooted($OutputPath)) { [IO.Path]::GetFullPath($OutputPath) } else { Join-Path $projectRoot $OutputPath }

function Invoke-Checked {
    param([Parameter(Mandatory)][string]$FilePath, [Parameter(Mandatory)][string[]]$Arguments)
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Command '$FilePath $($Arguments -join ' ')' failed with exit code $LASTEXITCODE." }
}

function Write-Utf8CrLf {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
    [IO.File]::WriteAllText($Path, $normalized, [Text.UTF8Encoding]::new($false))
}

$normalizationProject = Join-Path $projectRoot 'src/Cloudflare.Normalization/Cloudflare.Normalization.csproj'
$normalizationAssembly = Join-Path $projectRoot 'src/Cloudflare.Normalization/bin/Release/net10.0/Cloudflare.Normalization.dll'
if (-not (Test-Path -LiteralPath $normalizationAssembly -PathType Leaf) -or -not $SkipBuild) {
    $buildArgs = @('build', $normalizationProject, '--configuration', 'Release', '--nologo')
    if ($SkipBuild) { $buildArgs += '--no-restore' }
    Invoke-Checked 'dotnet' $buildArgs
}
if (-not (Test-Path -LiteralPath $normalizationAssembly -PathType Leaf)) { throw "Normalization assembly is missing: $normalizationAssembly" }
Add-Type -Path $normalizationAssembly

$operationIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($operationId in @(
        'd1-create-database',
        'd1-delete-database',
        'd1-get-database',
        'd1-list-databases',
        'd1-update-database',
        'd1-update-partial-database')) {
    [void]$operationIds.Add($operationId)
}

$openApi = [Cloudflare.Normalization.OpenApiLoader]::Load($schemaPath)
$normalized = [Cloudflare.Normalization.OpenApiNormalizer]::new($openApi).NormalizeOperations($operationIds)
$corrected = [Cloudflare.Normalization.ApiCorrectionEngine]::new($correctionPath).Apply($normalized)
if (@($corrected.Operations).Count -ne $operationIds.Count) { throw "Expected exactly $($operationIds.Count) normalized D1 operations, found $(@($corrected.Operations).Count)." }

$selectedNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($operation in $corrected.Operations) {
    foreach ($parameter in @($operation.Parameters)) { [void]$selectedNames.Add([string]$parameter.Schema) }
    if ($null -ne $operation.RequestBody) {
        foreach ($representation in @($operation.RequestBody.Representations)) { [void]$selectedNames.Add([string]$representation.Schema) }
    }
    foreach ($representation in @($operation.Responses | ForEach-Object Representations)) { [void]$selectedNames.Add([string]$representation.Schema) }
}

$schemas = [ordered]@{}
$pending = [System.Collections.Generic.Queue[string]]::new()
foreach ($name in @($selectedNames | Sort-Object)) { if (-not [string]::IsNullOrWhiteSpace($name)) { $pending.Enqueue($name) } }
while ($pending.Count -gt 0) {
    $name = $pending.Dequeue()
    if ($schemas.Contains($name)) { continue }
    if (-not $corrected.Schemas.ContainsKey($name)) { throw "Normalized D1 fixture references missing schema '$name'." }
    $schema = $corrected.Schemas[$name]
    $schemas[$name] = $schema
    $children = @($schema.Properties.Values | ForEach-Object Schema)
    if (-not [string]::IsNullOrWhiteSpace([string]$schema.Items)) { $children += [string]$schema.Items }
    $children += @($schema.OneOf) + @($schema.AnyOf) + @($schema.AllOf)
    foreach ($child in @($children | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)) { $pending.Enqueue([string]$child) }
}

$fixture = [Cloudflare.Normalization.NormalizedDocument]::new()
$fixture.Version = $corrected.Version
$fixture.SourcePath = $corrected.SourcePath
$fixture.SourceRevision = $corrected.SourceRevision
$fixture.Operations = [System.Collections.Generic.List[Cloudflare.Normalization.NormalizedOperation]]::new()
foreach ($operation in @($corrected.Operations | Sort-Object OperationId)) { $fixture.Operations.Add($operation) }
$fixture.Schemas = [System.Collections.Generic.Dictionary[string, Cloudflare.Normalization.NormalizedSchema]]::new([StringComparer]::Ordinal)
foreach ($name in @($schemas.Keys | Sort-Object)) { $fixture.Schemas.Add($name, $schemas[$name]) }
$json = [System.Text.Json.JsonSerializer]::Serialize($fixture, [Cloudflare.Normalization.NormalizedJson]::Options)
Write-Utf8CrLf $outputPath ($json + "`n")
Write-Output "PASS P3.3 D1 normalized fixture operations=$($fixture.Operations.Count) schemas=$($fixture.Schemas.Count) -> $outputPath"
