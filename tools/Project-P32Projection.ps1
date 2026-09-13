[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$DnsNormalizedPath = (Join-Path $ProjectRoot 'artifacts/generated-normalized/document.json'),
    [string]$ZoneNormalizedPath = (Join-Path $ProjectRoot 'fixtures/p2.1/zones/document.json'),
    [string]$ZoneProjectionPath = (Join-Path $ProjectRoot 'artifacts/p2.3/projection/zones.json'),
    [string]$ProjectionPath = (Join-Path $ProjectRoot 'overrides/powershell-projection.json'),
    [string]$P23ProjectionPath = (Join-Path $ProjectRoot 'overrides/powershell-p23-projection.json'),
    [string]$P32PolicyPath = (Join-Path $ProjectRoot 'overrides/powershell-p32-projection.json'),
    [string]$ArtifactPath = (Join-Path $ProjectRoot 'artifacts/p3.2/CmdletModel.json'),
    [switch]$Library
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-JsonValue {
    param([AllowNull()][object]$Object, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Copy-JsonObject {
    param([Parameter(Mandatory)][object]$Object)
    return ($Object | ConvertTo-Json -Depth 100 | ConvertFrom-Json)
}

function ConvertTo-PowerShellName {
    param([Parameter(Mandatory)][string]$Value)
    $parts = $Value -split '[._-]' | Where-Object { $_ }
    if (@($parts).Count -eq 0) { return 'Value' }
    $name = (@($parts) | ForEach-Object {
        if ($_.Length -eq 1) { $_.ToUpperInvariant() }
        else { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }
    }) -join ''
    if ($name[0] -match '[0-9]') { return "N_$name" }
    return $name
}

function Get-OperationOverride {
    param([Parameter(Mandatory)][hashtable]$Operations, [Parameter(Mandatory)][string]$OperationId)
    if ($Operations.ContainsKey($OperationId)) { return $Operations[$OperationId] }
    return [pscustomobject]@{}
}

function Get-ProjectedName {
    param([Parameter(Mandatory)][object]$Parameter, [Parameter(Mandatory)][object]$Override)
    $renames = Get-JsonValue $Override 'parameterRenames'
    if ($null -ne $renames) {
        $rename = $renames.PSObject.Properties[[string]$Parameter.name]
        if ($null -ne $rename) { return [string]$rename.Value }
    }
    return ConvertTo-PowerShellName ([string]$Parameter.name)
}

function ConvertTo-CSharpType {
    param([Parameter(Mandatory)][object]$Parameter, [Parameter(Mandatory)][hashtable]$Schemas)
    $schemaName = [string]$Parameter.schema
    $schema = if ($Schemas.ContainsKey($schemaName)) { $Schemas[$schemaName] } else { $null }
    $primitive = [string](Get-JsonValue $schema 'primitiveType')
    switch ($primitive) {
        'string' { return 'string?' }
        'integer' { return 'int' }
        'number' { return 'decimal' }
        'boolean' { return 'bool' }
        'array' { return 'string[]?' }
        default { return 'string?' }
    }
}

function Get-PathOrder {
    param([Parameter(Mandatory)][string]$PathTemplate, [Parameter(Mandatory)][string]$ApiName)
    $matches = [regex]::Matches($PathTemplate, '\{([^}]+)\}')
    for ($index = 0; $index -lt $matches.Count; $index++) {
        if ($matches[$index].Groups[1].Value -eq $ApiName) { return $index }
    }
    return $null
}

function Get-ScopeBinding {
    param([Parameter(Mandatory)][object]$Operation, [Parameter(Mandatory)][string]$ApiName)
    return @($Operation.scopeBindings | Where-Object parameterName -eq $ApiName | Select-Object -First 1)
}

function Get-HelpModel {
    param([Parameter(Mandatory)][string]$CmdletName, [Parameter(Mandatory)][object]$Override, [Parameter(Mandatory)][string]$OperationKind, [Parameter(Mandatory)][string]$OperationId)
    $explicit = Get-JsonValue $Override 'help'
    if ($null -ne $explicit) {
        return [ordered]@{
            synopsis = [string]$explicit.synopsis
            description = [string]$explicit.description
            source = 'Override'
        }
    }
    $help = [ordered]@{
        synopsis = "$CmdletName $($OperationKind.ToLowerInvariant()) operation."
        description = "Generated help for normalized operation '$OperationId'."
    }
    $help.source = 'DeterministicDefault'
    return $help
}

function Get-ImpactRank {
    param([string]$Impact)
    switch ($Impact) {
        'None' { return 0 }
        'Low' { return 1 }
        'Medium' { return 2 }
        'High' { return 3 }
        default { return 0 }
    }
}

function Get-P32PolicyValue {
    param([AllowNull()][object]$Policy, [Parameter(Mandatory)][string]$Name)
    return Get-JsonValue $Policy $Name
}

function Get-P32OperationPolicy {
    param([Parameter(Mandatory)][object]$CommandPolicy, [Parameter(Mandatory)][string]$OperationId)
    $operations = Get-P32PolicyValue $CommandPolicy 'operations'
    if ($null -eq $operations) { throw "P3.2 command '$($CommandPolicy.cmdletName)' has no operation policy." }
    $property = $operations.PSObject.Properties[$OperationId]
    if ($null -eq $property) { throw "P3.2 command '$($CommandPolicy.cmdletName)' has no policy for operation '$OperationId'." }
    return $property.Value
}

function Get-P32CanonicalSemanticObject {
    param([Parameter(Mandatory)][object]$Artifact)
    $properties = [ordered]@{}
    foreach ($name in @('version', 'stage', 'sourcePolicy', 'semanticAlgorithm', 'sourceFiles', 'cmdlets', 'models', 'commonInfrastructureParameters')) {
        $value = Get-JsonValue $Artifact $name
        if ($null -ne $value) { $properties[$name] = $value }
    }
    return $properties
}

function ConvertTo-P32CanonicalValue {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in @($Value.Keys | Sort-Object)) { $result[[string]$key] = ConvertTo-P32CanonicalValue $Value[$key] }
        return $result
    }
    if ($Value -is [pscustomobject]) {
        $result = [ordered]@{}
        foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) { $result[$property.Name] = ConvertTo-P32CanonicalValue $property.Value }
        return $result
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        return @($Value | ForEach-Object { ConvertTo-P32CanonicalValue $_ })
    }
    return $Value
}

