[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$FixtureRoot = (Join-Path $ProjectRoot 'fixtures/p2.1'),
    [string]$ProjectionPath = (Join-Path $ProjectRoot 'overrides/powershell-p23-projection.json'),
    [string]$BaseProjectionPath = (Join-Path $ProjectRoot 'overrides/powershell-projection.json'),
    [string]$ArtifactRoot = (Join-Path $ProjectRoot 'artifacts/p2.3/projection'),
    [string]$ExperimentSource = (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Experiments/P23_GetCfZoneCommand.cs')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-JsonPropertyValue {
    param([object]$Object, [string]$Name)
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) { return $Object[$Name] }
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) { return $null }
    return $Object.PSObject.Properties[$Name].Value
}

function ConvertTo-PowerShellName {
    param([string]$Value)
    $parts = $Value -split '[._-]' | Where-Object { $_ }
    if (@($parts).Count -eq 0) { return 'Value' }
    $name = (@($parts) | ForEach-Object {
        if ($_.Length -eq 1) { $_.ToUpperInvariant() }
        else { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }
    }) -join ''
    if ($name[0] -match '[0-9]') { return "N_$name" }
    return $name
}

function ConvertTo-CSharpIdentifier {
    param([string]$Value)
    $identifier = [regex]::Replace($Value, '[^A-Za-z0-9_]', '_')
    $identifier = [regex]::Replace($identifier, '_+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($identifier)) { return 'Value' }
    if ($identifier[0] -match '[0-9]') { return "N_$identifier" }
    return $identifier
}

function ConvertTo-CSharpType {
    param([object]$Schema, [hashtable]$Schemas)
    $schemaName = [string](Get-JsonPropertyValue $Schema 'schema')
    if ([string]::IsNullOrWhiteSpace($schemaName) -or $null -eq $Schemas[$schemaName]) { return 'object' }
    $definition = $Schemas[$schemaName]
    switch ([string](Get-JsonPropertyValue $definition 'primitiveType')) {
        'string' { if ([string](Get-JsonPropertyValue $definition 'kind') -eq 'enum') { return 'string' }; return 'string' }
        'integer' { return 'int' }
        'number' { return 'decimal' }
        'boolean' { return 'bool' }
        'array' { return 'string[]' }
        default { return 'object' }
    }
}

function Get-OperationOverride {
    param([object]$ProjectionDocument, [string]$OperationId)
    $property = $ProjectionDocument.operations.PSObject.Properties[$OperationId]
    if ($null -eq $property) { return [pscustomobject]@{} }
    return $property.Value
}

function Get-ParameterOverride {
    param([object]$Override, [string]$ApiName)
    $parameters = Get-JsonPropertyValue $Override 'parameters'
    if ($null -eq $parameters -or $null -eq $parameters.PSObject.Properties[$ApiName]) { return [pscustomobject]@{} }
    return $parameters.PSObject.Properties[$ApiName].Value
}

function Get-ProjectedParameterName {
    param([object]$Parameter, [object]$Override)
    $renames = Get-JsonPropertyValue $Override 'parameterRenames'
    if ($null -ne $renames -and $null -ne $renames.PSObject.Properties[$Parameter.name]) {
        return [string]$renames.PSObject.Properties[$Parameter.name].Value
    }
    return ConvertTo-PowerShellName ([string]$Parameter.name)
}

function Get-HelpModel {
    param([object]$Operation, [object]$Override)
    $explicit = Get-JsonPropertyValue $Override 'help'
    if ($null -ne $explicit) { return [pscustomobject]@{ synopsis = [string]$explicit.synopsis; description = [string]$explicit.description; source = 'Override' } }
    $verb = [string](Get-JsonPropertyValue $Override 'verb')
    $noun = [string](Get-JsonPropertyValue $Override 'noun')
    $kind = [string]$Operation.operationSemantic.kind
    return [pscustomobject]@{
        synopsis = "$verb`-$noun $($kind.ToLowerInvariant()) operation."
        description = "Generated help for the normalized $kind operation '$($Operation.operationId)'."
        source = 'DeterministicDefault'
    }
}

function ConvertTo-ProjectedOperation {
    param([object]$Operation, [object]$ProjectionDocument, [hashtable]$Schemas)
    $override = Get-OperationOverride $ProjectionDocument $Operation.operationId
    $verb = [string](Get-JsonPropertyValue $Override 'verb')
    $noun = [string](Get-JsonPropertyValue $Override 'noun')
    $parameterSet = if ($null -ne (Get-JsonPropertyValue $Override 'parameterSet')) { [string]$Override.parameterSet } else { [string]$Operation.operationSemantic.kind }
    $pipelinePolicy = [string](Get-JsonPropertyValue $ProjectionDocument.defaults 'pipelinePolicy')
    $parameters = @($Operation.parameters | Sort-Object location, name | ForEach-Object {
        $parameterOverride = Get-ParameterOverride $Override $_.name
        $projectedName = Get-ProjectedParameterName $_ $Override
        $isScope = @($Operation.scopeBindings | Where-Object parameterName -eq $_.name).Count -gt 0
        $valueFromPipeline = if ($null -ne (Get-JsonPropertyValue $parameterOverride 'valueFromPipeline')) { [bool]$parameterOverride.valueFromPipeline } else { $false }
        $valueFromPipelineByPropertyName = if ($null -ne (Get-JsonPropertyValue $parameterOverride 'valueFromPipelineByPropertyName')) { [bool]$parameterOverride.valueFromPipelineByPropertyName } else { $isScope -and $pipelinePolicy -eq 'ScopeByPropertyName' }
        [ordered]@{
            name = $projectedName
            parameterSet = $parameterSet
            apiName = [string]$_.name
            binding = [string]$_.location
            type = ConvertTo-CSharpType $_ $Schemas
            schema = [string]$_.schema
            mandatory = [bool]$_.required
            position = if ($null -ne (Get-JsonPropertyValue $parameterOverride 'position')) { [int]$parameterOverride.position } else { $null }
            valueFromPipeline = $valueFromPipeline
            valueFromPipelineByPropertyName = $valueFromPipelineByPropertyName
            nullPolicy = [string]$_.nullPolicy
            defaultValue = Get-JsonPropertyValue $_ 'defaultValue'
            apiBinding = [pscustomobject]@{ location = [string]$_.location; name = [string]$_.name }
            help = if ($null -ne (Get-JsonPropertyValue $parameterOverride 'help')) { $parameterOverride.help } else { [pscustomobject]@{ description = "Binds to API $($_.location) parameter '$($_.name)'."; source = 'DeterministicDefault' } }
        }
    })
    $scopeBindings = @($Operation.scopeBindings | Sort-Object parameterName, role | ForEach-Object { [ordered]@{ parameterName = $_.parameterName; projectedName = Get-ProjectedParameterName ([pscustomobject]@{ name = $_.parameterName }) $Override; scopeType = $_.scopeType; role = $_.role } })
    $outputType = Get-JsonPropertyValue $Override 'outputType'
    if ($null -eq $outputType) { $outputType = 'System.Management.Automation.PSObject' }
    [ordered]@{
        operationId = [string]$Operation.operationId
        cmdletName = "$verb-$noun"
        parameterSet = $parameterSet
        semantic = $Operation.operationSemantic
        method = [string]$Operation.method
        pathTemplate = [string]$Operation.pathTemplate
        resourcePath = @($Operation.resourcePath)
        scopeBindings = $scopeBindings
        parameters = $parameters
        outputType = [string]$outputType
        outputPolicy = if ($null -ne (Get-JsonPropertyValue $Override 'outputPolicy')) { [string]$Override.outputPolicy } else { 'single' }
        pagingBehavior = Get-JsonPropertyValue $Override 'paging'
        supportsShouldProcess = [bool](Get-JsonPropertyValue $Override 'supportsShouldProcess')
        confirmImpact = if ($null -ne (Get-JsonPropertyValue $Override 'confirmImpact')) { [string]$Override.confirmImpact } else { 'None' }
        help = Get-HelpModel $Operation $Override
    }
}

function Write-Utf8CrLf {
    param([string]$Path, [string]$Content)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
    [System.IO.File]::WriteAllText($Path, $normalized, [System.Text.UTF8Encoding]::new($false))
}

function ConvertTo-AttributeParameter {
    param([object]$Parameter, [string]$ParameterSet)
    $mandatory = @($Parameter.requiredIn) -contains $ParameterSet
    $arguments = @("Mandatory = $($mandatory.ToString().ToLowerInvariant())", "ParameterSetName = `"$ParameterSet`"")
    $position = Get-JsonPropertyValue $Parameter 'position'
    if ($null -ne $position) { $arguments += "Position = $position" }
    if ($Parameter.valueFromPipeline) { $arguments += 'ValueFromPipeline = true' }
    if ($Parameter.valueFromPipelineByPropertyName) { $arguments += 'ValueFromPipelineByPropertyName = true' }
    return "[Parameter($($arguments -join ', '))]"
}

function Write-GetCfZoneExperiment {
    param([object]$Cmdlet, [object]$ZonesDocument, [string]$Path)
    $parameters = @($Cmdlet.parameters | Sort-Object name)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('// <auto-generated />')
    $lines.Add('// P2.3 isolated experiment: metadata and loading only; HTTP dispatch remains deferred.')
    $lines.Add('#nullable enable')
    $lines.Add('using System.Management.Automation;')
    $lines.Add('')
    $lines.Add('namespace Cloudflare.PowerShell;')
    $lines.Add('')
    $lines.Add('[Cmdlet(VerbsCommon.Get, "CfZone", DefaultParameterSetName = "List")]')
    $lines.Add('[OutputType(typeof(CfZone))]')
    $lines.Add('public sealed class P23GetCfZoneCommand : PSCmdlet')
    $lines.Add('{')
    foreach ($set in @($Cmdlet.parameterSets | Sort-Object name)) {
        foreach ($parameter in @($parameters | Where-Object { @($_.appliesTo) -contains $set.name -or @($_.appliesTo).Count -eq 0 })) {
            if ($parameter.name -in @($lines | ForEach-Object { if ($_ -match '^    public .* ([A-Za-z0-9_]+) \{ get; set; \}$') { $Matches[1] } })) { continue }
            $attribute = ConvertTo-AttributeParameter $parameter $set.name
            $lines.Add("    $attribute")
            $type = if ([string]::IsNullOrWhiteSpace([string]$parameter.type)) { 'object' } else { [string]$parameter.type }
            $nullableType = if ($type -in @('string', 'object', 'string[]')) { "${type}?" } else { $type }
            $lines.Add("    public $nullableType $($parameter.name) { get; set; }")
        }
    }
    $lines.Add('')
    $lines.Add('    protected override void ProcessRecord()')
    $lines.Add('    {')
    $lines.Add('        // Deliberately empty: P2.3 measures the generated PowerShell surface before runtime migration.')
    $lines.Add('    }')
    $lines.Add('}')
    $lines.Add('')
    $lines.Add('public sealed class CfZone')
    $lines.Add('{')
    foreach ($property in @('Id', 'Name', 'Status', 'Type')) { $lines.Add("    public string? $property { get; init; }") }
    $lines.Add('}')
    Write-Utf8CrLf $Path ($lines -join "`n")
}

$baseProjectionDocument = Get-Content -Raw -LiteralPath $BaseProjectionPath | ConvertFrom-Json
$p23ProjectionDocument = Get-Content -Raw -LiteralPath $ProjectionPath | ConvertFrom-Json
$mergedOperations = [ordered]@{}
foreach ($property in $baseProjectionDocument.operations.PSObject.Properties) {
    $mergedOperations[$property.Name] = [ordered]@{}
    foreach ($operationProperty in $property.Value.PSObject.Properties) { $mergedOperations[$property.Name][$operationProperty.Name] = $operationProperty.Value }
}
foreach ($property in $p23ProjectionDocument.operations.PSObject.Properties) {
    if (-not $mergedOperations.Contains($property.Name)) { $mergedOperations[$property.Name] = [ordered]@{} }
    foreach ($operationProperty in $property.Value.PSObject.Properties) { $mergedOperations[$property.Name][$operationProperty.Name] = $operationProperty.Value }
}
$mergedDefaults = [ordered]@{}
foreach ($property in $baseProjectionDocument.defaults.PSObject.Properties) { $mergedDefaults[$property.Name] = $property.Value }
foreach ($property in $p23ProjectionDocument.defaults.PSObject.Properties) { $mergedDefaults[$property.Name] = $property.Value }
$projectionDocument = [pscustomobject]@{ operations = [pscustomobject]$mergedOperations; defaults = [pscustomobject]$mergedDefaults }
New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null
$allCmdlets = [System.Collections.Generic.List[object]]::new()

foreach ($fixture in Get-ChildItem -LiteralPath $FixtureRoot -Directory | Sort-Object Name) {
    $document = Get-Content -Raw -LiteralPath (Join-Path $fixture.FullName 'document.json') | ConvertFrom-Json
    $schemas = @{}
    foreach ($property in $document.schemas.PSObject.Properties) { $schemas[$property.Name] = $property.Value }
    $operations = @($document.operations | Sort-Object operationId | ForEach-Object { ConvertTo-ProjectedOperation $_ $projectionDocument $schemas })
    $cmdlets = @($operations | Group-Object { $_.cmdletName } | Sort-Object Name | ForEach-Object {
        $bindings = @($_.Group | Sort-Object operationId)
        $parameters = @($bindings | ForEach-Object { @($_.parameters) } | Group-Object { Get-JsonPropertyValue $_ 'name' } | Sort-Object Name | ForEach-Object {
            $variants = @($_.Group)
            [ordered]@{
                name = $_.Name
                type = [string]$variants[0].type
                binding = [string]$variants[0].binding
                position = Get-JsonPropertyValue $variants[0] 'position'
                appliesTo = @($variants | ForEach-Object { $_.parameterSet })
                requiredIn = @($variants | Where-Object mandatory | ForEach-Object { $_.parameterSet })
                valueFromPipeline = @($variants | Where-Object valueFromPipeline).Count -gt 0
                valueFromPipelineByPropertyName = @($variants | Where-Object valueFromPipelineByPropertyName).Count -gt 0
                nullPolicy = [string]$variants[0].nullPolicy
                defaultValue = $variants[0].defaultValue
                apiBindings = @($variants | ForEach-Object apiBinding)
                help = $variants[0].help
            }
        })
        [ordered]@{
            cmdletName = $_.Name
            operationIds = @($bindings | ForEach-Object operationId)
            parameterSets = @($bindings | ForEach-Object {
                [ordered]@{
                    name = $_.parameterSet
                    operationId = $_.operationId
                    operationBinding = [ordered]@{ method = $_.method; pathTemplate = $_.pathTemplate; pathParameters = @($_.parameters | Where-Object binding -eq 'path' | ForEach-Object name); queryParameters = @($_.parameters | Where-Object binding -eq 'query' | ForEach-Object name) }
                    requiredParameters = @($_.parameters | Where-Object mandatory | ForEach-Object name)
                    optionalParameters = @($_.parameters | Where-Object { -not $_.mandatory } | ForEach-Object name)
                }
            })
            parameters = $parameters
            outputType = [string]$bindings[0].outputType
            outputPolicy = if (@($bindings | Where-Object outputPolicy -eq 'item').Count -gt 0) { 'item' } else { 'single' }
            pagingBehavior = @($bindings | Where-Object { $null -ne $_.pagingBehavior } | Select-Object -First 1 | ForEach-Object pagingBehavior)
            supportsShouldProcess = @($bindings | Where-Object supportsShouldProcess).Count -gt 0
            confirmImpact = (@($bindings | Sort-Object confirmImpact | Select-Object -Last 1 | ForEach-Object confirmImpact) | Select-Object -First 1)
            help = $bindings[0].help
            scopeBindings = @($bindings | ForEach-Object { @($_.scopeBindings) } | Sort-Object projectedName, role | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
        }
    })
    $result = [ordered]@{ resource = $fixture.Name; operations = $operations; cmdlets = $cmdlets }
    Write-Utf8CrLf (Join-Path $ArtifactRoot "$($fixture.Name).json") ($result | ConvertTo-Json -Depth 100)
    foreach ($cmdlet in $cmdlets) { $allCmdlets.Add([pscustomobject]@{ resource = $fixture.Name; model = $cmdlet }) }
    Write-Output "Projected P2.3 $($fixture.Name): operations=$($operations.Count), cmdlets=$($cmdlets.Count)"
}

$zone = @($allCmdlets | Where-Object { $_.resource -eq 'zones' -and $_.model.cmdletName -eq 'Get-CfZone' } | Select-Object -First 1)
if ($zone.Count -ne 1) { throw 'P2.3 requires exactly one generated Get-CfZone model.' }
$zonesDocument = Get-Content -Raw -LiteralPath (Join-Path $FixtureRoot 'zones/document.json') | ConvertFrom-Json
Write-GetCfZoneExperiment $zone[0].model $zonesDocument $ExperimentSource

[ordered]@{
    stage = 'P2.3'
    projectionPolicy = $projectionDocument.defaults
    generatedExperiment = 'src/Cloudflare.PowerShell/Generated/Experiments/P23_GetCfZoneCommand.cs'
    generatedCmdlet = $zone[0].model.cmdletName
    dispatch = 'deferred'
} | ConvertTo-Json -Depth 30 | ForEach-Object { Write-Utf8CrLf (Join-Path (Split-Path -Parent $ArtifactRoot) 'manifest.json') $_ }
