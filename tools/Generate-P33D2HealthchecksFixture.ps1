[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$SchemaPath = (Join-Path $ProjectRoot 'ref/api-schemas/openapi.json'),
    [string]$CorrectionPath = (Join-Path $ProjectRoot 'overrides/api-corrections.json'),
    [string]$OutputPath = (Join-Path $ProjectRoot 'fixtures/p3.3/healthchecks/document.json'),
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

function Get-D2JsonValue {
    param([AllowNull()][object]$Object, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Assert-D2DeleteCorrectionContract {
    param([Parameter(Mandatory)][object]$CorrectionDocument)
    $operationId = 'health-checks-delete-health-check'
    $observedCorrection = 'official-wrappers-send-no-body'
    $candidates = @($CorrectionDocument.rules | Where-Object {
        $match = Get-D2JsonValue $_ 'match'
        $requestBody = Get-D2JsonValue (Get-D2JsonValue $_ 'actions') 'requestBody'
        [string](Get-D2JsonValue $match 'operationId') -ceq $operationId -or [string](Get-D2JsonValue $requestBody 'observedCorrection') -ceq $observedCorrection
    })
    if (@($candidates).Count -ne 1) { throw 'D2 DELETE correction must have exactly one identifiable correction rule.' }
    $rule = $candidates[0]
    $match = Get-D2JsonValue $rule 'match'
    $matchProperties = if ($null -eq $match) { @() } else { @($match.PSObject.Properties.Name) }
    if (@($matchProperties).Count -ne 1 -or @($matchProperties)[0] -cne 'operationId' -or [string](Get-D2JsonValue $match 'operationId') -cne $operationId) { throw 'D2 DELETE correction must match the exact operationId and no broad method/path selector.' }
    $requestBody = Get-D2JsonValue (Get-D2JsonValue $rule 'actions') 'requestBody'
    if ($null -eq $requestBody -or [bool](Get-D2JsonValue $requestBody 'declaredContract') -ne $true -or [string](Get-D2JsonValue $requestBody 'effectivePresence') -cne 'absent' -or [string](Get-D2JsonValue $requestBody 'observedCorrection') -cne $observedCorrection) { throw 'D2 DELETE correction action must preserve the exact absent-body evidence contract.' }
}

$correctionDocument = Get-Content -Raw -LiteralPath $correctionPath | ConvertFrom-Json
Assert-D2DeleteCorrectionContract $correctionDocument

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

$expectedOperationIds = @(
    'health-checks-create-health-check',
    'health-checks-delete-health-check',
    'health-checks-health-check-details',
    'health-checks-list-health-checks',
    'health-checks-patch-health-check',
    'health-checks-update-health-check'
)
$operationIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($operationId in $expectedOperationIds) { [void]$operationIds.Add($operationId) }

$openApi = [Cloudflare.Normalization.OpenApiLoader]::Load($schemaPath)
$normalized = [Cloudflare.Normalization.OpenApiNormalizer]::new($openApi).NormalizeOperations($operationIds)
$corrected = [Cloudflare.Normalization.ApiCorrectionEngine]::new($correctionPath).Apply($normalized)
$fixtureOperations = @($corrected.Operations)
if ($fixtureOperations.Count -ne $expectedOperationIds.Count) { throw "Expected exactly six normalized D2 operations, found $($fixtureOperations.Count)." }
if ((@($fixtureOperations | ForEach-Object OperationId | Sort-Object -Unique) -join '|') -ne (@($expectedOperationIds | Sort-Object) -join '|')) { throw 'D2 fixture operation identity is not exactly the requested six-operation slice.' }

$bodyIds = @('health-checks-create-health-check','health-checks-patch-health-check','health-checks-update-health-check')
foreach ($operation in $fixtureOperations) {
    $operationId = [string]$operation.OperationId
    if ([string]$operation.PathTemplate -notin @('/zones/{zone_id}/healthchecks','/zones/{zone_id}/healthchecks/{healthcheck_id}')) { throw "D2 operation '$operationId' escaped the fixed healthchecks path scope." }
    if (@($operation.ScopeBindings | Where-Object { [string]$_.ScopeType -eq 'Zone' -and [string]$_.Role -eq 'Parent' }).Count -ne 1) { throw "D2 operation '$operationId' does not have exactly one zone parent scope." }
    $body = if ($null -eq $operation.PSObject.Properties['RequestBody']) { $null } else { $operation.RequestBody }
    if ($bodyIds -contains $operationId) {
        if ($null -eq $body -or [string]$body.Presence -ne 'required' -or [string]$body.Representations[0].ContentType -ne 'application/json' -or [string]$body.Representations[0].Schema -ne 'healthchecks_query_healthcheck') { throw "D2 operation '$operationId' lost its required healthcheck JSON body contract." }
    } elseif ($operationId -eq 'health-checks-delete-health-check') {
        if ($null -eq $body -or [bool]$body.DeclaredContract -ne $true -or [bool]$body.Required -ne $true -or [string]$body.EffectivePresence -ne 'absent' -or [string]$body.Presence -ne 'declared-but-observed-absent') { throw 'D2 DELETE must preserve the correction that official wrappers send no body.' }
        if ([string]$body.ObservedCorrection -ne 'official-wrappers-send-no-body') { throw 'D2 DELETE correction evidence is missing.' }
        $representations = @($body.Representations)
        if (@($representations).Count -ne 1 -or [string]$representations[0].ContentType -cne 'application/json' -or -not [string]::IsNullOrWhiteSpace([string]$representations[0].Schema)) { throw 'D2 DELETE declared request representation drifted.' }
    } elseif ($null -ne $body) { throw "D2 read operation '$operationId' unexpectedly has a request body." }
    if (@($operation.Responses | Where-Object { [string]$_.StatusSelector.Kind -eq 'Exact' -and [string]$_.StatusSelector.Value -eq '200' } | ForEach-Object Representations | Where-Object { [string]$_.EnvelopePolicy -eq 'CloudflareResult' -and [string]$_.ContentType -eq 'application/json' -and [string]$_.ParsingMode -eq 'Json' }).Count -ne 1) { throw "D2 operation '$operationId' lacks its JSON CloudflareResult success response." }
    if (@($operation.Responses | Where-Object { [string]$_.StatusSelector.Kind -eq 'Class' -and [string]$_.StatusSelector.Value -eq '4XX' } | ForEach-Object Representations | Where-Object { [string]$_.EnvelopePolicy -eq 'ErrorEnvelope' -and [string]$_.ContentType -eq 'application/json' -and [string]$_.ParsingMode -eq 'Json' }).Count -lt 1) { throw "D2 operation '$operationId' lacks a normalized JSON error response." }
    $pathParameters = @($operation.Parameters | Where-Object { [string]$_.Location -eq 'path' } | ForEach-Object Name | Sort-Object)
    $expectedPathParameters = if ($operationId -in @('health-checks-create-health-check','health-checks-list-health-checks')) { @('zone_id') } else { @('healthcheck_id','zone_id') }
    if (($pathParameters -join '|') -ne ($expectedPathParameters -join '|')) { throw "D2 operation '$operationId' path parameter set is not exact." }
}
$list = @($fixtureOperations | Where-Object OperationId -eq 'health-checks-list-health-checks')[0]
if ([string]$list.Pagination.Strategy -ne 'V4PagePaginationArray' -or @($list.Parameters | Where-Object Name -in @('page','per_page')).Count -ne 2) { throw 'D2 list pagination facts are incomplete.' }

$selectedNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($operation in $fixtureOperations) {
    foreach ($parameter in @($operation.Parameters)) { if (-not [string]::IsNullOrWhiteSpace([string]$parameter.Schema)) { [void]$selectedNames.Add([string]$parameter.Schema) } }
    if ($null -ne $operation.RequestBody) { foreach ($representation in @($operation.RequestBody.Representations)) { if (-not [string]::IsNullOrWhiteSpace([string]$representation.Schema)) { [void]$selectedNames.Add([string]$representation.Schema) } } }
    foreach ($representation in @($operation.Responses | ForEach-Object Representations)) { if (-not [string]::IsNullOrWhiteSpace([string]$representation.Schema)) { [void]$selectedNames.Add([string]$representation.Schema) } }
}
$schemas = [ordered]@{}
$pending = [System.Collections.Generic.Queue[string]]::new()
foreach ($name in @($selectedNames | Sort-Object)) { $pending.Enqueue($name) }
while ($pending.Count -gt 0) {
    $name = $pending.Dequeue()
    if ($schemas.Contains($name)) { continue }
    if (-not $corrected.Schemas.ContainsKey($name)) { throw "D2 fixture references missing schema '$name'." }
    $schema = $corrected.Schemas[$name]
    $schemas[$name] = $schema
    $children = @($schema.Properties.Values | ForEach-Object Schema)
    if (-not [string]::IsNullOrWhiteSpace([string]$schema.Items)) { $children += [string]$schema.Items }
    if (-not [string]::IsNullOrWhiteSpace([string]$schema.AdditionalPropertiesSchema)) { $children += [string]$schema.AdditionalPropertiesSchema }
    $children += @($schema.OneOf) + @($schema.AnyOf) + @($schema.AllOf)
    foreach ($child in @($children | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)) { $pending.Enqueue([string]$child) }
}

$fixture = [Cloudflare.Normalization.NormalizedDocument]::new()
$fixture.Version = $corrected.Version
$fixture.SourcePath = $corrected.SourcePath
$fixture.SourceRevision = $corrected.SourceRevision
$fixture.Operations = [System.Collections.Generic.List[Cloudflare.Normalization.NormalizedOperation]]::new()
foreach ($operation in @($fixtureOperations | Sort-Object OperationId)) { $fixture.Operations.Add($operation) }
$fixture.Schemas = [System.Collections.Generic.Dictionary[string, Cloudflare.Normalization.NormalizedSchema]]::new([StringComparer]::Ordinal)
foreach ($name in @($schemas.Keys | Sort-Object)) { $fixture.Schemas.Add($name, $schemas[$name]) }
$json = [System.Text.Json.JsonSerializer]::Serialize($fixture, [Cloudflare.Normalization.NormalizedJson]::Options)
Write-Utf8CrLf $outputPath ($json + "`n")
Write-Output "PASS P3.3 D2 normalized fixture operations=$($fixture.Operations.Count) schemas=$($fixture.Schemas.Count) -> $outputPath"