function Get-P32CanonicalDigest {
    param([Parameter(Mandatory)][object]$Artifact)
    $semantic = ConvertTo-P32CanonicalValue (Get-P32CanonicalSemanticObject $Artifact)
    $json = $semantic | ConvertTo-Json -Depth 100 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    return ([Security.Cryptography.SHA256]::HashData($bytes) | ForEach-Object ToString x2) -join ''
}

function Get-P32SourceFiles {
    param([Parameter(Mandatory)][string]$ProjectRoot, [Parameter(Mandatory)][string[]]$Paths)
    return @($Paths | ForEach-Object {
        if (-not (Test-Path -LiteralPath $_ -PathType Leaf)) { throw "P3.2 projection input is missing: $_" }
        [ordered]@{
            path = [IO.Path]::GetRelativePath($ProjectRoot, $_).Replace('\', '/')
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash.ToLowerInvariant()
        }
    })
}

function Get-BodyProjection {
    param([Parameter(Mandatory)][object]$Operation, [AllowNull()][object]$OperationPolicy)
    $requestBody = Get-JsonValue $Operation 'requestBody'
    if ($null -eq $requestBody) { return $null }
    $presence = [string](Get-JsonValue $requestBody 'presence')
    $effectivePresence = [string](Get-JsonValue $requestBody 'effectivePresence')
    if ($presence -eq 'declared-but-observed-absent' -or $effectivePresence -eq 'absent') { return $null }
    $representation = @($requestBody.representations | Select-Object -First 1)
    if ($representation.Count -ne 1) { return $null }
    $parameterName = [string](Get-P32PolicyValue $OperationPolicy 'bodyParameterName')
    if ([string]::IsNullOrWhiteSpace($parameterName)) { throw "P3.2 body operation '$($Operation.operationId)' has no declared bodyParameterName." }
    $parameterType = [string](Get-P32PolicyValue $OperationPolicy 'bodyParameterType')
    if ([string]::IsNullOrWhiteSpace($parameterType)) { throw "P3.2 body operation '$($Operation.operationId)' has no declared bodyParameterType." }
    return [ordered]@{
        parameterName = $parameterName
        parameterType = $parameterType
        model = [string]$representation.schema
        required = [bool]$requestBody.required
        contentType = [string]$representation.contentType
        parts = if ($null -eq (Get-JsonValue $representation 'parts')) { @() } else {
            @((Get-JsonValue $representation 'parts') | ForEach-Object {
                [ordered]@{
                    parameterName = [string]$_.parameterName
                    partName = [string]$_.partName
                    contentType = [string]$_.contentType
                    format = [string]$_.format
                    required = [bool]$_.required
                }
            })
        }
        serialization = if ([string]::IsNullOrWhiteSpace([string](Get-P32PolicyValue $OperationPolicy 'bodySerialization'))) { 'Value' } else { [string](Get-P32PolicyValue $OperationPolicy 'bodySerialization') }
    }
}

function ConvertTo-OperationProjection {
    param([Parameter(Mandatory)][object]$Operation, [Parameter(Mandatory)][hashtable]$ProjectionOperations, [Parameter(Mandatory)][hashtable]$Schemas, [Parameter(Mandatory)][string]$Resource, [Parameter(Mandatory)][object]$OperationPolicy, [Parameter(Mandatory)][object]$CommandPolicy)
    $operationId = [string]$Operation.operationId
    $override = Get-OperationOverride $ProjectionOperations $operationId
    $policyParameterSet = Get-P32PolicyValue $OperationPolicy 'parameterSet'
    $parameterSet = if ($null -ne $policyParameterSet) { [string]$policyParameterSet } elseif ($null -ne (Get-JsonValue $override 'parameterSet')) { [string]$override.parameterSet } else { [string]$Operation.operationSemantic.kind }
    $projectedParameters = @($Operation.parameters | Sort-Object location, name | ForEach-Object {
        $scope = @(Get-ScopeBinding $Operation ([string]$_.name))
        $publicName = Get-ProjectedName $_ $override
        $isParentScope = [bool](Get-JsonValue $_ 'isParentScopeId') -or ($scope.Count -eq 1 -and [string]$scope[0].role -eq 'Parent')
        $isPrimaryScope = [bool](Get-JsonValue $_ 'isPrimaryResourceId') -or ($scope.Count -eq 1 -and [string]$scope[0].role -eq 'Primary')
        $parameterOverride = Get-JsonValue $override 'parameters'
        $parameterPolicy = if ($null -ne $parameterOverride -and $null -ne $parameterOverride.PSObject.Properties[[string]$_.name]) { $parameterOverride.PSObject.Properties[[string]$_.name].Value } else { [pscustomobject]@{} }
        $position = Get-JsonValue $parameterPolicy 'position'
        if ($null -eq $position -and [string]$_.location -eq 'path') { $position = Get-PathOrder ([string]$Operation.pathTemplate) ([string]$_.name) }
        $csharpType = [string](Get-P32PolicyValue $parameterPolicy 'type')
        $typeOverrides = Get-P32PolicyValue $OperationPolicy 'typeOverrides'
        if ([string]::IsNullOrWhiteSpace($csharpType) -and $null -ne $typeOverrides -and $null -ne $typeOverrides.PSObject.Properties[[string]$_.name]) {
            $csharpType = [string]$typeOverrides.PSObject.Properties[[string]$_.name].Value
        }
        if ([string]::IsNullOrWhiteSpace($csharpType)) { $csharpType = ConvertTo-CSharpType $_ $Schemas }
        [ordered]@{
            name = $publicName
            sourceName = [string]$_.name
            type = $csharpType
            binding = [string]$_.location
            position = if ($null -eq $position) { $null } else { [int]$position }
            appliesTo = @($parameterSet)
            requiredIn = if ([bool]$_.required) { @($parameterSet) } else { @() }
            valueFromPipeline = [bool](Get-JsonValue $parameterPolicy 'valueFromPipeline')
            valueFromPipelineByPropertyName = $isParentScope -or $isPrimaryScope
            nullPolicy = [string]$_.nullPolicy
            defaultValue = Get-JsonValue $_ 'defaultValue'
            aliases = @()
            apiBindings = @([ordered]@{ operationId = $operationId; location = [string]$_.location; name = [string]$_.name })
            help = [ordered]@{ description = "Binds to API $($_.location) parameter '$($_.name)'."; source = 'DeterministicDefault' }
            isBody = $false
            scopeRole = if ($isPrimaryScope) { 'Primary' } elseif ($isParentScope) { 'Parent' } else { $null }
        }
    })
    $body = Get-BodyProjection $Operation $OperationPolicy
    if ($null -ne $body) {
        $projectedParameters += [ordered]@{
            name = $body.parameterName
            sourceName = 'body'
            type = $body.parameterType
            binding = 'body'
            position = if (@($projectedParameters | Where-Object binding -eq 'path').Count -gt 0) { [int]((@($projectedParameters | Where-Object binding -eq 'path' | ForEach-Object position | Measure-Object -Maximum).Maximum) + 1) } else { 0 }
            appliesTo = @($parameterSet)
            requiredIn = if ($body.required) { @($parameterSet) } else { @() }
            valueFromPipeline = $false
            valueFromPipelineByPropertyName = $false
             nullPolicy = 'reject-null'
             defaultValue = $null
             initializerPolicy = 'null-forgiving'
             aliases = @()
            apiBindings = @([ordered]@{ operationId = $operationId; location = 'body'; name = 'body' })
            help = [ordered]@{ description = "Binds the normalized $($body.model) request body."; source = 'DeterministicDefault' }
            isBody = $true
            bodyModel = $body.model
            scopeRole = $null
        }
    }
    $runtimeParameters = @($Operation.parameters | Sort-Object location, name | ForEach-Object {
        [ordered]@{
            name = [string]$_.name
            location = [string]$_.location
            required = [bool]$_.required
        }
    })
    $requestRepresentations = if ($null -ne $body) {
        @([ordered]@{
            contentType = $body.contentType
            bodyParameterName = 'body'
            parts = @($body.parts)
        })
    } else { @() }
    $responseRepresentations = @($Operation.responses | ForEach-Object {
        $case = $_
        $status = Get-JsonValue $case.statusSelector 'value'
        $statusCode = $null
        if ([string]$case.statusSelector.kind -eq 'Exact') { $statusCode = [int]$status }
        @($case.representations | ForEach-Object {
            [ordered]@{
                statusCode = $statusCode
                contentType = [string]$_.contentType
                envelopePolicy = [string]$_.envelopePolicy
                parsingMode = [string]$_.parsingMode
            }
        })
    })
    $pagination = $Operation.pagination
    $paginationModel = if ($null -eq $pagination) { $null } else {
        $strategy = [string]$pagination.strategy
        [ordered]@{
            strategy = $strategy
            requestFields = if ($strategy -eq 'V4PagePaginationArray') { @('page', 'per_page') } else { @($pagination.requestFields) }
            responseFields = if ($strategy -eq 'V4PagePaginationArray') { @('result', 'result_info') } else { @($pagination.responseFields) }
            resultPath = if ($strategy -eq 'V4PagePaginationArray') { 'result' } else { $null }
            pageInfoPath = if ($strategy -eq 'V4PagePaginationArray') { 'result_info' } else { $null }
             currentPagePath = if ($strategy -eq 'V4PagePaginationArray') { 'result_info.page' } else { $null }
             totalPagesPath = if ($strategy -eq 'V4PagePaginationArray') { 'result_info.total_pages' } else { $null }
             nextCursorPath = if ($null -ne (Get-JsonValue $pagination 'nextCursorPath')) { [string](Get-JsonValue $pagination 'nextCursorPath') } else { $null }
             hasMorePath = if ($null -ne (Get-JsonValue $pagination 'hasMorePath')) { [string](Get-JsonValue $pagination 'hasMorePath') } else { $null }
             nextPageRule = if ($strategy -eq 'V4PagePaginationArray') { 'page + 1' } else { [string]$pagination.nextPageRule }
            stopRule = [string]$pagination.stopRule
        }
    }
    $operationOutputType = Get-JsonValue $override 'outputType'
    if ([string]::IsNullOrWhiteSpace([string]$operationOutputType)) { $operationOutputType = [string](Get-P32PolicyValue $CommandPolicy 'outputType') }
    if ([string]::IsNullOrWhiteSpace([string]$operationOutputType)) { throw "P3.2 operation '$operationId' has no outputType projection." }
    $operationOutputPolicy = Get-JsonValue $override 'outputPolicy'
    if ([string]::IsNullOrWhiteSpace([string]$operationOutputPolicy)) { $operationOutputPolicy = Get-P32PolicyValue $OperationPolicy 'outputPolicy' }
    if ([string]::IsNullOrWhiteSpace([string]$operationOutputPolicy)) { $operationOutputPolicy = Get-P32PolicyValue $CommandPolicy 'outputPolicy' }
    if ([string]::IsNullOrWhiteSpace([string]$operationOutputPolicy)) { throw "P3.2 operation '$operationId' has no outputPolicy projection." }
    $supportsShouldProcess = Get-JsonValue $override 'supportsShouldProcess'
    $confirmImpact = Get-JsonValue $override 'confirmImpact'
    if ($null -eq $supportsShouldProcess) { $supportsShouldProcess = $false }
    if ($null -eq $confirmImpact) { $confirmImpact = 'None' }
    [ordered]@{
        operationId = $operationId
        resource = $Resource
        parameterSet = $parameterSet
        method = [string]$Operation.method
        pathTemplate = [string]$Operation.pathTemplate
        semantic = $Operation.operationSemantic
        parameters = $projectedParameters
        bodyParameterName = if ($null -eq $body) { $null } else { $body.parameterName }
        bodyModel = if ($null -eq $body) { $null } else { $body.model }
         outputType = [string]$operationOutputType
         constantName = [string](Get-P32PolicyValue $OperationPolicy 'constantName')
         outputPolicy = [string]$operationOutputPolicy
         invokeKind = if ($null -ne (Get-P32PolicyValue $OperationPolicy 'invokeKind')) { [string](Get-P32PolicyValue $OperationPolicy 'invokeKind') } elseif ($null -ne $paginationModel -and [string]$paginationModel.strategy -ne 'SinglePage') { 'paged' } else { 'single' }
         bodySerialization = if ($null -eq $body) { $null } else { [string]$body.serialization }
         errorTarget = [string](Get-P32PolicyValue $OperationPolicy 'errorTarget')
        supportsShouldProcess = [bool]$supportsShouldProcess
        confirmImpact = [string]$confirmImpact
        help = Get-HelpModel "$($override.verb)-$($override.noun)" $override ([string]$Operation.operationSemantic.kind) $operationId
        runtime = [ordered]@{
            parameters = $runtimeParameters
            requestRepresentations = $requestRepresentations
            responseRepresentations = $responseRepresentations
            pagination = $paginationModel
        }
    }
}

function Merge-ParameterVariants {
    param([Parameter(Mandatory)][object[]]$Variants)
    $first = $Variants[0]
    $appliesTo = @($Variants | ForEach-Object { $_.appliesTo } | Sort-Object -Unique)
    $requiredIn = @($Variants | ForEach-Object { $_.requiredIn } | Sort-Object -Unique)
    $aliases = @($Variants | ForEach-Object { $_.aliases } | Sort-Object -Unique)
    $apiBindings = @($Variants | ForEach-Object { $_.apiBindings } | Sort-Object operationId, name)
    [ordered]@{
        name = [string]$first.name
        type = [string]$first.type
        binding = [string]$first.binding
        position = $first.position
        appliesTo = $appliesTo
        requiredIn = $requiredIn
        valueFromPipeline = @($Variants | Where-Object valueFromPipeline).Count -gt 0
        valueFromPipelineByPropertyName = @($Variants | Where-Object valueFromPipelineByPropertyName).Count -gt 0
        nullPolicy = [string]$first.nullPolicy
        defaultValue = $first.defaultValue
        initializerPolicy = [string](Get-JsonValue $first 'initializerPolicy')
        aliases = $aliases
        apiBindings = $apiBindings
        help = $first.help
        isBody = @($Variants | Where-Object isBody).Count -gt 0
        bodyModel = ($Variants | Where-Object isBody | Select-Object -First 1 | ForEach-Object { [string]$_.bodyModel })
        scopeRole = ($Variants | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.scopeRole) } | Select-Object -First 1 | ForEach-Object { [string]$_.scopeRole })
    }
}

