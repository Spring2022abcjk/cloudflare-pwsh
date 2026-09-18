[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ArtifactPath = (Join-Path $ProjectRoot 'artifacts/p3.2/CmdletModel.json'),
    [string]$TemplatePath = (Join-Path $ProjectRoot 'tools/templates/P32RepresentativeCmdlets.cs.tmpl'),
    [string]$SourcePath = (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Cmdlets/P32RepresentativeCmdlets.cs'),
    [string]$RuntimeSourcePath = (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Metadata/CfDnsRecordRuntimeMetadata.cs'),
    [string]$ZoneRuntimeSourcePath = (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Metadata/CfZoneRuntimeMetadata.cs'),
    [string]$GeneratedRoot = (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated'),
    [switch]$ValidateOnly,
    [switch]$Library
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectionLibrary = Join-Path $PSScriptRoot 'Project-P32Projection.ps1'
$p32GenerateProjectRoot = $ProjectRoot
$p32GenerateArtifactPath = $ArtifactPath
$p32GenerateTemplatePath = $TemplatePath
$p32GenerateSourcePath = $SourcePath
$p32GenerateLibrary = $Library
. $projectionLibrary -ProjectRoot $ProjectRoot -Library
$ProjectRoot = $p32GenerateProjectRoot
$ArtifactPath = $p32GenerateArtifactPath
$TemplatePath = $p32GenerateTemplatePath
$SourcePath = $p32GenerateSourcePath
$Library = $p32GenerateLibrary

function Get-JsonValue {
    param([AllowNull()][object]$Object, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Write-Utf8CrLf {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
    [IO.File]::WriteAllText($Path, $normalized, [Text.UTF8Encoding]::new($false))
}

function ConvertTo-CSharpString {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return 'null' }
    return ($Value.ToString() | ConvertTo-Json -Compress)
}

function ConvertTo-CSharpBool {
    param([object]$Value)
    return ([bool]$Value).ToString().ToLowerInvariant()
}

function ConvertTo-CSharpLiteral {
    param([AllowNull()][object]$Value, [Parameter(Mandatory)][string]$Type)
    if ($null -eq $Value) { return $null }
    if ($Type -eq 'string?' -or $Type -eq 'string') { return ConvertTo-CSharpString $Value }
    if ($Type -eq 'bool' -or $Type -eq 'bool?') { return ConvertTo-CSharpBool $Value }
    if ($Type -eq 'decimal') { return "$Value`m" }
    if ($Type -eq 'int') { return [string][int]$Value }
    return $null
}

function Get-ParameterAttributeLines {
    param([Parameter(Mandatory)][object]$Cmdlet, [Parameter(Mandatory)][object]$Parameter)
    $lines = [System.Collections.Generic.List[string]]::new()
    $appliesTo = @($Parameter.appliesTo)
    if ($appliesTo.Count -eq 0) { throw "Parameter '$($Parameter.name)' has no parameter-set applicability." }
    foreach ($set in $appliesTo) {
        $arguments = [System.Collections.Generic.List[string]]::new()
        if (@($Parameter.requiredIn) -contains $set) { $arguments.Add('Mandatory = true') }
        if ($null -ne $Parameter.position) { $arguments.Add("Position = $([int]$Parameter.position)") }
        $arguments.Add("ParameterSetName = $(ConvertTo-CSharpString $set)")
        if ([bool]$Parameter.valueFromPipeline) { $arguments.Add('ValueFromPipeline = true') }
        if ([bool]$Parameter.valueFromPipelineByPropertyName) { $arguments.Add('ValueFromPipelineByPropertyName = true') }
        $lines.Add("    [Parameter($($arguments -join ', '))]")
    }
    foreach ($alias in @($Parameter.aliases)) { $lines.Add("    [Alias($(ConvertTo-CSharpString ([string]$alias)))]") }
    $type = [string]$Parameter.type
    if ([string]$Parameter.nullPolicy -eq 'omit' -and ($type -eq 'string?' -or $type -eq 'string[]?' -or $type -eq 'bool?')) { $lines.Add('    [AllowNull]') }
    return $lines
}

function Get-PropertyDeclaration {
    param([Parameter(Mandatory)][object]$Cmdlet, [Parameter(Mandatory)][object]$Parameter)
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in Get-ParameterAttributeLines $Cmdlet $Parameter) { $lines.Add($line) }
    $initializer = ConvertTo-CSharpLiteral $Parameter.defaultValue ([string]$Parameter.type)
    if ($null -ne $initializer) { $initializer = " = $initializer" }
    else { $initializer = '' }
    if ([string]$Parameter.initializerPolicy -eq 'null-forgiving') { $initializer = ' = null!' }
    $terminator = if ([string]::IsNullOrEmpty($initializer)) { '' } else { ';' }
    $lines.Add("    public $($Parameter.type) $($Parameter.name) { get; set; }$initializer$terminator")
    return $lines
}

function Get-OperationParameterMapping {
    param([Parameter(Mandatory)][object]$Parameter, [Parameter(Mandatory)][string]$OperationId)
    $bindings = @($Parameter.apiBindings | Where-Object operationId -eq $OperationId)
    if ($bindings.Count -ne 1) { throw "Parameter '$($Parameter.name)' has no unique API binding for '$OperationId'." }
    return $bindings[0]
}

function Get-BindParametersCall {
    param([Parameter(Mandatory)][object]$Cmdlet, [Parameter(Mandatory)][object]$Operation)
    $mappings = @($Cmdlet.parameters | Where-Object { -not [bool]$_.isBody -and -not [bool](Get-JsonValue $_ 'isSelector') -and @($_.appliesTo) -contains [string]$Operation.parameterSet } | ForEach-Object {
        $parameter = $_
        $binding = Get-OperationParameterMapping $parameter ([string]$Operation.operationId)
        if ([string]$binding.location -eq 'body') { return }
        "(nameof($($parameter.name)), $(ConvertTo-CSharpString ([string]$binding.name)))"
    })
    if ($mappings.Count -eq 0) { return 'BindParameters()' }
    return "BindParameters(`r`n            $($mappings -join ",`r`n            ") )"
}

function Get-CmdletAttribute {
    param([Parameter(Mandatory)][object]$Cmdlet)
    $parts = ([string]$Cmdlet.cmdletName).Split('-', 2)
    $verbExpression = switch ($parts[0]) {
        'Get' { 'VerbsCommon.Get' }
        'New' { 'VerbsCommon.New' }
        'Remove' { 'VerbsCommon.Remove' }
        'Set' { 'VerbsCommon.Set' }
        default { throw "Unsupported PowerShell verb '$($parts[0])'." }
    }
    $arguments = [System.Collections.Generic.List[string]]::new()
    $arguments.Add($verbExpression)
    $arguments.Add((ConvertTo-CSharpString $parts[1]))
    if (-not [string]::IsNullOrWhiteSpace([string]$Cmdlet.defaultParameterSetName)) { $arguments.Add("DefaultParameterSetName = $(ConvertTo-CSharpString ([string]$Cmdlet.defaultParameterSetName))") }
    if ([bool]$Cmdlet.supportsShouldProcess) {
        $arguments.Add('SupportsShouldProcess = true')
        $arguments.Add("ConfirmImpact = ConfirmImpact.$([string]$Cmdlet.confirmImpact)")
    }
    return "[Cmdlet($([string]::Join(', ', $arguments)))]"
}

function Add-BindParametersLines {
    param([Parameter(Mandatory)][ref]$Lines, [Parameter(Mandatory)][object]$Cmdlet, [Parameter(Mandatory)][object]$Operation, [Parameter(Mandatory)][string]$VariableName)
    $target = $Lines.Value
    $call = Get-BindParametersCall $Cmdlet $Operation
    $callLines = $call -split "`r?`n"
    if ($callLines.Count -eq 1) { $target.Add("        var $VariableName = $call;") }
    else {
        $target.Add("        var $VariableName = $($callLines[0])")
        for ($index = 1; $index -lt $callLines.Count; $index++) {
            $suffix = if ($index -eq $callLines.Count - 1) { ';' } else { '' }
            $target.Add("$($callLines[$index])$suffix")
        }
    }
}

function Get-BodyExpression {
    param([Parameter(Mandatory)][object]$Cmdlet, [Parameter(Mandatory)][object]$Operation)
    $bodyName = [string]$Operation.operationBinding.bodyParameter
    if ([string]::IsNullOrWhiteSpace($bodyName)) { throw "Operation '$($Operation.operationId)' has no body parameter." }
    $bodyParameter = @($Cmdlet.parameters | Where-Object name -eq $bodyName)
    if ($bodyParameter.Count -ne 1) { throw "Operation '$($Operation.operationId)' body parameter '$bodyName' is not projected exactly once." }
    $serialization = [string]$Operation.operationBinding.bodySerialization
    if ([string]::IsNullOrWhiteSpace($serialization) -or $serialization -eq 'Value') { return $bodyName }
    if ($serialization -eq 'ToJson') { return "$bodyName.ToJson()" }
    throw "Unsupported body serialization '$serialization' for operation '$($Operation.operationId)'."
}

function Add-BindParametersWithBodyLines {
    param([Parameter(Mandatory)][ref]$Lines, [Parameter(Mandatory)][object]$Cmdlet, [Parameter(Mandatory)][object]$Operation, [Parameter(Mandatory)][string]$BodyExpression)
    $target = $Lines.Value
    $parameterSetName = if ($null -ne $Operation.PSObject.Properties['parameterSet']) { [string]$Operation.parameterSet } else { [string]$Operation.name }
    $mappings = @($Cmdlet.parameters | Where-Object { -not [bool]$_.isBody -and -not [bool](Get-JsonValue $_ 'isSelector') -and @($_.appliesTo) -contains $parameterSetName } | ForEach-Object {
        $parameter = $_
        $binding = Get-OperationParameterMapping $parameter ([string]$Operation.operationId)
        if ([string]$binding.location -ne 'body') { "(nameof($($parameter.name)), $(ConvertTo-CSharpString ([string]$binding.name)))" }
    })
    if ($mappings.Count -eq 0) { $target.Add("        var parameters = BindParametersWithBody($BodyExpression);"); return }
    $target.Add("        var parameters = BindParametersWithBody($BodyExpression,")
    for ($index = 0; $index -lt $mappings.Count; $index++) {
        $suffix = if ($index -eq $mappings.Count - 1) { ');' } else { ',' }
        $target.Add("            $($mappings[$index])$suffix")
    }
}

function Add-GeneratedParameterSetBranch {
    param([Parameter(Mandatory)][ref]$Lines, [Parameter(Mandatory)][object]$Cmdlet, [Parameter(Mandatory)][object]$ParameterSet)
    $target = $Lines.Value
    $operationId = [string]$ParameterSet.operationId
    $operation = @($Cmdlet.operations | Where-Object operationId -eq $operationId)
    if ($operation.Count -ne 1) { throw "Cmdlet '$($Cmdlet.cmdletName)' parameter set '$($ParameterSet.name)' has no unique operation '$operationId'." }
    $operation = $operation[0]
    $runtimeType = [string]$Cmdlet.runtimeMetadataType
    if ([string]::IsNullOrWhiteSpace($runtimeType)) { throw "Cmdlet '$($Cmdlet.cmdletName)' has no runtimeMetadataType." }
    $target.Add("        if (ParameterSetName.Equals($(ConvertTo-CSharpString ([string]$ParameterSet.name)), StringComparison.Ordinal))")
    $target.Add('        {')
    if ($null -ne $ParameterSet.operationBinding.bodyParameter -and -not [string]::IsNullOrWhiteSpace([string]$ParameterSet.operationBinding.bodyParameter)) {
        Add-BindParametersWithBodyLines -Lines $Lines -Cmdlet $Cmdlet -Operation $ParameterSet -BodyExpression (Get-BodyExpression $Cmdlet $ParameterSet)
    } else {
        Add-BindParametersLines -Lines $Lines -Cmdlet $Cmdlet -Operation $operation -VariableName 'parameters'
    }
    $errorTarget = [string]$ParameterSet.operationBinding.errorTarget
    if ([string]::IsNullOrWhiteSpace($errorTarget)) { $errorTarget = [string](Get-JsonValue $Cmdlet.execution 'errorTarget') }
    if ([string]::IsNullOrWhiteSpace($errorTarget)) { $errorTarget = [string]$Cmdlet.shouldProcessTarget }
    if ([string]$ParameterSet.operationBinding.invokeKind -eq 'paged') {
        $target.Add("            WritePaged<$($Cmdlet.outputType)>($runtimeType.Get($(ConvertTo-CSharpString $operationId)), parameters, $(if ([string]::IsNullOrWhiteSpace($errorTarget)) { 'null' } else { $errorTarget }));")
    } elseif ([string]$ParameterSet.operationBinding.outputPolicy -eq 'none' -or [string]$Cmdlet.outputPolicy -eq 'none') {
        $target.Add("            _ = InvokeSingle<JsonNode>($runtimeType.Get($(ConvertTo-CSharpString $operationId)), parameters, $(if ([string]::IsNullOrWhiteSpace($errorTarget)) { 'null' } else { $errorTarget }));")
    } else {
        $target.Add("            WriteObject(InvokeSingle<$($Cmdlet.outputType)>($runtimeType.Get($(ConvertTo-CSharpString $operationId)), parameters, $(if ([string]::IsNullOrWhiteSpace($errorTarget)) { 'null' } else { $errorTarget })));")
    }
    $target.Add('            return;')
    $target.Add('        }')
    $target.Add('')
}

function Add-GeneratedCmdlet {
    param([Parameter(Mandatory)][ref]$Lines, [Parameter(Mandatory)][object]$Cmdlet)
    $target = $Lines.Value
    $target.Add((Get-CmdletAttribute $Cmdlet))
    if ([string]$Cmdlet.outputPolicy -ne 'none') {
        if ([string]::IsNullOrWhiteSpace([string]$Cmdlet.outputType)) { throw "P3.2 cmdlet '$($Cmdlet.cmdletName)' has outputPolicy '$($Cmdlet.outputPolicy)' but no outputType." }
        $target.Add("[OutputType(typeof($($Cmdlet.outputType)))]")
    }
    $target.Add("public sealed class $($Cmdlet.className) : CloudflareCmdletBase")
    $target.Add('{')
    foreach ($parameter in @($Cmdlet.parameters | Sort-Object { if ($null -eq $_.position) { 999 } else { [int]$_.position } }, name)) {
        foreach ($line in Get-PropertyDeclaration $Cmdlet $parameter) { $target.Add($line) }
        $target.Add('')
    }
    $target.Add('    protected override void ProcessRecord()')
    $target.Add('    {')
    $execution = $Cmdlet.execution
    if ([string]$execution.strategy -ne 'parameter-set') { throw "Unsupported P3.2 execution strategy '$($execution.strategy)' for '$($Cmdlet.cmdletName)'." }
    if ([bool]$execution.shouldProcess) {
        $targetName = [string]$Cmdlet.shouldProcessTarget
        if ([string]::IsNullOrWhiteSpace($targetName)) { $targetName = [string](Get-JsonValue $execution 'shouldProcessTarget') }
        if ([string]::IsNullOrWhiteSpace($targetName)) { throw "Cmdlet '$($Cmdlet.cmdletName)' declares ShouldProcess without a target." }
        if (@($Cmdlet.parameters | Where-Object name -eq $targetName).Count -ne 1) { throw "ShouldProcess target '$targetName' is not a projected parameter of '$($Cmdlet.cmdletName)'." }
        $action = [string](Get-JsonValue $Cmdlet.execution 'shouldProcessAction')
        if ([string]::IsNullOrWhiteSpace($action)) { throw "Cmdlet '$($Cmdlet.cmdletName)' declares ShouldProcess without an action." }
        if ($action.Contains('{ParameterSetName}')) {
            $actionLiteral = '$"' + $action.Replace('"', '\"') + '"'
        } else { $actionLiteral = ConvertTo-CSharpString $action }
        $target.Add("        if (!ShouldProcess($targetName, $actionLiteral)) return;")
    }
    foreach ($parameterSet in @($Cmdlet.parameterSets | Sort-Object name)) { Add-GeneratedParameterSetBranch -Lines $Lines -Cmdlet $Cmdlet -ParameterSet $parameterSet }
    $target.Add("        throw new InvalidOperationException($(ConvertTo-CSharpString "Unsupported parameter set for $($Cmdlet.cmdletName)."));")
    $target.Add('    }')
    $target.Add('}')
    $target.Add('')
}

function ConvertTo-CSharpStringArray {
    param([AllowNull()][object[]]$Values)
    $items = @($Values | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-CSharpString $_ })
    if ($items.Count -eq 0) { return '[]' }
    return "[$($items -join ', ')]"
}

function ConvertTo-CSharpRuntimeParameters {
    param([AllowNull()][object[]]$Parameters)
    $items = @($Parameters | ForEach-Object { "new GeneratedParameterMetadata { Name = $(ConvertTo-CSharpString $_.name), Location = $(ConvertTo-CSharpString $_.location), Required = $(ConvertTo-CSharpBool $_.required) }" })
    if ($items.Count -eq 0) { return '[]' }
    return "[$($items -join ', ')]"
}

function ConvertTo-CSharpRuntimeParts {
    param([AllowNull()][object[]]$Parts)
    $items = @($Parts | ForEach-Object {
        "new GeneratedMultipartPartMetadata { ParameterName = $(ConvertTo-CSharpString $_.parameterName), PartName = $(ConvertTo-CSharpString $_.partName), ContentType = $(ConvertTo-CSharpString $_.contentType), Format = $(ConvertTo-CSharpString $_.format), Required = $(ConvertTo-CSharpBool $_.required) }"
    })
    if ($items.Count -eq 0) { return '[]' }
    return "[$($items -join ', ')]"
}

function ConvertTo-CSharpRuntimeRepresentations {
    param([AllowNull()][object[]]$Representations, [switch]$Request)
    if ($null -eq $Representations) { return '[]' }
    $items = @($Representations | Where-Object { $null -ne $_ } | ForEach-Object {
        if ($Request) { "new GeneratedRequestRepresentationMetadata { ContentType = $(ConvertTo-CSharpString $_.contentType), BodyParameterName = $(ConvertTo-CSharpString $_.bodyParameterName), Parts = $(ConvertTo-CSharpRuntimeParts @($_.parts)) }" }
        else { "new GeneratedResponseRepresentationMetadata { StatusCode = $(if ($null -eq $_.statusCode) {'null'} else {[string][int]$_.statusCode}), ContentType = $(ConvertTo-CSharpString $_.contentType), EnvelopePolicy = $(ConvertTo-CSharpString $_.envelopePolicy), ParsingMode = $(ConvertTo-CSharpString $_.parsingMode) }" }
    })
    if ($items.Count -eq 0) { return '[]' }
    return "[$($items -join ', ')]"
}

function ConvertTo-CSharpRuntimePagination {
    param([AllowNull()][object]$Pagination)
    if ($null -eq $Pagination) { return 'null' }
    $pathExpression = {
        param([AllowNull()][object]$Value)
        if ($null -eq $Value) { return 'null' }
        $text = [string]$Value
        $dot = $text.IndexOf('.')
        if ($dot -gt 0) { return "($(ConvertTo-CSharpString $text.Substring(0, $dot)) + $(ConvertTo-CSharpString $text.Substring($dot)))" }
        return ConvertTo-CSharpString $text
    }
    return "new GeneratedPaginationMetadata { Strategy = $(ConvertTo-CSharpString $Pagination.strategy), RequestFields = $(ConvertTo-CSharpStringArray @($Pagination.requestFields)), ResponseFields = $(ConvertTo-CSharpStringArray @($Pagination.responseFields)), ResultPath = $(ConvertTo-CSharpString $Pagination.resultPath), PageInfoPath = $(ConvertTo-CSharpString $Pagination.pageInfoPath), CurrentPagePath = $(& $pathExpression $Pagination.currentPagePath), TotalPagesPath = $(& $pathExpression $Pagination.totalPagesPath), NextCursorPath = $(& $pathExpression $Pagination.nextCursorPath), HasMorePath = $(& $pathExpression $Pagination.hasMorePath), NextPageRule = $(ConvertTo-CSharpString $Pagination.nextPageRule), StopRule = $(ConvertTo-CSharpString $Pagination.stopRule) }"
}

function Write-RuntimeMetadata {
    param([Parameter(Mandatory)][object]$Cmdlet, [Parameter(Mandatory)][string]$ClassName, [Parameter(Mandatory)][string]$Path)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('// <auto-generated />'); $lines.Add('#nullable enable'); $lines.Add('namespace Cloudflare.PowerShell;'); $lines.Add(''); $lines.Add("public static class $ClassName"); $lines.Add('{'); $lines.Add('    public static IReadOnlyList<GeneratedOperationMetadata> Operations { get; } ='); $lines.Add('    [')
    $operations = @($Cmdlet.operations | Sort-Object operationId)
    for ($index = 0; $index -lt $operations.Count; $index++) {
        $op = $operations[$index]; $runtime = $op.runtime
        $lines.Add('        new GeneratedOperationMetadata'); $lines.Add('        {')
        $lines.Add("            OperationId = $(ConvertTo-CSharpString ([string]$op.operationId)),")
        $lines.Add("            Method = $(ConvertTo-CSharpString ([string]$op.method)),")
        $lines.Add("            PathTemplate = $(ConvertTo-CSharpString ([string]$op.pathTemplate)),")
        $lines.Add("            Parameters = $(ConvertTo-CSharpRuntimeParameters @($runtime.parameters)),")
        $lines.Add("            RequestRepresentations = $(ConvertTo-CSharpRuntimeRepresentations @($runtime.requestRepresentations) -Request),")
        $lines.Add("            ResponseRepresentations = $(ConvertTo-CSharpRuntimeRepresentations @($runtime.responseRepresentations)),")
        $lines.Add("            Pagination = $(ConvertTo-CSharpRuntimePagination $runtime.pagination)")
        $lines.Add("        }$(if ($index -lt $operations.Count - 1) { ',' })")
    }
    $lines.Add('    ];'); $lines.Add(''); $lines.Add('    public static GeneratedOperationMetadata Get(string operationId)'); $lines.Add('        => Operations.Single(x => x.OperationId.Equals(operationId, StringComparison.Ordinal));'); $lines.Add('}')
    Write-Utf8CrLf $Path ($lines -join "`n")
}

function Write-OperationMetadata {
    param([Parameter(Mandatory)][object]$Cmdlet, [Parameter(Mandatory)][string]$ClassName, [Parameter(Mandatory)][string]$Path)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('// <auto-generated />'); $lines.Add('#nullable enable'); $lines.Add('namespace Cloudflare.PowerShell;'); $lines.Add(''); $lines.Add("public static class $ClassName"); $lines.Add('{')
    foreach ($op in @($Cmdlet.operations | Sort-Object operationId)) {
        $constantName = [string]$op.constantName
        if ([string]::IsNullOrWhiteSpace($constantName)) { throw "Operation '$($op.operationId)' has no generated constantName." }
        $lines.Add("    public const string $constantName = $(ConvertTo-CSharpString ([string]$op.operationId));")
    }
    $lines.Add('}')
    Write-Utf8CrLf $Path ($lines -join "`n")
}

function Write-GeneratedModel {
    param([Parameter(Mandatory)][object]$Model, [Parameter(Mandatory)][string]$Path)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('// <auto-generated />'); $lines.Add('#nullable enable');
    if (@($Model.properties | Where-Object { [string]$_.type -match '(^|\.)Dictionary<' }).Count -gt 0) { $lines.Add('using System.Collections.Generic;') }
    $lines.Add('using System.Text.Json.Serialization;'); $lines.Add(''); $lines.Add('namespace Cloudflare.PowerShell;'); $lines.Add('');
    $lines.Add("public sealed class $($Model.className)"); $lines.Add('{')
    foreach ($property in @($Model.properties)) {
        $type = [string]$property.type
        $initializer = if ($type -notmatch '\?$' -and $type -notin @('bool', 'bool?', 'int', 'int?', 'decimal', 'decimal?')) { ' = null!;' } else { '' }
        $lines.Add("    [JsonPropertyName($(ConvertTo-CSharpString ([string]$property.jsonName)))] public $type $($property.name) { get; set; }$initializer")
    }
    $lines.Add('}')
    $content = $lines -join "`n"
    Write-Utf8CrLf $Path $content
}

function Write-HelpMetadata {
    param(
        [Parameter(Mandatory)][object[]]$Cmdlets,
        [Parameter(Mandatory)][object]$PipelineIdentity,
        [Parameter(Mandatory)][string]$Path
    )
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('// <auto-generated />'); $lines.Add('#nullable enable'); $lines.Add('namespace Cloudflare.PowerShell;'); $lines.Add(''); $lines.Add('public sealed record GeneratedHelpModel(string Synopsis, string Description, string Source);'); $lines.Add(''); $lines.Add('public static class P32CmdletHelpMetadata'); $lines.Add('{'); $lines.Add('    public static IReadOnlyDictionary<string, GeneratedHelpModel> Commands { get; } ='); $lines.Add('        new Dictionary<string, GeneratedHelpModel>(StringComparer.Ordinal)'); $lines.Add('        {')
    for ($index = 0; $index -lt $Cmdlets.Count; $index++) {
        $help = $Cmdlets[$index].help
        $comma = if ($index -lt $Cmdlets.Count - 1) { ',' } else { '' }
        $lines.Add("            [$(ConvertTo-CSharpString ([string]$Cmdlets[$index].cmdletName))] = new($(ConvertTo-CSharpString ([string]$help.synopsis)), $(ConvertTo-CSharpString ([string]$help.description)), $(ConvertTo-CSharpString ([string]$help.source)))$comma")
    }
    $lines.Add('        };'); $lines.Add('}')
    $lines.Add('')
    $lines.Add('public sealed record GeneratedPipelineIdentityAlias(string TypeName, string AliasName, string SourceProperty);')
    $lines.Add('')
    $lines.Add('public static class P32PipelineIdentityMetadata'); $lines.Add('{')
    $lines.Add('    public static IReadOnlyList<GeneratedPipelineIdentityAlias> Aliases { get; } =')
    $lines.Add('    [')
    $aliases = @((Get-JsonValue $PipelineIdentity 'aliases') | Sort-Object typeName, aliasName)
    for ($index = 0; $index -lt $aliases.Count; $index++) {
        $alias = $aliases[$index]
        $comma = if ($index -lt $aliases.Count - 1) { ',' } else { '' }
        $lines.Add("        new GeneratedPipelineIdentityAlias($(ConvertTo-CSharpString ([string]$alias.typeName)), $(ConvertTo-CSharpString ([string]$alias.aliasName)), $(ConvertTo-CSharpString ([string]$alias.sourceProperty)))$comma")
    }
    $lines.Add('    ];'); $lines.Add('}')
    Write-Utf8CrLf $Path ($lines -join "`n")
}

function ConvertTo-HelpXmlText {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    return [System.Security.SecurityElement]::Escape([string]$Value)
}

function Get-HelpTypeName {
    param([Parameter(Mandatory)][string]$Type)
    $known = @{
        'string' = 'String'
        'string?' = 'String'
        'string[]?' = 'String[]'
        'bool' = 'Boolean'
        'bool?' = 'Boolean'
        'decimal' = 'Decimal'
        'decimal?' = 'Decimal'
        'int' = 'Int32'
        'int?' = 'Int32'
        'Hashtable' = 'Hashtable'
        'None' = 'None'
    }
    if ($known.ContainsKey($Type)) { return $known[$Type] }
    if ($Type -match '^Cloudflare\.PowerShell\.') { return $Type }
    return "Cloudflare.PowerShell.$Type"
}

function Get-HelpParameterDescription {
    param([Parameter(Mandatory)][object]$Help, [Parameter(Mandatory)][object]$Parameter)
    $descriptions = Get-JsonValue $Help 'parameterDescriptions'
    $explicit = Get-JsonValue $descriptions ([string]$Parameter.name)
    if (-not [string]::IsNullOrWhiteSpace([string]$explicit)) { return [string]$explicit }
    $parameterHelp = Get-JsonValue $Parameter 'help'
    $fallback = Get-JsonValue $parameterHelp 'description'
    if ([string]::IsNullOrWhiteSpace([string]$fallback)) { throw "P4.1 help metadata has no description for parameter '$($Parameter.name)'." }
    return [string]$fallback
}

function Get-HelpPipelineText {
    param([Parameter(Mandatory)][object]$Parameter)
    if ([bool]$Parameter.valueFromPipeline) { return 'True (ByValue)' }
    if ([bool]$Parameter.valueFromPipelineByPropertyName) { return 'True (ByPropertyName)' }
    return 'False'
}

function Get-HelpAliasesText {
    param([Parameter(Mandatory)][object]$Parameter)
    $aliases = @($Parameter.aliases | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($aliases.Count -eq 0) { return 'none' }
    return [string]::Join(', ', $aliases)
}

function Get-HelpDefaultText {
    param([Parameter(Mandatory)][object]$Parameter)
    if ($null -eq $Parameter.defaultValue) { return 'None' }
    return [string]$Parameter.defaultValue
}

function Get-HelpResourceContent {
    param([Parameter(Mandatory)][object[]]$Cmdlets, [Parameter(Mandatory)][string]$Path)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('<?xml version="1.0" encoding="utf-8"?>')
    $lines.Add('<helpItems schema="maml" xmlns="http://msh">')
    foreach ($cmdlet in @($Cmdlets | Sort-Object cmdletName)) {
        $parts = ([string]$cmdlet.cmdletName).Split('-', 2)
        $help = $cmdlet.help
        if ($null -eq $help -or [string]::IsNullOrWhiteSpace([string]$help.synopsis) -or [string]::IsNullOrWhiteSpace([string]$help.description)) {
            throw "P3.2 cmdlet '$($cmdlet.cmdletName)' has incomplete help metadata."
        }
        $name = ConvertTo-HelpXmlText $cmdlet.cmdletName
        $verb = ConvertTo-HelpXmlText $parts[0]
        $noun = ConvertTo-HelpXmlText $parts[1]
        $synopsis = ConvertTo-HelpXmlText $help.synopsis
        $description = ConvertTo-HelpXmlText $help.description
        $lines.Add('  <command:command xmlns:maml="http://schemas.microsoft.com/maml/2004/10" xmlns:command="http://schemas.microsoft.com/maml/dev/command/2004/10" xmlns:dev="http://schemas.microsoft.com/maml/dev/2004/10" xmlns:MSHelp="http://msdn.microsoft.com/mshelp">')
        $lines.Add('    <command:details>')
        $lines.Add("      <command:name>$name</command:name>")
        $lines.Add("      <command:verb>$verb</command:verb>")
        $lines.Add("      <command:noun>$noun</command:noun>")
        $lines.Add('      <maml:description>')
        $lines.Add("        <maml:para>$synopsis</maml:para>")
        $lines.Add('      </maml:description>')
        $lines.Add('    </command:details>')
        $lines.Add('    <maml:description>')
        $lines.Add("      <maml:para>$description</maml:para>")
        $setDescriptions = Get-JsonValue $help 'parameterSetDescriptions'
        if ($null -ne $setDescriptions) {
            foreach ($setDescription in @($setDescriptions.PSObject.Properties | Sort-Object Name)) {
                $setText = ConvertTo-HelpXmlText ("Parameter set '$($setDescription.Name)': $([string]$setDescription.Value)")
                $lines.Add("      <maml:para>$setText</maml:para>")
            }
        }
        $lines.Add('    </maml:description>')
        $lines.Add('    <command:syntax>')
        foreach ($parameterSet in @($cmdlet.parameterSets)) {
            $lines.Add('      <command:syntaxItem>')
            $lines.Add("        <maml:name>$name</maml:name>")
            $syntaxParameters = @($cmdlet.parameters | Where-Object { @($_.appliesTo) -contains [string]$parameterSet.name } | Sort-Object @{ Expression = { if ($null -eq $_.position) { 999 } else { [int]$_.position } } }, name)
            foreach ($parameter in $syntaxParameters) {
                $required = if (@($parameter.requiredIn) -contains [string]$parameterSet.name) { 'true' } else { 'false' }
                $position = if ($null -eq $parameter.position) { 'named' } else { [string][int]$parameter.position }
                $typeName = ConvertTo-HelpXmlText (Get-HelpTypeName ([string]$parameter.type))
                $parameterName = ConvertTo-HelpXmlText ([string]$parameter.name)
                $parameterDescription = ConvertTo-HelpXmlText (Get-HelpParameterDescription $help $parameter)
                $aliases = ConvertTo-HelpXmlText (Get-HelpAliasesText $parameter)
                $pipeline = ConvertTo-HelpXmlText (Get-HelpPipelineText $parameter)
                $variableLength = if ([string]$parameter.type -match '\[\]|Hashtable') { 'true' } else { 'false' }
                $lines.Add(('        <command:parameter required="{0}" variableLength="{1}" globbing="false" pipelineInput="{2}" position="{3}" aliases="{4}">' -f $required, $variableLength, $pipeline, $position, $aliases))
                $lines.Add("          <maml:name>$parameterName</maml:name>")
                $lines.Add('          <maml:description>')
                $lines.Add("            <maml:para>$parameterDescription</maml:para>")
                $lines.Add('          </maml:description>')
                $lines.Add(('          <command:parameterValue required="true" variableLength="{0}">{1}</command:parameterValue>' -f $variableLength, $typeName))
                $lines.Add('          <dev:type>')
                $lines.Add("            <maml:name>$typeName</maml:name>")
                $lines.Add('            <maml:uri />')
                $defaultText = ConvertTo-HelpXmlText (Get-HelpDefaultText $parameter)
                $lines.Add("          </dev:type>")
                $lines.Add("          <dev:defaultValue>$defaultText</dev:defaultValue>")
                $lines.Add('        </command:parameter>')
            }
            $lines.Add('      </command:syntaxItem>')
        }
        $lines.Add('    </command:syntax>')
        $lines.Add('    <command:parameters>')
        foreach ($parameter in @($cmdlet.parameters | Sort-Object name)) {
            $appliesTo = @($parameter.appliesTo)
            $requiredEverywhere = $appliesTo.Count -gt 0 -and @($parameter.requiredIn | Where-Object { $appliesTo -contains $_ }).Count -eq $appliesTo.Count
            $required = if ($requiredEverywhere) { 'true' } else { 'false' }
            $typeName = ConvertTo-HelpXmlText (Get-HelpTypeName ([string]$parameter.type))
            $parameterName = ConvertTo-HelpXmlText ([string]$parameter.name)
            $parameterDescription = ConvertTo-HelpXmlText (Get-HelpParameterDescription $help $parameter)
            $aliases = ConvertTo-HelpXmlText (Get-HelpAliasesText $parameter)
            $pipeline = ConvertTo-HelpXmlText (Get-HelpPipelineText $parameter)
            $variableLength = if ([string]$parameter.type -match '\[\]|Hashtable') { 'true' } else { 'false' }
            $lines.Add(('      <command:parameter required="{0}" variableLength="{1}" globbing="false" pipelineInput="{2}" position="named" aliases="{3}">' -f $required, $variableLength, $pipeline, $aliases))
            $lines.Add("        <maml:name>$parameterName</maml:name>")
            $lines.Add('        <maml:description>')
            $lines.Add("          <maml:para>$parameterDescription</maml:para>")
            $lines.Add('        </maml:description>')
            $lines.Add(('        <command:parameterValue required="true" variableLength="{0}">{1}</command:parameterValue>' -f $variableLength, $typeName))
            $lines.Add('        <dev:type>')
            $lines.Add("          <maml:name>$typeName</maml:name>")
            $lines.Add('          <maml:uri />')
            $defaultText = ConvertTo-HelpXmlText (Get-HelpDefaultText $parameter)
            $lines.Add('        </dev:type>')
            $lines.Add("        <dev:defaultValue>$defaultText</dev:defaultValue>")
            $lines.Add('      </command:parameter>')
        }
        $lines.Add('    </command:parameters>')
        $lines.Add('    <command:inputTypes>')
        $inputs = @(Get-JsonValue $help 'inputs')
        if ($inputs.Count -eq 0) { throw "P4.1 help metadata has no inputs for '$($cmdlet.cmdletName)'." }
        foreach ($input in $inputs) {
            $inputType = ConvertTo-HelpXmlText (Get-HelpTypeName ([string]$input.type))
            $inputDescription = ConvertTo-HelpXmlText ([string]$input.description)
            if ([string]::IsNullOrWhiteSpace([string]$inputDescription)) { throw "P4.1 input help is incomplete for '$($cmdlet.cmdletName)'." }
            $lines.Add('      <command:inputType>')
            $lines.Add('        <dev:type>')
            $lines.Add("          <maml:name>$inputType</maml:name>")
            $lines.Add('        </dev:type>')
            $lines.Add('        <maml:description>')
            $lines.Add("          <maml:para>$inputDescription</maml:para>")
            $lines.Add('        </maml:description>')
            $lines.Add('      </command:inputType>')
        }
        $lines.Add('    </command:inputTypes>')
        $lines.Add('    <command:returnValues>')
        $outputs = @(Get-JsonValue $help 'outputs')
        if ($outputs.Count -eq 0) { throw "P4.1 help metadata has no outputs for '$($cmdlet.cmdletName)'." }
        foreach ($output in $outputs) {
            $outputType = ConvertTo-HelpXmlText (Get-HelpTypeName ([string]$output.type))
            $outputDescription = ConvertTo-HelpXmlText ([string]$output.description)
            if ([string]::IsNullOrWhiteSpace([string]$outputDescription)) { throw "P4.1 output help is incomplete for '$($cmdlet.cmdletName)'." }
            $lines.Add('      <command:returnValue>')
            $lines.Add('        <dev:type>')
            $lines.Add("          <maml:name>$outputType</maml:name>")
            $lines.Add('        </dev:type>')
            $lines.Add('        <maml:description>')
            $lines.Add("          <maml:para>$outputDescription</maml:para>")
            $lines.Add('        </maml:description>')
            $lines.Add('      </command:returnValue>')
        }
        $lines.Add('    </command:returnValues>')
        $lines.Add('    <maml:alertSet>')
        $lines.Add('      <maml:alert>')
        $lines.Add('        <maml:para></maml:para>')
        $lines.Add('      </maml:alert>')
        $lines.Add('    </maml:alertSet>')
        $examples = @(Get-JsonValue $help 'examples')
        if ($examples.Count -eq 0) { throw "P4.1 help metadata has no examples for '$($cmdlet.cmdletName)'." }
        $exampleNumber = 1
        $lines.Add('    <command:examples>')
        foreach ($example in $examples) {
            $title = [string](Get-JsonValue $example 'title')
            if ([string]::IsNullOrWhiteSpace($title)) { $title = "Example $exampleNumber" }
            $titleText = ConvertTo-HelpXmlText $title
            $code = ConvertTo-HelpXmlText (Get-JsonValue $example 'code')
            $remarks = ConvertTo-HelpXmlText (Get-JsonValue $example 'remarks')
            if ([string]::IsNullOrWhiteSpace([string]$code) -or [string]::IsNullOrWhiteSpace([string]$remarks)) { throw "P4.1 example '$title' is incomplete for '$($cmdlet.cmdletName)'." }
            $lines.Add('      <command:example>')
            $lines.Add("        <maml:title>-------------------------- Example $exampleNumber -------------------------- $titleText</maml:title>")
            $lines.Add("        <dev:code>$code</dev:code>")
            $lines.Add('        <dev:remarks>')
            $lines.Add("          <maml:para>$remarks</maml:para>")
            $lines.Add('        </dev:remarks>')
            $lines.Add('      </command:example>')
            $exampleNumber++
        }
        $lines.Add('    </command:examples>')
        $relatedLinks = @(Get-JsonValue $help 'relatedLinks')
        if ($relatedLinks.Count -gt 0) {
            $lines.Add('    <maml:relatedLinks>')
            foreach ($link in $relatedLinks) {
                $linkText = ConvertTo-HelpXmlText (Get-JsonValue $link 'text')
                $uri = ConvertTo-HelpXmlText (Get-JsonValue $link 'uri')
                if ([string]::IsNullOrWhiteSpace([string]$linkText) -or [string]::IsNullOrWhiteSpace([string]$uri)) { throw "P4.1 related link is incomplete for '$($cmdlet.cmdletName)'." }
                $lines.Add('      <maml:navigationLink>')
                $lines.Add("        <maml:linkText>$linkText</maml:linkText>")
                $lines.Add("        <maml:uri>$uri</maml:uri>")
                $lines.Add('      </maml:navigationLink>')
            }
            $lines.Add('    </maml:relatedLinks>')
        }
        $lines.Add('  </command:command>')
    }
    $lines.Add('</helpItems>')
    return ($lines -join "`n")
}

function Write-HelpResource {
    param([Parameter(Mandatory)][object[]]$Cmdlets, [Parameter(Mandatory)][string]$Path)
    Write-Utf8CrLf $Path (Get-HelpResourceContent $Cmdlets $Path)
}

function Assert-RuntimeMetadataSourceContract {
    param(
        [Parameter(Mandatory)][object]$Artifact,
        [Parameter(Mandatory)][string]$RuntimeSource,
        [Parameter(Mandatory)][string]$RuntimeMetadataType
    )
    if ($RuntimeSource -notmatch "public static class $([regex]::Escape($RuntimeMetadataType))\s*") {
        throw "P3.2 runtime metadata source does not declare '$RuntimeMetadataType'."
    }
    $canonicalOperations = @($Artifact.cmdlets | Where-Object runtimeMetadataType -eq $RuntimeMetadataType | ForEach-Object operations)
    if ($canonicalOperations.Count -eq 0) { throw "P3.2 canonical artifact has no operations for runtime metadata '$RuntimeMetadataType'." }
    $runtimeOperationMatches = @([regex]::Matches($RuntimeSource, 'OperationId\s*=\s*"([^"]+)"'))
    $expectedOperationIds = @($canonicalOperations | ForEach-Object operationId | Sort-Object)
    $actualOperationIds = @($runtimeOperationMatches | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
    if (($expectedOperationIds -join '|') -ne ($actualOperationIds -join '|')) {
        throw "P3.2 runtime metadata operation set drifted for '$RuntimeMetadataType'. Expected '$($expectedOperationIds -join ',')', actual '$($actualOperationIds -join ',')'."
    }

    foreach ($operation in $canonicalOperations) {
        $operationMatch = @($runtimeOperationMatches | Where-Object { $_.Groups[1].Value -eq [string]$operation.operationId })
        if ($operationMatch.Count -ne 1) { throw "Runtime metadata '$RuntimeMetadataType' is missing canonical operation '$($operation.operationId)'." }
        $start = [int]$operationMatch[0].Index
        $next = @($runtimeOperationMatches | Where-Object { $_.Index -gt $start } | Sort-Object Index | Select-Object -First 1)
        $length = if ($next.Count -eq 1) { [int]$next[0].Index - $start } else { $RuntimeSource.Length - $start }
        $operationBlock = $RuntimeSource.Substring($start, $length)
        $expectedParameters = @($operation.runtime.parameters | ForEach-Object { "$($_.name)|$($_.location)|$(([bool]$_.required).ToString().ToLowerInvariant())" } | Sort-Object)
        $actualParameters = @([regex]::Matches($operationBlock, 'Name\s*=\s*"([^"]+)",\s*Location\s*=\s*"([^"]+)",\s*Required\s*=\s*(true|false)') | ForEach-Object { "$($_.Groups[1].Value)|$($_.Groups[2].Value)|$($_.Groups[3].Value)" } | Sort-Object)
        if (($expectedParameters -join '|') -ne ($actualParameters -join '|')) { throw "Runtime metadata '$RuntimeMetadataType' Parameters drifted for '$($operation.operationId)'." }
        $expectedFields = @{
            OperationId = "OperationId = $(ConvertTo-CSharpString ([string]$operation.operationId))"
            Method = "Method = $(ConvertTo-CSharpString ([string]$operation.method))"
            PathTemplate = "PathTemplate = $(ConvertTo-CSharpString ([string]$operation.pathTemplate))"
            RequestRepresentations = "RequestRepresentations = $(ConvertTo-CSharpRuntimeRepresentations @($operation.runtime.requestRepresentations) -Request)"
            ResponseRepresentations = "ResponseRepresentations = $(ConvertTo-CSharpRuntimeRepresentations @($operation.runtime.responseRepresentations))"
            Pagination = "Pagination = $(ConvertTo-CSharpRuntimePagination $operation.runtime.pagination)"
        }
        foreach ($field in $expectedFields.GetEnumerator()) {
            if ($operationBlock -notmatch [regex]::Escape($field.Value)) { throw "Runtime metadata '$RuntimeMetadataType' $($field.Key) drifted for '$($operation.operationId)'. Expected: $($field.Value)" }
        }
    }
}

function Normalize-GeneratedSource {
    param([Parameter(Mandatory)][string]$Content)
    return $Content.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
}

function Assert-ArtifactFresh {
    param([Parameter(Mandatory)][object]$Artifact, [Parameter(Mandatory)][string]$ProjectRoot)
    if ([int]$Artifact.version -ne 3 -or [string]$Artifact.sourcePolicy -ne 'normalized-model-plus-projection-policy' -or [string]$Artifact.semanticAlgorithm -ne 'SHA256-CanonicalJson-v1') { throw 'P3.2 canonical artifact is not version 3 normalized/projection output.' }
    foreach ($source in @($Artifact.sourceFiles)) {
        $path = Join-Path $ProjectRoot ([string]$source.path)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "P3.2 canonical artifact source is missing: $path" }
        $actual = Get-P32PortableFileHash -Path $path
        if ($actual -ne [string]$source.sha256) { throw "P3.2 canonical artifact is stale for '$($source.path)'. Run Project-P32Projection.ps1 first." }
    }
    $digest = Get-P32CanonicalDigest $Artifact
    if ([string]$Artifact.canonicalDigest -ne $digest) { throw "P3.2 canonical artifact semantic digest is invalid. Expected '$digest', actual '$($Artifact.canonicalDigest)'." }
}

function Assert-ArtifactSemanticParity {
    param([Parameter(Mandatory)][object]$Artifact, [Parameter(Mandatory)][string]$ProjectRoot)
    $expected = New-P32CanonicalArtifact -Root $ProjectRoot `
        -DnsPath (Join-Path $ProjectRoot 'artifacts/generated-normalized/document.json') `
        -ZonePath (Join-Path $ProjectRoot 'fixtures/p2.1/zones/document.json') `
        -ZoneProjection (Join-Path $ProjectRoot 'artifacts/p2.3/projection/zones.json') `
        -BaseProjection (Join-Path $ProjectRoot 'overrides/powershell-projection.json') `
        -P23Projection (Join-Path $ProjectRoot 'overrides/powershell-p23-projection.json') `
        -P32Policy (Join-Path $ProjectRoot 'overrides/powershell-p32-projection.json')
    $actualDigest = Get-P32CanonicalDigest $Artifact
    $expectedDigest = Get-P32CanonicalDigest $expected
    if ($actualDigest -ne $expectedDigest -or [string]$Artifact.canonicalDigest -ne $expectedDigest) {
        throw "P3.2 canonical artifact semantic projection drifted. Expected '$expectedDigest', actual '$actualDigest'."
    }
}

function Assert-ArtifactContract {
    param([Parameter(Mandatory)][object]$Artifact)
    $operationIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($cmdlet in @($Artifact.cmdlets)) {
        if ([string]::IsNullOrWhiteSpace([string]$cmdlet.className) -or [string]::IsNullOrWhiteSpace([string]$cmdlet.runtimeMetadataType)) { throw "P3.2 cmdlet '$($cmdlet.cmdletName)' has incomplete renderer metadata." }
        if ($null -eq $cmdlet.execution -or [string]::IsNullOrWhiteSpace([string]$cmdlet.execution.strategy)) { throw "P3.2 cmdlet '$($cmdlet.cmdletName)' has no execution strategy." }
        if ([string]$cmdlet.outputPolicy -notin @('item', 'single', 'none')) { throw "P3.2 cmdlet '$($cmdlet.cmdletName)' has an unsupported output policy." }
        if ([string]$cmdlet.outputPolicy -eq 'none') {
            if (-not [string]::IsNullOrWhiteSpace([string]$cmdlet.outputType)) { throw "P3.2 cmdlet '$($cmdlet.cmdletName)' has outputType metadata despite outputPolicy 'none'." }
        } elseif ([string]::IsNullOrWhiteSpace([string]$cmdlet.outputType)) {
            throw "P3.2 cmdlet '$($cmdlet.cmdletName)' has outputPolicy '$($cmdlet.outputPolicy)' but no outputType metadata."
        }
        $sets = @($cmdlet.parameterSets | ForEach-Object name)
        if ($sets.Count -eq 0 -or @($sets | Sort-Object -Unique).Count -ne $sets.Count) { throw "P3.2 cmdlet '$($cmdlet.cmdletName)' has no unique parameter sets." }
        foreach ($parameter in @($cmdlet.parameters)) {
            if (@($parameter.appliesTo | Where-Object { $sets -notcontains $_ }).Count -gt 0) { throw "P3.2 parameter '$($parameter.name)' references an unknown parameter set." }
            if (@($parameter.appliesTo).Count -eq 0) { throw "P3.2 parameter '$($parameter.name)' has no applicability." }
            if (@($parameter.appliesTo | Where-Object { @($parameter.requiredIn) -contains $_ -and @($parameter.apiBindings | Where-Object operationId -in @($cmdlet.operations | ForEach-Object operationId)).Count -eq 0 }).Count -gt 0) { throw "P3.2 parameter '$($parameter.name)' has required applicability without binding." }
            $aliases = @($parameter.aliases)
            if (($aliases -contains $parameter.name) -or (@($aliases | Sort-Object -Unique).Count -ne $aliases.Count)) { throw "P3.2 parameter '$($parameter.name)' has an invalid or duplicate alias." }
        }
        Assert-P32ArtifactParameterSetDiscriminators $cmdlet
        foreach ($operation in @($cmdlet.operations)) {
            if (-not $operationIds.Add([string]$operation.operationId)) { throw "P3.2 operation '$($operation.operationId)' is duplicated in the canonical artifact." }
            if ($null -eq $operation.runtime) { throw "P3.2 operation '$($operation.operationId)' has no runtime metadata." }
            $set = @($cmdlet.parameterSets | Where-Object { [string]$_.operationId -eq [string]$operation.operationId })
            if ($set.Count -ne 1) { throw "P3.2 operation '$($operation.operationId)' is not mapped by exactly one parameter set." }
            if ([string]$set[0].operationBinding.invokeKind -notin @('single', 'paged')) { throw "P3.2 operation '$($operation.operationId)' has unsupported invokeKind." }
            if ([string]$operation.outputPolicy -eq 'none' -and -not [string]::IsNullOrWhiteSpace([string]$operation.outputType)) { throw "P3.2 operation '$($operation.operationId)' has outputType metadata despite outputPolicy 'none'." }
            if ([string]$operation.outputPolicy -ne 'none' -and [string]::IsNullOrWhiteSpace([string]$operation.outputType)) { throw "P3.2 operation '$($operation.operationId)' has no outputType metadata." }
            if ([string]$set[0].operationBinding.method -ne [string]$operation.method -or [string]$set[0].operationBinding.pathTemplate -ne [string]$operation.pathTemplate) { throw "P3.2 operation '$($operation.operationId)' parameter-set binding drifted from HTTP metadata." }
            $applicableParameters = @($cmdlet.parameters | Where-Object { -not [bool](Get-JsonValue $_ 'isSelector') -and @($_.appliesTo) -contains [string]$operation.parameterSet })
            $bodyParameterName = [string](Get-JsonValue $set[0].operationBinding 'bodyParameter')
            $bodyParameters = @($applicableParameters | Where-Object isBody)
            if ([string]::IsNullOrWhiteSpace($bodyParameterName)) {
                if ($bodyParameters.Count -ne 0) { throw "P3.2 operation '$($operation.operationId)' has an unbound body parameter." }
            } elseif ($bodyParameters.Count -ne 1 -or [string]$bodyParameters[0].name -ne $bodyParameterName) {
                throw "P3.2 operation '$($operation.operationId)' body binding does not identify exactly one projected body parameter."
            }
            foreach ($parameter in $applicableParameters) {
                $bindings = @($parameter.apiBindings | Where-Object { [string]$_.operationId -eq [string]$operation.operationId })
                if ($bindings.Count -ne 1) { throw "P3.2 parameter '$($parameter.name)' is not consumed exactly once by '$($operation.operationId)'." }
                if ([bool]$parameter.isBody -and [string]$bindings[0].location -ne 'body') { throw "P3.2 body parameter '$($parameter.name)' has a non-body API binding." }
                if (-not [bool]$parameter.isBody -and [string]$bindings[0].location -eq 'body') { throw "P3.2 non-body parameter '$($parameter.name)' has a body API binding." }
            }
            $projectedRuntimeParameters = @($cmdlet.parameters | Where-Object { -not [bool]$_.isBody } | ForEach-Object {
                $parameter = $_
                $required = ([bool](@($parameter.requiredIn) -contains [string]$operation.parameterSet)).ToString().ToLowerInvariant()
                @($parameter.apiBindings | Where-Object { $_.operationId -eq [string]$operation.operationId } | ForEach-Object {
                    "$($_.name)|$($_.location)|$required"
                })
            } | Sort-Object)
            $runtimeParameters = @($operation.runtime.parameters | ForEach-Object {
                "$($_.name)|$($_.location)|$(([bool]$_.required).ToString().ToLowerInvariant())"
            } | Sort-Object)
            if (($projectedRuntimeParameters -join '|') -ne ($runtimeParameters -join '|')) {
                throw "P3.2 operation '$($operation.operationId)' public/runtime parameter contract drifted."
            }
            if ([string]$operation.method -notmatch '^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)$' -or [string]::IsNullOrWhiteSpace([string]$operation.pathTemplate)) { throw "P3.2 operation '$($operation.operationId)' has invalid HTTP metadata." }
            foreach ($representation in @($operation.runtime.requestRepresentations)) {
                if ($null -ne $representation -and ([string]::IsNullOrWhiteSpace([string]$representation.contentType) -or [string]::IsNullOrWhiteSpace([string]$representation.bodyParameterName))) { throw "P3.2 operation '$($operation.operationId)' has an invalid request representation." }
                foreach ($part in @((Get-JsonValue $representation 'parts'))) { if ($null -ne $part -and ([string]::IsNullOrWhiteSpace([string]$part.parameterName) -or [string]::IsNullOrWhiteSpace([string]$part.partName) -or [string]::IsNullOrWhiteSpace([string]$part.contentType) -or [string]::IsNullOrWhiteSpace([string]$part.format))) { throw "P3.2 operation '$($operation.operationId)' has an invalid multipart part." } }
            }
            foreach ($representation in @($operation.runtime.responseRepresentations)) { if ($null -ne $representation -and ([string]::IsNullOrWhiteSpace([string]$representation.contentType) -or [string]::IsNullOrWhiteSpace([string]$representation.envelopePolicy) -or [string]::IsNullOrWhiteSpace([string]$representation.parsingMode))) { throw "P3.2 operation '$($operation.operationId)' has an invalid response representation." } }
            if ($null -ne $operation.runtime.pagination -and [string]::IsNullOrWhiteSpace([string]$operation.runtime.pagination.stopRule)) { throw "P3.2 operation '$($operation.operationId)' has no pagination stop rule." }
        }
    }
    foreach ($model in @($Artifact.models)) {
        if ([string]::IsNullOrWhiteSpace([string]$model.className) -or @($model.properties).Count -eq 0) { throw 'P3.2 artifact contains an incomplete output model.' }
        foreach ($property in @($model.properties)) { if ([string]::IsNullOrWhiteSpace([string]$property.name) -or [string]::IsNullOrWhiteSpace([string]$property.jsonName) -or [string]::IsNullOrWhiteSpace([string]$property.type)) { throw "P3.2 model '$($model.className)' contains an incomplete property." } }
    }
}

if (-not $Library) {
if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf)) { throw "P3.2 canonical artifact is missing: $ArtifactPath" }
if (-not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) { throw "P3.2 source template is missing: $TemplatePath" }

$artifact = Get-Content -Raw -LiteralPath $ArtifactPath | ConvertFrom-Json
Assert-ArtifactFresh $artifact $ProjectRoot
Assert-ArtifactSemanticParity $artifact $ProjectRoot
Assert-ArtifactContract $artifact
$template = Get-Content -Raw -LiteralPath $TemplatePath -Encoding UTF8
if ($template -notmatch '\{\{P32_CMDLETS\}\}') { throw 'P3.2 source template is missing the canonical renderer token.' }

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('__P32_SEED__')
foreach ($cmdlet in @($artifact.cmdlets)) { Add-GeneratedCmdlet -Lines ([ref]$lines) -Cmdlet $cmdlet }
$lines.RemoveAt(0)
$rendered = $template.Replace('{{P32_CMDLETS}}', (($lines -join "`n").TrimEnd([char[]]"`r`n")))
if ($rendered -match '\{\{[^}]+\}\}') { throw 'P3.2 generated source contains unresolved template tokens.' }
$sourceExists = Test-Path -LiteralPath $SourcePath -PathType Leaf
if ($ValidateOnly -and -not $sourceExists) { throw "P3.2 ValidateOnly source is missing: $SourcePath" }
$sourceForValidation = if ($sourceExists) { Get-Content -Raw -LiteralPath $SourcePath -Encoding UTF8 } else { $rendered }
foreach ($cmdlet in @($artifact.cmdlets)) {
    if ($sourceForValidation -notmatch "public sealed class $([regex]::Escape([string]$cmdlet.className))\s*:") { throw "Generated P3.2 source is missing '$($cmdlet.className)'." }
    foreach ($parameter in @($cmdlet.parameters)) {
        $declaration = "public $([regex]::Escape([string]$parameter.type)) $([regex]::Escape([string]$parameter.name))\s*\{"
        if ($sourceForValidation -notmatch $declaration) { throw "Generated P3.2 source does not consume parameter '$($parameter.name)' with type '$($parameter.type)'." }
        foreach ($alias in @($parameter.aliases)) { if ($sourceForValidation -notmatch "Alias\($(ConvertTo-CSharpString ([string]$alias))\)") { throw "Generated P3.2 source does not consume alias '$alias' for '$($parameter.name)'." } }
    }
}
foreach ($runtimeMetadataType in @($artifact.cmdlets | ForEach-Object runtimeMetadataType | Sort-Object -Unique)) {
    $runtimePath = switch ($runtimeMetadataType) {
        'CfDnsRecordRuntimeMetadata' { $RuntimeSourcePath; break }
        'CfZoneRuntimeMetadata' { $ZoneRuntimeSourcePath; break }
        default {
            $generatedRuntime = @($artifact.cmdlets | Where-Object runtimeMetadataType -eq $runtimeMetadataType | ForEach-Object { $_.generated.runtimeMetadataPath } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First 1)
            if ($generatedRuntime.Count -ne 1) { throw "P3.2 runtime metadata '$runtimeMetadataType' has no source path." }
            Join-Path $ProjectRoot ([string]$generatedRuntime[0])
        }
    }
    if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) { throw "Runtime metadata '$runtimeMetadataType' is missing: $runtimePath" }
    Assert-RuntimeMetadataSourceContract $artifact (Get-Content -Raw -LiteralPath $runtimePath -Encoding UTF8) $runtimeMetadataType
}

$renderedNormalized = Normalize-GeneratedSource $rendered
if ($ValidateOnly) {
    $existingNormalized = Normalize-GeneratedSource $sourceForValidation
    $expectedHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($renderedNormalized))).Replace('-', '').ToLowerInvariant()
    $actualHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($existingNormalized))).Replace('-', '').ToLowerInvariant()
    if ($expectedHash -ne $actualHash -or $renderedNormalized -cne $existingNormalized) {
        throw "P3.2 generated source renderer drifted for '$SourcePath'. Expected renderer SHA256 '$expectedHash', actual source SHA256 '$actualHash'."
    }
} else {
    Write-Utf8CrLf $SourcePath $rendered
}

