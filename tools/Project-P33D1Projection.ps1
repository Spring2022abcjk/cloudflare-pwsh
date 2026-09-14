[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$NormalizedPath = (Join-Path $ProjectRoot 'fixtures/p3.3/d1-database/document.json'),
    [string]$BaseProjectionPath = (Join-Path $ProjectRoot 'overrides/powershell-projection.json'),
    [string]$PolicyPath = (Join-Path $ProjectRoot 'overrides/powershell-p33-d1-projection.json'),
    [string]$FixtureScriptPath = (Join-Path $ProjectRoot 'tools/Generate-P33D1Fixture.ps1'),
    [string]$GeneratorPath = (Join-Path $ProjectRoot 'tools/Generate-P33D1Source.ps1'),
    [string]$TemplatePath = (Join-Path $ProjectRoot 'tools/templates/P32RepresentativeCmdlets.cs.tmpl'),
    [string]$ArtifactPath = (Join-Path $ProjectRoot 'artifacts/p3.3/CmdletModel.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$p33ProjectRoot = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
$p33NormalizedPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $NormalizedPath).Path)
$p33BaseProjectionPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $BaseProjectionPath).Path)
$p33PolicyPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $PolicyPath).Path)
$p33FixtureScriptPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $FixtureScriptPath).Path)
$p33GeneratorPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $GeneratorPath).Path)
$p33TemplatePath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $TemplatePath).Path)
$p33ArtifactPath = if ([IO.Path]::IsPathRooted($ArtifactPath)) { [IO.Path]::GetFullPath($ArtifactPath) } else { Join-Path $p33ProjectRoot $ArtifactPath }

$projectionLibrary = Join-Path $PSScriptRoot 'Project-P32Projection.ps1'
if (-not (Test-Path -LiteralPath $projectionLibrary -PathType Leaf)) { throw "Shared projection library is missing: $projectionLibrary" }
$rendererLibrary = Join-Path $PSScriptRoot 'Generate-P32Source.ps1'
if (-not (Test-Path -LiteralPath $rendererLibrary -PathType Leaf)) { throw "Shared source renderer is missing: $rendererLibrary" }
. $projectionLibrary -ProjectRoot $p33ProjectRoot -Library
$modelParityLibrary = Join-Path $PSScriptRoot 'P33ModelSchemaParity.ps1'
if (-not (Test-Path -LiteralPath $modelParityLibrary -PathType Leaf)) { throw "P3.3 model schema parity library is missing: $modelParityLibrary" }
. $modelParityLibrary

function Merge-ProjectionOperations {
    param([Parameter(Mandatory)][object[]]$Documents)
    $result = @{}
    foreach ($document in $Documents) {
        $operations = Get-P32PolicyValue $document 'operations'
        if ($null -eq $operations) { continue }
        foreach ($property in $operations.PSObject.Properties) {
            if (-not $result.ContainsKey($property.Name)) { $result[$property.Name] = [ordered]@{} }
            foreach ($child in $property.Value.PSObject.Properties) { $result[$property.Name][$child.Name] = $child.Value }
        }
    }
    return $result
}

function Assert-P33D1OperationFacts {
    param([Parameter(Mandatory)][object]$Operation)
    if ([string]$Operation.OperationId -notin @(
            'd1-create-database','d1-delete-database','d1-get-database',
            'd1-list-databases','d1-update-database','d1-update-partial-database')) {
        throw "P3.3 D1 fixture contains an operation outside the bounded slice: $($Operation.OperationId)."
    }
    if ([string]$Operation.Method -notin @('GET','POST','PUT','PATCH','DELETE')) { throw "P3.3 D1 operation '$($Operation.OperationId)' has an unsupported method." }
    if (@($Operation.ScopeBindings | Where-Object ScopeType -eq 'Account' | Where-Object Role -eq 'Parent').Count -ne 1) { throw "P3.3 D1 operation '$($Operation.OperationId)' does not have exactly one account parent scope." }
    if ([string]$Operation.OperationId -eq 'd1-list-databases' -and [string]$Operation.Pagination.Strategy -ne 'V4PagePaginationArray') { throw 'P3.3 D1 list lost its normalized page-array pagination fact.' }
    $bodyOperations = @('d1-create-database','d1-update-database','d1-update-partial-database')
    $body = if ($null -eq $Operation.PSObject.Properties['RequestBody']) { $null } else { $Operation.RequestBody }
    $hasBody = $null -ne $body
    if (($bodyOperations -contains [string]$Operation.OperationId) -ne $hasBody) { throw "P3.3 D1 operation '$($Operation.OperationId)' request-body presence is inconsistent with the bounded contract." }
    if ($hasBody -and [string]$body.Presence -ne 'required') { throw "P3.3 D1 operation '$($Operation.OperationId)' does not preserve required body presence." }
}

if (-not (Test-Path -LiteralPath $p33NormalizedPath -PathType Leaf)) { throw "P3.3 normalized fixture is missing: $p33NormalizedPath" }
foreach ($input in @($p33BaseProjectionPath, $p33PolicyPath, $p33FixtureScriptPath, $p33GeneratorPath, $p33TemplatePath)) {
    if (-not (Test-Path -LiteralPath $input -PathType Leaf)) { throw "P3.3 projection input is missing: $input" }
}

$normalized = Get-Content -Raw -LiteralPath $p33NormalizedPath | ConvertFrom-Json
$baseProjection = Get-Content -Raw -LiteralPath $p33BaseProjectionPath | ConvertFrom-Json
$policy = Get-Content -Raw -LiteralPath $p33PolicyPath | ConvertFrom-Json
if ([int]$policy.version -ne 1 -or [string]$policy.stage -ne 'P3.3' -or [string]$policy.slice -ne 'd1/database') { throw 'P3.3 D1 projection policy version, stage, or slice is unsupported.' }