function ConvertTo-CmdletProjection {
    param([Parameter(Mandatory)][object]$CommandPolicy, [Parameter(Mandatory)][object[]]$Operations, [Parameter(Mandatory)][string]$Resource)
    $cmdletName = [string]$CommandPolicy.cmdletName
    $bindings = @($Operations | Sort-Object parameterSet, operationId)
    $parameterGroups = @{}
    foreach ($operation in $bindings) {
        foreach ($parameter in @($operation.parameters)) {
            if (-not $parameterGroups.ContainsKey([string]$parameter.name)) { $parameterGroups[[string]$parameter.name] = [System.Collections.Generic.List[object]]::new() }
            $parameterGroups[[string]$parameter.name].Add($parameter)
        }
    }
    $parameters = @($parameterGroups.Keys | Sort-Object | ForEach-Object {
        $merged = Merge-ParameterVariants @($parameterGroups[$_])
        $aliases = Get-P32PolicyValue $CommandPolicy 'parameterAliases'
        if ($null -ne $aliases -and $null -ne $aliases.PSObject.Properties[$merged.name]) { $merged.aliases = @($aliases.PSObject.Properties[$merged.name].Value) }
        $merged
    })
    $parameterSets = @($bindings | ForEach-Object {
        $operation = $_
        [ordered]@{
            name = [string]$operation.parameterSet
            operationId = [string]$operation.operationId
             operationBinding = [ordered]@{
                 method = [string]$operation.method
                 pathTemplate = [string]$operation.pathTemplate
                 pathParameters = @($operation.parameters | Where-Object binding -eq 'path' | Sort-Object position | ForEach-Object name)
                 queryParameters = @($operation.parameters | Where-Object binding -eq 'query' | ForEach-Object name)
                 bodyParameter = $operation.bodyParameterName
                 bodyModel = $operation.bodyModel
                 invokeKind = [string]$operation.invokeKind
                 outputPolicy = [string]$operation.outputPolicy
                 bodySerialization = $operation.bodySerialization
                 errorTarget = [string]$operation.errorTarget
             }
            requiredParameters = @($operation.parameters | Where-Object { @($_.requiredIn) -contains $_.appliesTo[0] } | ForEach-Object name)
            optionalParameters = @($operation.parameters | Where-Object { @($_.requiredIn) -notcontains $_.appliesTo[0] } | ForEach-Object name)
        }
    })
    $first = $bindings[0]
    $outputPolicy = if (@($bindings | Where-Object outputPolicy -eq 'item').Count -gt 0) { 'item' } elseif (@($bindings | Where-Object outputPolicy -eq 'none').Count -eq $bindings.Count) { 'none' } else { 'single' }
    $paging = @($bindings | Where-Object { $null -ne $_.runtime.pagination -and [string]$_.runtime.pagination.strategy -ne 'SinglePage' } | Select-Object -First 1)
    $impact = ($bindings | Sort-Object { Get-ImpactRank $_.confirmImpact } | Select-Object -Last 1).confirmImpact
    $defaultParameterSet = [string](Get-P32PolicyValue $CommandPolicy 'defaultParameterSetName')
    if ([string]::IsNullOrWhiteSpace($defaultParameterSet)) { $defaultParameterSet = [string]$first.parameterSet }
    $execution = Get-P32PolicyValue $CommandPolicy 'execution'
    if ($null -eq $execution) { throw "P3.2 command '$cmdletName' has no execution strategy." }
    $model = Get-P32PolicyValue $CommandPolicy 'model'
    [ordered]@{
        cmdletName = $CmdletName
        className = if ([string]::IsNullOrWhiteSpace([string](Get-P32PolicyValue $CommandPolicy 'className'))) { "$($CmdletName -replace '-', '')Command" } else { [string]$CommandPolicy.className }
        execution = $execution
        runtimeMetadataType = [string](Get-P32PolicyValue $CommandPolicy 'runtimeMetadataType')
        generated = Get-P32PolicyValue $CommandPolicy 'generated'
        model = $model
        defaultParameterSetName = $defaultParameterSet
        operationIds = @($bindings | ForEach-Object operationId)
        parameterSets = $parameterSets
        parameters = $parameters
        outputType = if ([string]::IsNullOrWhiteSpace([string](Get-P32PolicyValue $CommandPolicy 'outputType'))) { [string]$first.outputType } else { [string](Get-P32PolicyValue $CommandPolicy 'outputType') }
        outputPolicy = if ([string]::IsNullOrWhiteSpace([string](Get-P32PolicyValue $CommandPolicy 'outputPolicy'))) { $outputPolicy } else { [string](Get-P32PolicyValue $CommandPolicy 'outputPolicy') }
        pagingBehavior = if ($paging.Count -eq 1) { [string]$paging[0].runtime.pagination.strategy } else { $null }
        supportsShouldProcess = if ($null -ne (Get-P32PolicyValue $CommandPolicy 'supportsShouldProcess')) { [bool](Get-P32PolicyValue $CommandPolicy 'supportsShouldProcess') } else { @($bindings | Where-Object supportsShouldProcess).Count -gt 0 }
        confirmImpact = if ([string]::IsNullOrWhiteSpace([string](Get-P32PolicyValue $CommandPolicy 'confirmImpact'))) { [string]$impact } else { [string](Get-P32PolicyValue $CommandPolicy 'confirmImpact') }
        shouldProcessTarget = [string](Get-P32PolicyValue (Get-P32PolicyValue $CommandPolicy 'execution') 'shouldProcessTarget')
        shouldProcessAction = [string](Get-P32PolicyValue (Get-P32PolicyValue $CommandPolicy 'execution') 'shouldProcessAction')
        help = if ($null -ne (Get-P32PolicyValue $CommandPolicy 'help')) { Get-P32PolicyValue $CommandPolicy 'help' } else { $first.help }
        operations = $bindings
    }
}

