[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$SchemaPath = (Join-Path $ProjectRoot 'ref/api-schemas/openapi.json'),
    [string]$CorrectionPath = (Join-Path $ProjectRoot 'overrides/api-corrections.json'),
    [string]$ProjectionPolicyPath = (Join-Path $ProjectRoot 'overrides/powershell-projection.json'),
    [string]$PublicArtifactPath = (Join-Path $ProjectRoot 'artifacts/p3.2/CmdletModel.json'),
    [string]$OutputRoot = (Join-Path $ProjectRoot 'artifacts/p3.3'),
    [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
$schemaPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $SchemaPath).Path)
$correctionPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $CorrectionPath).Path)
$projectionPolicyPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectionPolicyPath).Path)
$publicArtifactPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $PublicArtifactPath).Path)
$outputCandidate = if ([IO.Path]::IsPathRooted($OutputRoot)) { $OutputRoot } else { Join-Path $projectRoot $OutputRoot }
$outputRoot = [IO.Path]::GetFullPath($outputCandidate)

$hashHelper = Join-Path $PSScriptRoot 'P32Hash.ps1'
if (-not (Test-Path -LiteralPath $hashHelper -PathType Leaf)) { throw "P3.3 hash helper is missing: $hashHelper" }
. $hashHelper

function Invoke-Checked {
    param([Parameter(Mandatory)][string]$FilePath, [Parameter(Mandatory)][string[]]$Arguments)
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Command '$FilePath $($Arguments -join ' ')' failed with exit code $LASTEXITCODE." }
}

function Get-PropertyValue {
    param([object]$Object, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) { return $null }
    return $Object.PSObject.Properties[$Name].Value
}

function Get-JsonPropertyValue {
    param([object]$Object, [Parameter(Mandatory)][string]$Name)
    if ($Object -is [System.Text.Json.Nodes.JsonObject]) { return $Object[$Name] }
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) { return $Object[$Name] }
    return Get-PropertyValue $Object $Name
}

function Get-PolicyOperation {
    param([Parameter(Mandatory)][object]$Policy, [Parameter(Mandatory)][string]$OperationId)
    $operations = Get-JsonPropertyValue $Policy 'operations'
    if ($operations -is [System.Text.Json.Nodes.JsonObject]) { return $operations[$OperationId] }
    if ($null -eq $operations -or $null -eq $operations.PSObject.Properties[$OperationId]) { return $null }
    return $operations.PSObject.Properties[$OperationId].Value
}

function ConvertTo-PowerShellName {
    param([Parameter(Mandatory)][string]$Value)
    $parts = @($Value -split '[._-]' | Where-Object { $_ })
    if ($parts.Count -eq 0) { return 'Value' }
    $name = ($parts | ForEach-Object {
            if ($_.Length -eq 1) { $_.ToUpperInvariant() }
            else { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }
        }) -join ''
    if ($name[0] -match '[0-9]') { return "N_$name" }
    return $name
}

function Get-ProjectedName {
    param([Parameter(Mandatory)][object]$Policy, [Parameter(Mandatory)][string]$ApiName)
    $renames = Get-JsonPropertyValue $Policy 'parameterRenames'
    if ($null -ne $renames -and $null -ne $renames.PSObject.Properties[$ApiName]) {
        return [string]$renames.PSObject.Properties[$ApiName].Value
    }
    return ConvertTo-PowerShellName $ApiName
}

function Get-OperationRuntimeGaps {
    param([Parameter(Mandatory)][object]$Operation)
    $gaps = [System.Collections.Generic.List[string]]::new()
    if ([string]$Operation.Method -notin @('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS')) {
        $gaps.Add('UnsupportedHttpMethod')
    }

    $supportedRequestTypes = @('application/json', 'multipart/form-data')
    if ($null -ne $Operation.RequestBody) {
        foreach ($representation in @($Operation.RequestBody.Representations)) {
            if ([string]$representation.ContentType -notin $supportedRequestTypes) {
                $gaps.Add("UnsupportedRequestContentType:$($representation.ContentType)")
            }
        }
    }

    $supportedParsingModes = @('Json', 'Text', 'RawText', 'Binary', 'NoContent')
    foreach ($response in @($Operation.Responses)) {
        foreach ($representation in @($response.Representations)) {
            if ([string]$representation.ParsingMode -notin $supportedParsingModes) {
                $gaps.Add("UnsupportedResponseParsingMode:$($representation.ParsingMode)")
            }
            if ([string]$representation.EnvelopePolicy -notin @('CloudflareResult', 'ErrorEnvelope', 'Raw', 'None')) {
                $gaps.Add("UnsupportedResponseEnvelope:$($representation.EnvelopePolicy)")
            }
        }
    }

    $supportedPagination = @('SinglePage', 'V4PagePaginationArray', 'V4PagePagination', 'CursorPagination', 'CursorPaginationAfter', 'CursorLimitPagination')
    if ($null -ne $Operation.Pagination -and [string]$Operation.Pagination.Strategy -notin $supportedPagination) {
        $gaps.Add("UnsupportedPaginationStrategy:$($Operation.Pagination.Strategy)")
    }
    return @($gaps | Sort-Object -Unique)
}