$helpResourcePath = Join-Path $ProjectRoot 'module/Cloudflare.PowerShell/Cloudflare.PowerShell-help.xml'
$renderedHelpResource = Get-HelpResourceContent @($artifact.cmdlets) $helpResourcePath
if ($ValidateOnly) {
    if (-not (Test-Path -LiteralPath $helpResourcePath -PathType Leaf)) { throw "P3.2 ValidateOnly help resource is missing: $helpResourcePath" }
    $existingHelpResource = Get-Content -Raw -LiteralPath $helpResourcePath -Encoding UTF8
    $expectedHelpHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes((Normalize-GeneratedSource $renderedHelpResource)))).Replace('-', '').ToLowerInvariant()
    $actualHelpHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes((Normalize-GeneratedSource $existingHelpResource)))).Replace('-', '').ToLowerInvariant()
    if ($expectedHelpHash -ne $actualHelpHash -or (Normalize-GeneratedSource $existingHelpResource) -cne (Normalize-GeneratedSource $renderedHelpResource)) {
        throw "P3.2 generated help resource drifted for '$helpResourcePath'. Expected SHA256 '$expectedHelpHash', actual '$actualHelpHash'."
    }
}

if (-not $ValidateOnly) {
    foreach ($model in @($artifact.models)) {
        $modelPath = [string]$model.path
        if ([string]::IsNullOrWhiteSpace($modelPath)) { throw "P3.2 model '$($model.className)' has no generated path." }
        Write-GeneratedModel $model (Join-Path $ProjectRoot $modelPath)
    }
    foreach ($cmdlet in @($artifact.cmdlets)) {
        $generated = $cmdlet.generated
        if ($null -eq $generated) { continue }
        $operationMetadataPath = [string]$generated.operationMetadataPath
        if (-not [string]::IsNullOrWhiteSpace($operationMetadataPath)) { Write-OperationMetadata $cmdlet ([string]$generated.operationMetadataType) (Join-Path $ProjectRoot $operationMetadataPath) }
        $runtimeMetadataPath = [string]$generated.runtimeMetadataPath
        if (-not [string]::IsNullOrWhiteSpace($runtimeMetadataPath)) { Write-RuntimeMetadata $cmdlet ([string]$cmdlet.runtimeMetadataType) (Join-Path $ProjectRoot $runtimeMetadataPath) }
    }
    Write-HelpMetadata @($artifact.cmdlets) $artifact.pipelineIdentity (Join-Path $GeneratedRoot 'Metadata/P32CmdletHelpMetadata.cs')
    Write-HelpResource @($artifact.cmdlets) $helpResourcePath
}

[pscustomobject]@{
    Stage = 'P3.2'
    Cmdlets = @($artifact.cmdlets | ForEach-Object cmdletName)
    ProjectionArtifact = [IO.Path]::GetRelativePath($ProjectRoot, $ArtifactPath).Replace('\', '/')
    GeneratedSource = [IO.Path]::GetRelativePath($ProjectRoot, $SourcePath).Replace('\', '/')
    RuntimeMetadata = @($artifact.cmdlets | ForEach-Object runtimeMetadataType | Sort-Object -Unique)
} | ConvertTo-Json -Depth 10
Write-Output 'PASS P3.2 canonical-artifact source generation and runtime drift checks'
}