function Write-Utf8CrLf {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
    [System.IO.File]::WriteAllText($Path, $normalized, [System.Text.UTF8Encoding]::new($false))
}

function Assert-P32ProjectionAlignment {
    param([Parameter(Mandatory)][object]$ZoneProjection, [Parameter(Mandatory)][object[]]$ProjectedZoneOperations)
    $expectedIds = @($ProjectedZoneOperations | ForEach-Object operationId)
    $expectedOperations = @($ZoneProjection.operations | Where-Object { $expectedIds -contains [string]$_.operationId })
    if ($expectedOperations.Count -eq 0) { throw 'P3.2 projection alignment input contains no expected operations.' }
    if ($ProjectedZoneOperations.Count -ne $expectedOperations.Count) { throw "P3.2 projection alignment operation count drifted. Expected $($expectedOperations.Count), found $($ProjectedZoneOperations.Count)." }
    foreach ($expected in $expectedOperations) {
        $actual = @($ProjectedZoneOperations | Where-Object { $_.operationId -eq [string]$expected.operationId })
        if ($actual.Count -ne 1) { throw "P3.2 normalized zone operation '$($expected.operationId)' is missing from the projection." }
        if ([string]$actual[0].method -ne [string]$expected.method -or [string]$actual[0].pathTemplate -ne [string]$expected.pathTemplate) {
            throw "P3.2 zone projection method/path drifted for '$($expected.operationId)'."
        }
        $expectedNames = @($expected.parameters | ForEach-Object name | Sort-Object)
        $actualNames = @($actual[0].parameters | ForEach-Object name | Sort-Object)
        if (($expectedNames -join '|') -ne ($actualNames -join '|')) { throw "P3.2 zone projection parameters drifted for '$($expected.operationId)'." }
        foreach ($expectedParameter in @($expected.parameters)) {
            $actualParameter = @($actual[0].parameters | Where-Object { $_.name -eq [string]$expectedParameter.name })
            if ($actualParameter.Count -ne 1) { throw "P3.2 zone parameter '$($expectedParameter.name)' is missing for '$($expected.operationId)'." }
            $expectedRequired = [bool]$expectedParameter.mandatory
            $actualRequired = @($actualParameter[0].requiredIn).Count -gt 0
            if ([string]$actualParameter[0].sourceName -ne [string]$expectedParameter.apiName -or
                [string]$actualParameter[0].binding -ne [string]$expectedParameter.binding -or
                $actualRequired -ne $expectedRequired -or
                [bool]$actualParameter[0].valueFromPipelineByPropertyName -ne [bool]$expectedParameter.valueFromPipelineByPropertyName -or
                [string]$actualParameter[0].nullPolicy -ne [string]$expectedParameter.nullPolicy) {
                throw "P3.2 zone parameter projection drifted for '$($expected.operationId)'/'$($expectedParameter.name)'."
            }
        }
    }
}

