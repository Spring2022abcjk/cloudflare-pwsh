Set-StrictMode -Version Latest

function Get-P33JsonValue {
    param([AllowNull()][object]$Object, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-P33JsonProperty {
    param([AllowNull()][object]$Object, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) }
    return $null -ne $Object.PSObject.Properties[$Name]
}

function Get-P33SchemaProperty {
    param([Parameter(Mandatory)][object]$Schema, [Parameter(Mandatory)][string]$PropertyName)
    $properties = Get-P33JsonValue $Schema 'properties'
    if ($null -eq $properties) { return $null }
    if ($properties -is [System.Collections.IDictionary] -and $properties.Contains($PropertyName)) { return $properties[$PropertyName] }
    $property = $properties.PSObject.Properties[$PropertyName]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-P33SchemaBaseType {
    param([Parameter(Mandatory)][object]$Schema, [Parameter(Mandatory)][string]$SchemaName)
    $primitiveType = [string](Get-P33JsonValue $Schema 'primitiveType')
    switch ($primitiveType) {
        'string' { return 'string' }
        'integer' { return 'int' }
        'number' { return 'decimal' }
        'boolean' { return 'bool' }
        'array' {
            $itemsName = [string](Get-P33JsonValue $Schema 'items')
            if ([string]::IsNullOrWhiteSpace($itemsName)) { throw "P3.3 model schema '$SchemaName' is an array without normalized item schema." }
            throw "P3.3 typed model schema '$SchemaName' is an unsupported array reference; add a typed array projection rule with provenance."
        }
        default { throw "P3.3 model schema '$SchemaName' has unsupported normalized primitive type '$primitiveType'." }
    }
}

function Get-P33SchemaType {
    param([Parameter(Mandatory)][hashtable]$Schemas, [Parameter(Mandatory)][string]$SchemaName)
    if (-not $Schemas.ContainsKey($SchemaName)) { throw "P3.3 typed model schema '$SchemaName' is missing from the normalized fixture." }
    $schema = $Schemas[$SchemaName]
    $primitiveType = [string](Get-P33JsonValue $schema 'primitiveType')
    switch ($primitiveType) {
        'string' { return 'string' }
        'integer' { return 'int' }
        'number' { return 'decimal' }
        'boolean' { return 'bool' }
        'array' {
            $itemsName = [string](Get-P33JsonValue $schema 'items')
            if ([string]::IsNullOrWhiteSpace($itemsName)) { throw "P3.3 typed model schema '$SchemaName' is an array without normalized item schema." }
            return "$(Get-P33SchemaType $Schemas $itemsName)[]"
        }
        default {
            $additionalPropertiesSchema = [string](Get-P33JsonValue $schema 'additionalPropertiesSchema')
            if ([string]$schema.kind -eq 'object' -and -not [string]::IsNullOrWhiteSpace($additionalPropertiesSchema)) {
                return "Dictionary<string, $(Get-P33SchemaType $Schemas $additionalPropertiesSchema)>"
            }
            throw "P3.3 typed model schema '$SchemaName' has unsupported normalized type '$primitiveType' and no typed object/array mapping."
        }
    }
}

function Get-P33ModelDefinition {
    param([Parameter(Mandatory)][object[]]$Models, [Parameter(Mandatory)][string]$ClassName)
    $matches = @($Models | Where-Object { [string]$_.className -ceq $ClassName })
    if ($matches.Count -ne 1) { throw "P3.3 nested model '$ClassName' must resolve to exactly one model definition; found $($matches.Count)." }
    return $matches[0]
}

function Get-P33ObjectAllowlistEntry {
    param([AllowNull()][object]$Allowlist, [Parameter(Mandatory)][string]$ClassName, [Parameter(Mandatory)][string]$PropertyName)
    if ($null -eq $Allowlist) { return $null }
    $matches = @($Allowlist | Where-Object { $null -ne $_ -and [string]$_.className -ceq $ClassName -and [string]$_.propertyName -ceq $PropertyName })
    if ($matches.Count -gt 1) { throw "P3.3 object allowlist contains duplicate entry '$ClassName.$PropertyName'." }
    if ($matches.Count -eq 1) { return $matches[0] }
    return $null
}

function ConvertTo-P33ModelProjection {
    param(
        [Parameter(Mandatory)][object]$Model,
        [Parameter(Mandatory)][hashtable]$Schemas,
        [Parameter(Mandatory)][object[]]$AllModels,
        [Parameter(Mandatory)][string]$NormalizedSourcePath,
        [AllowNull()][object]$ObjectAllowlist
    )

    $className = [string](Get-P33JsonValue $Model 'className')
    if ([string]::IsNullOrWhiteSpace($className)) { throw 'P3.3 model is missing className.' }
    $schemaSources = @(Get-P33JsonValue $Model 'schemaSources')
    if ($schemaSources.Count -eq 0) { throw "P3.3 model '$className' has no normalized schema source binding." }
    $declaredDirections = @(Get-P33JsonValue $Model 'directions')
    if ($declaredDirections.Count -eq 0) { throw "P3.3 model '$className' has no request/response direction declaration." }
    $validDirections = @('request', 'response')
    foreach ($direction in $declaredDirections) {
        if ([string]$direction -notin $validDirections) { throw "P3.3 model '$className' has unsupported direction '$direction'." }
    }
    $declaredDirections = @($declaredDirections | ForEach-Object { [string]$_ } | Sort-Object -Unique)

    $canonicalSources = [System.Collections.Generic.List[object]]::new()
    $sourceKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($source in $schemaSources) {
        $schemaName = [string](Get-P33JsonValue $source 'schema')
        $direction = [string](Get-P33JsonValue $source 'direction')
        if ([string]::IsNullOrWhiteSpace($schemaName) -or $direction -notin $validDirections) { throw "P3.3 model '$className' has an incomplete normalized schema source binding." }
        if (-not $Schemas.ContainsKey($schemaName)) { throw "P3.3 model '$className' references missing normalized schema '$schemaName'." }
        if ($declaredDirections -notcontains $direction) { throw "P3.3 model '$className' source '$schemaName' uses undeclared direction '$direction'." }
        if (-not $sourceKeys.Add("$schemaName|$direction")) { throw "P3.3 model '$className' has duplicate normalized source '$schemaName|$direction'." }
        $schema = $Schemas[$schemaName]
        $canonicalSources.Add([ordered]@{
                schema = $schemaName
                direction = $direction
                sourceRef = [string](Get-P33JsonValue $schema 'sourceRef')
                normalizedSourcePath = $NormalizedSourcePath
            })
    }

    $properties = @(Get-P33JsonValue $Model 'properties')
    if ($properties.Count -eq 0) { throw "P3.3 model '$className' has no properties." }
    $canonicalProperties = [System.Collections.Generic.List[object]]::new()
    $propertyNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($property in $properties) {
        $propertyName = [string](Get-P33JsonValue $property 'name')
        $jsonName = [string](Get-P33JsonValue $property 'jsonName')
        $declaredType = [string](Get-P33JsonValue $property 'type')
        if ([string]::IsNullOrWhiteSpace($propertyName) -or -not $propertyNames.Add($propertyName)) { throw "P3.3 model '$className' has a missing or duplicate property name." }
        if ([string]::IsNullOrWhiteSpace($jsonName)) { throw "P3.3 model '$className.$propertyName' has no JSON property name." }
        if ([string]::IsNullOrWhiteSpace($declaredType)) { throw "P3.3 model '$className.$propertyName' has no C# type." }
        if (-not (Test-P33JsonProperty $property 'nullable') -or -not (Test-P33JsonProperty $property 'presence')) { throw "P3.3 model '$className.$propertyName' must declare nullable and presence expectations." }

        $propertySources = @(Get-P33JsonValue $property 'schemaSources')
        if ($propertySources.Count -eq 0) { throw "P3.3 model '$className.$propertyName' has no normalized property source binding." }
        $contracts = [System.Collections.Generic.List[object]]::new()
        $baseTypes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $hasNullableSource = $false
        $allRequired = $true
        $nestedModels = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($propertySource in $propertySources) {
            $schemaName = [string](Get-P33JsonValue $propertySource 'schema')
            $sourcePropertyName = [string](Get-P33JsonValue $propertySource 'property')
            $direction = [string](Get-P33JsonValue $propertySource 'direction')
            if ([string]::IsNullOrWhiteSpace($schemaName) -or [string]::IsNullOrWhiteSpace($sourcePropertyName) -or $direction -notin $validDirections) { throw "P3.3 model '$className.$propertyName' has an incomplete property schema binding." }
            if (-not $Schemas.ContainsKey($schemaName)) { throw "P3.3 model '$className.$propertyName' references missing normalized schema '$schemaName'." }
            if (-not $sourceKeys.Contains("$schemaName|$direction")) { throw "P3.3 model '$className.$propertyName' source '$schemaName|$direction' is not a model source binding." }
            $normalizedSchema = $Schemas[$schemaName]
            $normalizedProperty = Get-P33SchemaProperty $normalizedSchema $sourcePropertyName
            if ($null -eq $normalizedProperty) { throw "P3.3 model '$className.$propertyName' property source '$schemaName.$sourcePropertyName' is not present in normalized schema." }
            if ([string]$normalizedProperty.name -cne $sourcePropertyName) { throw "P3.3 model '$className.$propertyName' property source name '$sourcePropertyName' does not match normalized property '$($normalizedProperty.name)'." }
            if ($jsonName -cne [string]$normalizedProperty.name) { throw "P3.3 model '$className.$propertyName' JSON name '$jsonName' does not match normalized property '$($normalizedProperty.name)'." }

            $childSchemaName = [string]$normalizedProperty.schema
            if ([string]::IsNullOrWhiteSpace($childSchemaName) -or -not $Schemas.ContainsKey($childSchemaName)) { throw "P3.3 model '$className.$propertyName' normalized property has missing schema '$childSchemaName'." }
            $childSchema = $Schemas[$childSchemaName]
            $childKind = [string](Get-P33JsonValue $childSchema 'kind')
            $nestedModel = [string](Get-P33JsonValue $property 'nestedModel')
            $baseType = $null
            $additionalPropertiesSchema = [string](Get-P33JsonValue $childSchema 'additionalPropertiesSchema')
            if ($childKind -eq 'object' -and [string]::IsNullOrWhiteSpace($additionalPropertiesSchema)) {
                if ([string]::IsNullOrWhiteSpace($nestedModel)) { throw "P3.3 model '$className.$propertyName' points to object schema '$childSchemaName' without nestedModel." }
                $nestedDefinition = Get-P33ModelDefinition $AllModels $nestedModel
                $nestedSources = @($nestedDefinition.schemaSources | ForEach-Object { "$(Get-P33JsonValue $_ 'schema')|$(Get-P33JsonValue $_ 'direction')" })
                if ($nestedSources -notcontains "$childSchemaName|$direction") { throw "P3.3 model '$className.$propertyName' nestedModel '$nestedModel' is not bound to normalized schema '$childSchemaName' in direction '$direction'." }
                [void]$nestedModels.Add($nestedModel)
                $baseType = $nestedModel
            } else {
                if (-not [string]::IsNullOrWhiteSpace($nestedModel)) { throw "P3.3 model '$className.$propertyName' declares nestedModel '$nestedModel' for non-object or dictionary schema '$childSchemaName'." }
                $baseType = Get-P33SchemaType $Schemas $childSchemaName
            }
            [void]$baseTypes.Add($baseType)
            $required = [bool](Get-P33JsonValue $normalizedProperty 'required')
            $allowsNull = [bool](Get-P33JsonValue $normalizedProperty 'allowsNull')
            if (-not $required) { $allRequired = $false }
            if (-not $required -or $allowsNull) { $hasNullableSource = $true }
            $contracts.Add([ordered]@{
                    schema = $schemaName
                    property = $sourcePropertyName
                    direction = $direction
                    normalizedSchema = $childSchemaName
                    normalizedKind = $childKind
                    normalizedPrimitiveType = [string](Get-P33JsonValue $childSchema 'primitiveType')
                    normalizedItemsSchema = [string](Get-P33JsonValue $childSchema 'items')
                    normalizedAdditionalPropertiesAllowed = Get-P33JsonValue $childSchema 'additionalPropertiesAllowed'
                    normalizedAdditionalPropertiesSchema = [string](Get-P33JsonValue $childSchema 'additionalPropertiesSchema')
                    normalizedSourceRef = [string](Get-P33JsonValue $childSchema 'sourceRef')
                    sourceRef = [string](Get-P33JsonValue $normalizedSchema 'sourceRef')
                    required = $required
                    allowsNull = $allowsNull
                    presence = if ($required) { 'required' } else { 'optional' }
                    nullable = (-not $required -or $allowsNull)
                    nullPolicy = [string](Get-P33JsonValue $normalizedProperty 'nullPolicy')
                    normalizedSourcePath = $NormalizedSourcePath
                })
        }

        if ($baseTypes.Count -ne 1) { throw "P3.3 model '$className.$propertyName' has inconsistent normalized C# base types: $($baseTypes -join ', ')." }
        $expectedNullable = [bool]$hasNullableSource
        $expectedPresence = if ($allRequired) { 'required' } else { 'optional' }
        $expectedType = [string](@($baseTypes)[0]) + $(if ($expectedNullable) { '?' } else { '' })
        $declaredNullable = [bool](Get-P33JsonValue $property 'nullable')
        $declaredPresence = [string](Get-P33JsonValue $property 'presence')
        if ($declaredNullable -ne $expectedNullable) { throw "P3.3 model '$className.$propertyName' nullable=$declaredNullable does not match normalized schema nullable=$expectedNullable." }
        if ($declaredPresence -cne $expectedPresence) { throw "P3.3 model '$className.$propertyName' presence '$declaredPresence' does not match normalized schema presence '$expectedPresence'." }
        $objectTypes = @('object', 'System.Object', 'PSObject', 'System.Management.Automation.PSObject')
        $declaredBaseType = $declaredType.TrimEnd('?')
        if ($objectTypes -contains $declaredBaseType) {
            $allowance = Get-P33ObjectAllowlistEntry $ObjectAllowlist $className $propertyName
            if ($null -eq $allowance -or [string]::IsNullOrWhiteSpace([string](Get-P33JsonValue $allowance 'reason')) -or [string]::IsNullOrWhiteSpace([string](Get-P33JsonValue $allowance 'source')) -or [string]::IsNullOrWhiteSpace([string](Get-P33JsonValue $allowance 'provenance'))) {
                throw "P3.3 model '$className.$propertyName' uses forbidden object fallback; provide an explicit allowlist entry with reason, source, and provenance." }
        } elseif ($declaredType -cne $expectedType) {
            throw "P3.3 model '$className.$propertyName' C# type '$declaredType' does not match normalized schema type '$expectedType'."
        }
        $canonicalProperty = [ordered]@{
            name = $propertyName
            jsonName = $jsonName
            type = $declaredType
            nullable = $expectedNullable
            presence = $expectedPresence
            schemaSources = @($propertySources | ForEach-Object { [ordered]@{ schema = [string](Get-P33JsonValue $_ 'schema'); property = [string](Get-P33JsonValue $_ 'property'); direction = [string](Get-P33JsonValue $_ 'direction') } })
            sourceContracts = @($contracts)
        }
        if ($nestedModels.Count -eq 1) { $canonicalProperty.nestedModel = @($nestedModels)[0] }
        $allowance = Get-P33ObjectAllowlistEntry $ObjectAllowlist $className $propertyName
        if ($null -ne $allowance) { $canonicalProperty.objectTypeAllowance = [ordered]@{ reason = [string]$allowance.reason; source = [string]$allowance.source; provenance = [string]$allowance.provenance } }
        $canonicalProperties.Add($canonicalProperty)
    }

    return [ordered]@{
        className = $className
        path = [string](Get-P33JsonValue $Model 'path')
        directions = @($declaredDirections)
        schemaSources = @($canonicalSources)
        properties = @($canonicalProperties)
        provenance = [ordered]@{
            kind = 'normalized-schema-binding'
            sourcePath = $NormalizedSourcePath
            modelClass = $className
        }
    }
}