$expectedOperationIds = @('d1-create-database','d1-delete-database','d1-get-database','d1-list-databases','d1-update-database','d1-update-partial-database')
$fixtureOperations = @($normalized.operations)
if ($fixtureOperations.Count -ne $expectedOperationIds.Count -or (@($fixtureOperations | ForEach-Object operationId | Sort-Object -Unique) -join '|') -ne (@($expectedOperationIds | Sort-Object) -join '|')) { throw 'P3.3 D1 normalized fixture must contain exactly the six bounded operation ids.' }
foreach ($operation in $fixtureOperations) { Assert-P33D1OperationFacts $operation }

$projectionOperations = Merge-ProjectionOperations @($baseProjection, $policy)
$schemas = @{}
foreach ($property in $normalized.schemas.PSObject.Properties) { $schemas[$property.Name] = $property.Value }
$cmdlets = [System.Collections.Generic.List[object]]::new()
$selected = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($commandPolicy in @($policy.commands)) {
    $commandOperations = [System.Collections.Generic.List[object]]::new()
    $operationPolicies = Get-P32PolicyValue $commandPolicy 'operations'
    if ($null -eq $operationPolicies) { throw "P3.3 command '$($commandPolicy.cmdletName)' has no operation policy." }
    foreach ($operationProperty in @($operationPolicies.PSObject.Properties | Sort-Object Name)) {
        $operation = @($fixtureOperations | Where-Object operationId -eq $operationProperty.Name)
        if ($operation.Count -ne 1) { throw "P3.3 command '$($commandPolicy.cmdletName)' references missing/duplicate operation '$($operationProperty.Name)'." }
        if (-not $selected.Add([string]$operationProperty.Name)) { throw "P3.3 operation '$($operationProperty.Name)' is projected more than once." }
        $commandOperations.Add((ConvertTo-OperationProjection $operation[0] $projectionOperations $schemas 'd1/database' $operationProperty.Value $commandPolicy))
    }
    if ($commandOperations.Count -eq 0) { throw "P3.3 command '$($commandPolicy.cmdletName)' has no operations." }
    $cmdlets.Add((ConvertTo-CmdletProjection $commandPolicy @($commandOperations) 'd1/database'))
}
if ($selected.Count -ne $expectedOperationIds.Count) { throw "P3.3 D1 projection selected $($selected.Count) operations instead of six." }
if (@($cmdlets).Count -ne 4) { throw "P3.3 D1 projection produced $(@($cmdlets).Count) cmdlets instead of four." }

$rawModels = [System.Collections.Generic.List[object]]::new()
foreach ($commandPolicy in @($policy.commands)) {
    $model = Get-P32PolicyValue $commandPolicy 'model'
    if ($null -ne $model) { $rawModels.Add($model) }
}
foreach ($model in @($policy.additionalModels)) { $rawModels.Add($model) }
if (@($rawModels | ForEach-Object className | Sort-Object -Unique).Count -ne @($rawModels).Count) { throw 'P3.3 D1 projection contains duplicate generated model classes.' }
$models = [System.Collections.Generic.List[object]]::new()
$normalizedSourcePath = [IO.Path]::GetRelativePath($p33ProjectRoot, $p33NormalizedPath).Replace('\', '/')
$objectAllowlist = Get-P32PolicyValue $policy 'objectTypeAllowlist'
foreach ($model in @($rawModels)) {
    $models.Add((ConvertTo-P33ModelProjection $model $schemas @($rawModels) $normalizedSourcePath $objectAllowlist))
}

$sourcePaths = @(
    (Join-Path $p33ProjectRoot 'ref/api-schemas/openapi.json'),
    (Join-Path $p33ProjectRoot 'overrides/api-corrections.json'),
    $p33NormalizedPath,
    $p33BaseProjectionPath,
    $p33PolicyPath,
    $p33FixtureScriptPath,
    $projectionLibrary,
    $rendererLibrary,
    $modelParityLibrary,
    $p33GeneratorPath,
    $p33TemplatePath,
    (Join-Path $p33ProjectRoot 'module/Cloudflare.PowerShell/Cloudflare.PowerShell.psd1'),
    (Join-Path $p33ProjectRoot 'module/Cloudflare.PowerShell/Cloudflare.PowerShell.psm1')
)
$sourceFiles = Get-P32SourceFiles $p33ProjectRoot $sourcePaths
$artifact = [ordered]@{
    version = 1
    stage = 'P3.3'
    sourcePolicy = 'normalized-model-plus-projection-policy'
    semanticAlgorithm = 'SHA256-CanonicalJson-v1'
    sourceFiles = $sourceFiles
    cmdlets = @($cmdlets)
    models = @($models)
    commonInfrastructureParameters = @('BaseUrl', 'Token', 'Handler')
}
$artifact.canonicalDigest = Get-P32CanonicalDigest $artifact
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p33ArtifactPath) | Out-Null
Write-Utf8CrLf $p33ArtifactPath (($artifact | ConvertTo-Json -Depth 100) + "`n")
Write-Output "PASS P3.3 D1 canonical projection: cmdlets=$(@($artifact.cmdlets).Count), operations=$(@($artifact.cmdlets | ForEach-Object operations).Count), models=$(@($artifact.models).Count)"
Write-Output "P3.3 canonical artifact: $p33ArtifactPath"