function New-P32CanonicalArtifact {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$DnsPath,
        [Parameter(Mandatory)][string]$ZonePath,
        [Parameter(Mandatory)][string]$ZoneProjection,
        [Parameter(Mandatory)][string]$BaseProjection,
        [Parameter(Mandatory)][string]$P23Projection,
        [Parameter(Mandatory)][string]$P32Policy
    )

    $inputPaths = @($DnsPath, $ZonePath, $ZoneProjection, $BaseProjection, $P23Projection, $P32Policy)
    foreach ($path in $inputPaths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "P3.2 projection input is missing: $path" }
    }

    $dnsDocument = Get-Content -Raw -LiteralPath $DnsPath | ConvertFrom-Json
    $zoneDocument = Get-Content -Raw -LiteralPath $ZonePath | ConvertFrom-Json
    $zoneProjectionDocument = Get-Content -Raw -LiteralPath $ZoneProjection | ConvertFrom-Json
    $baseProjectionDocument = Get-Content -Raw -LiteralPath $BaseProjection | ConvertFrom-Json
    $p23ProjectionDocument = Get-Content -Raw -LiteralPath $P23Projection | ConvertFrom-Json
    $p32PolicyDocument = Get-Content -Raw -LiteralPath $P32Policy | ConvertFrom-Json
    if ([int]$p32PolicyDocument.version -ne 1 -or [string]$p32PolicyDocument.stage -ne 'P3.2') { throw 'P3.2 projection policy version/stage is unsupported.' }

    $projectionOperations = @{}
    foreach ($document in @($baseProjectionDocument, $p23ProjectionDocument)) {
        foreach ($property in $document.operations.PSObject.Properties) {
            if (-not $projectionOperations.ContainsKey($property.Name)) { $projectionOperations[$property.Name] = [ordered]@{} }
            foreach ($child in $property.Value.PSObject.Properties) { $projectionOperations[$property.Name][$child.Name] = $child.Value }
        }
    }
    $documentsByResource = @{ zones = $zoneDocument; dns = $dnsDocument }
    $schemasByResource = @{
        zones = @{};
        dns = @{}
    }
    foreach ($property in $zoneDocument.schemas.PSObject.Properties) { $schemasByResource.zones[$property.Name] = $property.Value }
    foreach ($property in $dnsDocument.schemas.PSObject.Properties) { $schemasByResource.dns[$property.Name] = $property.Value }

    $selectedOperations = [System.Collections.Generic.List[object]]::new()
    $cmdlets = [System.Collections.Generic.List[object]]::new()
    foreach ($commandPolicy in @($p32PolicyDocument.commands)) {
        $resource = [string](Get-P32PolicyValue $commandPolicy 'resource')
        if (-not $documentsByResource.ContainsKey($resource)) { throw "P3.2 command '$($commandPolicy.cmdletName)' references unknown resource '$resource'." }
        $document = $documentsByResource[$resource]
        $operationPolicies = Get-P32PolicyValue $commandPolicy 'operations'
        $commandOperations = [System.Collections.Generic.List[object]]::new()
        foreach ($operationProperty in @($operationPolicies.PSObject.Properties | Sort-Object Name)) {
            $operationId = [string]$operationProperty.Name
            $operation = @($document.operations | Where-Object operationId -eq $operationId)
            if ($operation.Count -ne 1) { throw "P3.2 command '$($commandPolicy.cmdletName)' references missing/duplicate normalized operation '$operationId'." }
            $projected = ConvertTo-OperationProjection $operation[0] $projectionOperations $schemasByResource[$resource] $resource $operationProperty.Value $commandPolicy
            $commandOperations.Add($projected)
            $selectedOperations.Add($projected)
        }
        if ($commandOperations.Count -eq 0) { throw "P3.2 command '$($commandPolicy.cmdletName)' has no operations." }
        $cmdlets.Add((ConvertTo-CmdletProjection $commandPolicy @($commandOperations) $resource))
    }

    foreach ($commandPolicy in @($p32PolicyDocument.commands)) {
        $alignment = [string](Get-P32PolicyValue $commandPolicy 'projectionAlignment')
        if ([string]::IsNullOrWhiteSpace($alignment)) { continue }
        $resource = [string](Get-P32PolicyValue $commandPolicy 'resource')
        switch ($alignment) {
            'p23-resource' {
                if ($resource -ne 'zones') { throw "P3.2 projection alignment '$alignment' is unsupported for resource '$resource'." }
                Assert-P32ProjectionAlignment $zoneProjectionDocument @($selectedOperations | Where-Object resource -eq $resource)
            }
            default { throw "P3.2 projection alignment '$alignment' is unsupported." }
        }
    }
    if ($selectedOperations.Count -eq 0) { throw 'P3.2 projection contains no operations.' }

    $models = @($p32PolicyDocument.commands | ForEach-Object { $model = Get-P32PolicyValue $_ 'model'; if ($null -ne $model) { $model } })
    $sourceFiles = Get-P32SourceFiles $Root $inputPaths
    $artifact = [ordered]@{
        version = 3
        stage = 'P3.2'
        sourcePolicy = 'normalized-model-plus-projection-policy'
        semanticAlgorithm = 'SHA256-CanonicalJson-v1'
        sourceFiles = $sourceFiles
        cmdlets = @($cmdlets)
        models = $models
        commonInfrastructureParameters = @('BaseUrl', 'Token', 'Handler')
    }
    $artifact.canonicalDigest = Get-P32CanonicalDigest $artifact
    return $artifact
}

if (-not $Library) {
    $artifact = New-P32CanonicalArtifact -Root $ProjectRoot -DnsPath $DnsNormalizedPath -ZonePath $ZoneNormalizedPath -ZoneProjection $ZoneProjectionPath -BaseProjection $ProjectionPath -P23Projection $P23ProjectionPath -P32Policy $P32PolicyPath
    Write-Utf8CrLf $ArtifactPath ($artifact | ConvertTo-Json -Depth 100)
    Write-Output "PASS P3.2 canonical projection: cmdlets=$(@($artifact.cmdlets).Count), operations=$(@($artifact.cmdlets | ForEach-Object operations).Count)"
    Write-Output "P3.2 canonical artifact: $ArtifactPath"
}