function Get-ResourceFamily {
    param([Parameter(Mandatory)][object]$Operation)
    return (@($Operation.ResourcePath | ForEach-Object { [string]$_ }) -join '/')
}

function Get-OperationKey {
    param([Parameter(Mandatory)][object]$Operation)
    return "{0}|{1}|{2}" -f [string]$Operation.OperationId, [string]$Operation.Method, [string]$Operation.PathTemplate
}

function Get-StatusCounts {
    param([Parameter(Mandatory)][object[]]$Rows, [Parameter(Mandatory)][string]$Property)
    $result = [ordered]@{}
    foreach ($group in @($Rows | Group-Object $Property | Sort-Object Name)) { $result[[string]$group.Name] = $group.Count }
    return [pscustomobject]$result
}

function Write-Utf8CrLf {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
    [IO.File]::WriteAllText($Path, $normalized, [Text.UTF8Encoding]::new($false))
}

if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) { throw "Schema file is missing: $schemaPath" }
foreach ($required in @($correctionPath, $projectionPolicyPath, $publicArtifactPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required discovery input is missing: $required" }
}

$normalizationProject = Join-Path $projectRoot 'src/Cloudflare.Normalization/Cloudflare.Normalization.csproj'
$buildArguments = @('build', $normalizationProject, '--configuration', 'Release', '--nologo')
if ($SkipBuild) { $buildArguments += '--no-restore' }
else { $buildArguments += '--nologo' }
Invoke-Checked 'dotnet' $buildArguments

$normalizationAssembly = Join-Path $projectRoot 'src/Cloudflare.Normalization/bin/Release/net10.0/Cloudflare.Normalization.dll'
if (-not (Test-Path -LiteralPath $normalizationAssembly -PathType Leaf)) { throw "Normalization assembly is missing: $normalizationAssembly" }
Add-Type -Path $normalizationAssembly

$openApi = [Cloudflare.Normalization.OpenApiLoader]::Load($schemaPath)
$raw = [Cloudflare.Normalization.OpenApiNormalizer]::new($openApi).NormalizeOperations()
$corrected = [Cloudflare.Normalization.ApiCorrectionEngine]::new($correctionPath).Apply($raw)
$policyNode = [Text.Json.Nodes.JsonNode]::Parse((Get-Content -Raw -LiteralPath $projectionPolicyPath)).AsObject()
$publicArtifact = Get-Content -Raw -LiteralPath $publicArtifactPath | ConvertFrom-Json

$projectionNode = [Cloudflare.Normalization.Compatibility.ProjectionModelBuilder]::Build($corrected, $policyNode)
$projectionModel = $projectionNode.ToJsonString() | ConvertFrom-Json
$projectionRows = @($projectionModel.cmdlets | ForEach-Object {
        $cmdlet = $_
        @($_.parameterSets | ForEach-Object {
                [pscustomobject]@{
                    operationId = [string]$_.operationId
                    cmdletName = [string]$cmdlet.cmdletName
                    parameterSet = [string]$_.name
                }
            })
    })

$parameterNameCollisions = @([Cloudflare.Normalization.Compatibility.ProjectionModelBuilder]::FindNameCollisions($corrected, $policyNode))
$parameterCollisionByOperation = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($collision in $parameterNameCollisions) { [void]$parameterCollisionByOperation.Add([string]$collision.OperationId) }

$parameterSetCollisionByOperation = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$parameterSetCollisionRows = [System.Collections.Generic.List[object]]::new()
foreach ($cmdlet in @($projectionModel.cmdlets)) {
    foreach ($group in @($cmdlet.parameterSets | Group-Object name | Where-Object Count -gt 1 | Sort-Object Name)) {
        $operationIds = @($group.Group | ForEach-Object operationId | Sort-Object)
        foreach ($operationId in $operationIds) { [void]$parameterSetCollisionByOperation.Add([string]$operationId) }
        $parameterSetCollisionRows.Add([pscustomobject]@{
                cmdletName = [string]$cmdlet.cmdletName
                parameterSet = [string]$group.Name
                operationIds = $operationIds
                reason = 'multiple operations map to one cmdlet parameter-set name'
            })
    }
}

$publicByOperation = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
foreach ($cmdlet in @($publicArtifact.cmdlets)) {
    foreach ($operation in @($cmdlet.operations)) {
        $publicByOperation[[string]$operation.operationId] = [string]$cmdlet.cmdletName
    }
}

$rows = [System.Collections.Generic.List[object]]::new()
foreach ($operation in @($corrected.Operations | Sort-Object OperationId)) {
    $operationId = [string]$operation.OperationId
    $operationKey = Get-OperationKey $operation
    $operationPolicy = $policyNode['operations'][$operationId]
    $projection = @($projectionRows | Where-Object { [string]$_.operationId -ceq $operationId })
    $runtimeGaps = @(Get-OperationRuntimeGaps $operation)
    $reasonCodes = [System.Collections.Generic.List[string]]::new()
    $missingCapabilities = [System.Collections.Generic.List[string]]::new()
    $normalizationStatus = 'Succeeded'
    $correctionStatus = if (@($operation.CorrectionTrace).Count -gt 0) { 'Applied' } else { 'None' }
    $projectionStatus = if ($parameterCollisionByOperation.Contains($operationId) -or $parameterSetCollisionByOperation.Contains($operationId)) { 'Conflict' } elseif ($null -ne $operationPolicy) { 'PolicyAvailable' } else { 'DefaultAvailable' }
    $runtimeStatus = if ($runtimeGaps.Count -eq 0) { 'Ready' } else { 'Gap' }
    $publicCmdlet = if ($publicByOperation.ContainsKey($operationId)) { [string]$publicByOperation[$operationId] } else { $null }
    $projectionCmdlet = if ($projection.Count -gt 0) { [string]$projection[0].cmdletName } else { $null }
    $parameterSet = if ($projection.Count -eq 1) { [string]$projection[0].parameterSet } else { $null }

    if ($operation.OperationSemantic.Kind -eq 'Unknown') {
        $reasonCodes.Add('UnknownOperationSemantic')
        $missingCapabilities.Add('normalization.semantic.kind')
        $classification = 'AmbiguousSemantics'
    } elseif ($operation.OperationSemantic.Confidence -eq 'Low') {
        $reasonCodes.Add('LowSemanticConfidence')
        $missingCapabilities.Add('normalization.semantic.confidence')
        $classification = 'NeedsManualReview'
    } elseif ($parameterCollisionByOperation.Contains($operationId)) {
        $reasonCodes.Add('ProjectionParameterNameCollision')
        $missingCapabilities.Add('projection.parameter-name-collision-resolution')
        $classification = 'UnsupportedProjectionCapability'
    } elseif ($parameterSetCollisionByOperation.Contains($operationId)) {
        $reasonCodes.Add('ProjectionParameterSetCollision')
        $missingCapabilities.Add('projection.parameter-set-disambiguation')
        $classification = 'UnsupportedProjectionCapability'
    } elseif ($runtimeGaps.Count -gt 0) {
        foreach ($gap in $runtimeGaps) { $reasonCodes.Add($gap) }
        foreach ($gap in $runtimeGaps) { $missingCapabilities.Add(('runtime.' + ($gap -replace ':.*$', ''))) }
        $classification = 'UnsupportedRuntimeCapability'
    } elseif ($publicByOperation.ContainsKey($operationId)) {
        $reasonCodes.Add('CurrentPublicSurface')
        if ($null -ne $operationPolicy -or $correctionStatus -eq 'Applied') { $reasonCodes.Add('ExplicitPolicyOrCorrection'); $classification = 'SupportedWithOverride' }
        else { $classification = 'Supported' }
    } else {
        $reasonCodes.Add('OutsideCurrentPublicSurface')
        if ($null -ne $operationPolicy) { $reasonCodes.Add('ProjectionPolicyPresent') }
        else { $reasonCodes.Add('NoPublicProjectionPolicy') }
        $missingCapabilities.Add('p3.3.public-surface-admission')
        $classification = 'ExcludedByPolicy'
    }

    $rows.Add([pscustomobject][ordered]@{
            operationKey = $operationKey
            resourcePath = @($operation.ResourcePath | ForEach-Object { [string]$_ })
            resourceFamily = Get-ResourceFamily $operation
            operationId = $operationId
            method = [string]$operation.Method
            pathTemplate = [string]$operation.PathTemplate
            semanticKind = [string]$operation.OperationSemantic.Kind
            semanticSource = [string]$operation.OperationSemantic.Source
            semanticConfidence = [string]$operation.OperationSemantic.Confidence
            classification = $classification
            reasonCodes = @($reasonCodes | Sort-Object -Unique)
            missingCapabilities = @($missingCapabilities | Sort-Object -Unique)
            normalizedStatus = $normalizationStatus
            correctionStatus = $correctionStatus
            correctionRules = @($operation.CorrectionTrace | ForEach-Object RuleId | Sort-Object -Unique)
            projectionStatus = $projectionStatus
            projectionOverride = ($null -ne $operationPolicy)
            projectedCmdletName = $projectionCmdlet
            projectedParameterSet = $parameterSet
            runtimeStatus = $runtimeStatus
            runtimeGaps = $runtimeGaps
            currentPublicCmdlet = $publicCmdlet
            currentPublicSurface = ($null -ne $publicCmdlet)
        })
}

$sortedRows = @($rows | Sort-Object operationKey)
$classificationCounts = [ordered]@{}
foreach ($group in @($sortedRows | Group-Object classification | Sort-Object Name)) { $classificationCounts[[string]$group.Name] = $group.Count }
$resourceFamilyCounts = @($sortedRows | Group-Object resourceFamily | Sort-Object Name | ForEach-Object {
        $familyRows = @($_.Group)
        $counts = [ordered]@{}
        foreach ($group in @($familyRows | Group-Object classification | Sort-Object Name)) { $counts[[string]$group.Name] = $group.Count }
        [pscustomobject][ordered]@{ resourceFamily = [string]$_.Name; totalOperations = $familyRows.Count; classificationCounts = [pscustomobject]$counts }
    })
$capabilityGapCounts = [ordered]@{}
foreach ($group in @($sortedRows | ForEach-Object { $_.reasonCodes } | Group-Object | Sort-Object Name)) { $capabilityGapCounts[[string]$group.Name] = $group.Count }

$stageCounts = [ordered]@{
    normalizedSucceeded = @($sortedRows | Where-Object normalizedStatus -eq 'Succeeded').Count
    correctionApplied = @($sortedRows | Where-Object correctionStatus -eq 'Applied').Count
    projectionReady = @($sortedRows | Where-Object projectionStatus -ne 'Conflict').Count
    projectionConflicts = @($sortedRows | Where-Object projectionStatus -eq 'Conflict').Count
    runtimeReady = @($sortedRows | Where-Object runtimeStatus -eq 'Ready').Count
    runtimeGaps = @($sortedRows | Where-Object runtimeStatus -eq 'Gap').Count
    currentPublicSurface = @($sortedRows | Where-Object currentPublicSurface).Count
    fullyEligibleCurrentOperations = @($sortedRows | Where-Object classification -in @('Supported', 'SupportedWithOverride')).Count
}

$inputIdentity = [ordered]@{
    source = [ordered]@{
        path = [IO.Path]::GetRelativePath($projectRoot, $schemaPath).Replace('\', '/')
        revision = [string]$openApi.SourceRevision
        sha256 = Get-P32PortableFileHash -Path $schemaPath
    }
    corrections = [ordered]@{
        path = [IO.Path]::GetRelativePath($projectRoot, $correctionPath).Replace('\', '/')
        sha256 = Get-P32PortableFileHash -Path $correctionPath
    }
    projectionPolicy = [ordered]@{
        path = [IO.Path]::GetRelativePath($projectRoot, $projectionPolicyPath).Replace('\', '/')
        sha256 = Get-P32PortableFileHash -Path $projectionPolicyPath
    }
    publicArtifact = [ordered]@{
        path = [IO.Path]::GetRelativePath($projectRoot, $publicArtifactPath).Replace('\', '/')
        sha256 = Get-P32PortableFileHash -Path $publicArtifactPath
    }
}

$report = [pscustomobject][ordered]@{
    schemaVersion = 1
    stage = 'P3.3'
    sourcePath = [IO.Path]::GetRelativePath($projectRoot, $schemaPath).Replace('\', '/')
    sourceRevision = [string]$openApi.SourceRevision
    deterministic = $true
    generatedAt = $null
    normalizedSchemaCount = $corrected.Schemas.Count
    totalOperations = $sortedRows.Count
    countSemantics = [pscustomobject][ordered]@{
        normalizedSchemaCount = $corrected.Schemas.Count
        runtimeReadyStageCount = $stageCounts.runtimeReady
        finalUnsupportedRuntimeCapabilityCount = @($sortedRows | Where-Object classification -eq 'UnsupportedRuntimeCapability').Count
    }
    inputIdentity = [pscustomobject]$inputIdentity
    stageCounts = [pscustomobject]$stageCounts
    classificationCounts = [pscustomobject]$classificationCounts
    capabilityGapCounts = [pscustomobject]$capabilityGapCounts
    resourceFamilyCounts = $resourceFamilyCounts
    operations = $sortedRows
}

$jsonPath = Join-Path $outputRoot 'coverage-baseline.json'
$markdownPath = Join-Path $outputRoot 'coverage-baseline.md'
Write-Utf8CrLf $jsonPath (($report | ConvertTo-Json -Depth 100) + "`n")

$markdown = [Text.StringBuilder]::new()
[void]$markdown.AppendLine('# P3.3 Coverage Baseline')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('- Source revision: `' + $report.sourceRevision + '`')
[void]$markdown.AppendLine('- Source: `' + $report.sourcePath + '`')
[void]$markdown.AppendLine('- Normalized schema count: `' + $report.normalizedSchemaCount + '`')
[void]$markdown.AppendLine('- Operations: `' + $report.totalOperations + '`')
[void]$markdown.AppendLine('- Runtime-ready stage count (operations): `' + $report.countSemantics.runtimeReadyStageCount + '`')
[void]$markdown.AppendLine('- Final `UnsupportedRuntimeCapability` classification count: `' + $report.countSemantics.finalUnsupportedRuntimeCapabilityCount + '`')
[void]$markdown.AppendLine('- Input identity: source `' + $report.inputIdentity.source.path + '` revision `' + $report.inputIdentity.source.revision + '` SHA-256 `' + $report.inputIdentity.source.sha256 + '`')
[void]$markdown.AppendLine('- Input identity: corrections `' + $report.inputIdentity.corrections.path + '` SHA-256 `' + $report.inputIdentity.corrections.sha256 + '`')
[void]$markdown.AppendLine('- Input identity: projection policy `' + $report.inputIdentity.projectionPolicy.path + '` SHA-256 `' + $report.inputIdentity.projectionPolicy.sha256 + '`')
[void]$markdown.AppendLine('- Input identity: current public artifact `' + $report.inputIdentity.publicArtifact.path + '` SHA-256 `' + $report.inputIdentity.publicArtifact.sha256 + '`')
[void]$markdown.AppendLine('- Deterministic artifact: `true`; generation timestamp intentionally omitted')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('## Stage counts')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('| Stage | Count |')
[void]$markdown.AppendLine('| --- | ---: |')
foreach ($property in $stageCounts.Keys) { [void]$markdown.AppendLine('| ' + $property + ' | ' + $stageCounts[$property] + ' |') }
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('## Final classification')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('| Classification | Count |')
[void]$markdown.AppendLine('| --- | ---: |')
foreach ($property in $classificationCounts.Keys) { [void]$markdown.AppendLine('| ' + $property + ' | ' + $classificationCounts[$property] + ' |') }
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('## Capability gaps and review reasons')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('| Reason | Operations |')
[void]$markdown.AppendLine('| --- | ---: |')
foreach ($property in $capabilityGapCounts.Keys) { [void]$markdown.AppendLine('| `' + $property + '` | ' + $capabilityGapCounts[$property] + ' |') }
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('## Resource families')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('| Resource family | Operations | Classification counts |')
[void]$markdown.AppendLine('| --- | ---: | --- |')
foreach ($family in $resourceFamilyCounts) {
    $counts = @($family.classificationCounts.PSObject.Properties | ForEach-Object { $_.Name + '=' + $_.Value }) -join '; '
    [void]$markdown.AppendLine('| `' + $family.resourceFamily + '` | ' + $family.totalOperations + ' | ' + $counts + ' |')
}
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('## Current supported operations')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('| Operation | Cmdlet | Classification |')
[void]$markdown.AppendLine('| --- | --- | --- |')
foreach ($row in @($sortedRows | Where-Object classification -in @('Supported', 'SupportedWithOverride'))) {
    [void]$markdown.AppendLine('| `' + $row.operationId + '` | `' + $row.currentPublicCmdlet + '` | ' + $row.classification + ' |')
}
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('## Runtime gaps')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('The JSON report contains every affected operation. The table below shows the first 100 deterministically sorted examples.')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('| Operation | Resource family | Runtime gaps |')
[void]$markdown.AppendLine('| --- | --- | --- |')
foreach ($row in @($sortedRows | Where-Object runtimeStatus -eq 'Gap' | Select-Object -First 100)) {
    [void]$markdown.AppendLine('| `' + $row.operationId + '` | `' + $row.resourceFamily + '` | ' + (@($row.runtimeGaps) -join ', ') + ' |')
}
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('## Projection gaps')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('The JSON report contains every affected operation. The table below shows the first 100 deterministically sorted examples.')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('| Operation | Resource family | Reason |')
[void]$markdown.AppendLine('| --- | --- | --- |')
foreach ($row in @($sortedRows | Where-Object classification -eq 'UnsupportedProjectionCapability' | Select-Object -First 100)) {
    [void]$markdown.AppendLine('| `' + $row.operationId + '` | `' + $row.resourceFamily + '` | ' + (@($row.reasonCodes) -join ', ') + ' |')
}
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('## Normalization gaps')
[void]$markdown.AppendLine()
$normalizationGaps = @($sortedRows | Where-Object normalizedStatus -ne 'Succeeded')
if ($normalizationGaps.Count -eq 0) {
    [void]$markdown.AppendLine('None in this baseline. The category remains part of the report contract for future schema/model failures.')
} else {
    foreach ($row in @($normalizationGaps | Select-Object -First 100)) { [void]$markdown.AppendLine('- `' + $row.operationId + '`: ' + (@($row.reasonCodes) -join ', ')) }
}
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('## Operations with explicit projection policy')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('These operations have an entry in the current projection policy. Policy presence is not equivalent to current public admission.')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('| Operation | Projected cmdlet | Current public cmdlet | Classification |')
[void]$markdown.AppendLine('| --- | --- | --- | --- |')
foreach ($row in @($sortedRows | Where-Object projectionOverride)) {
    $current = if ([string]::IsNullOrWhiteSpace([string]$row.currentPublicCmdlet)) { '-' } else { [string]$row.currentPublicCmdlet }
    [void]$markdown.AppendLine('| `' + $row.operationId + '` | `' + $row.projectedCmdletName + '` | `' + $current + '` | ' + $row.classification + ' |')
}
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('## Manual review')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('The JSON report contains every affected operation. The table below shows the first 100 deterministically sorted examples.')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('| Operation | Resource family | Reason |')
[void]$markdown.AppendLine('| --- | --- | --- |')
foreach ($row in @($sortedRows | Where-Object classification -in @('NeedsManualReview', 'AmbiguousSemantics') | Select-Object -First 100)) {
    [void]$markdown.AppendLine('| `' + $row.operationId + '` | `' + $row.resourceFamily + '` | ' + (@($row.reasonCodes) -join ', ') + ' |')
}
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('## Scope interpretation')
[void]$markdown.AppendLine()
[void]$markdown.AppendLine('`Supported` and `SupportedWithOverride` mean current public-surface operations pass this discovery gate. `ExcludedByPolicy` means the operation is not admitted to the bounded P3.2 public policy; it is not a claim that the operation is permanently unsupported. Normalization success and projection construction are reported separately and are not sufficient for final support.')

Write-Utf8CrLf $markdownPath $markdown.ToString()
Write-Output "PASS P3.3 coverage discovery operations=$($report.totalOperations) schemas=$($report.normalizedSchemaCount) -> $jsonPath"
Write-Output "PASS P3.3 coverage Markdown -> $markdownPath"
