[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [int]$ExpectedOperationCount = 6,
    [string]$FixtureRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$fixtureRoot = if ($FixtureRoot) { $FixtureRoot } else { Join-Path $ProjectRoot 'fixtures/dns-records' }
$outputRoot = Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated'
$modelOutputRoot = Join-Path $outputRoot 'Models'
$metadataOutputRoot = Join-Path $outputRoot 'Metadata'
$projectionRoot = Join-Path $ProjectRoot 'artifacts/projection'
$correctionPath = Join-Path $ProjectRoot 'overrides/api-corrections.json'
$projectionPath = Join-Path $ProjectRoot 'overrides/powershell-projection.json'

$csharpKeywords = @{
    abstract=$true; as=$true; base=$true; bool=$true; break=$true; byte=$true; case=$true; catch=$true; char=$true; checked=$true; class=$true; const=$true; continue=$true; decimal=$true; default=$true; delegate=$true; do=$true; double=$true; else=$true; enum=$true; event=$true; explicit=$true; extern=$true; false=$true; finally=$true; fixed=$true; float=$true; for=$true; foreach=$true; goto=$true; if=$true; implicit=$true; in=$true; int=$true; interface=$true; internal=$true; is=$true; lock=$true; long=$true; namespace=$true; new=$true; null=$true; object=$true; operator=$true; out=$true; override=$true; params=$true; private=$true; protected=$true; public=$true; readonly=$true; ref=$true; return=$true; sbyte=$true; sealed=$true; short=$true; sizeof=$true; stackalloc=$true; static=$true; string=$true; struct=$true; switch=$true; this=$true; throw=$true; true=$true; try=$true; typeof=$true; uint=$true; ulong=$true; unchecked=$true; unsafe=$true; ushort=$true; using=$true; virtual=$true; void=$true; volatile=$true; while=$true; record=$true; required=$true; file=$true; init=$true; var=$true; global=$true; value=$true;
}

function Get-JsonPropertyValue {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) { return $null }
    return $Object.PSObject.Properties[$Name].Value
}

function Write-Utf8CrLf {
    param([string]$Path, [string]$Content)
    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
    [System.IO.File]::WriteAllText($Path, $normalized, [System.Text.UTF8Encoding]::new($false))
}

function Copy-JsonObject {
    param([object]$Object)
    return ($Object | ConvertTo-Json -Depth 100 | ConvertFrom-Json)
}

function Test-CorrectionMatch {
    param([object]$Operation, [object]$Match)
    if ($null -ne (Get-JsonPropertyValue $Match 'operationId') -and $Operation.operationId -ne $Match.operationId) { return $false }
    if ($null -ne (Get-JsonPropertyValue $Match 'method') -and $Operation.method.ToUpperInvariant() -ne $Match.method.ToString().ToUpperInvariant()) { return $false }
    if ($null -ne (Get-JsonPropertyValue $Match 'path') -and $Operation.pathTemplate -ne $Match.path) { return $false }
    if ($null -ne (Get-JsonPropertyValue $Match 'resourcePath')) {
        if ((@($Operation.resourcePath) -join '/') -ne (@($Match.resourcePath) -join '/')) { return $false }
    }
    if ($null -ne (Get-JsonPropertyValue $Match 'schemaName')) {
        $schemas = @()
        $schemas += @($Operation.parameters | ForEach-Object { $_.schema })
        if ($Operation.requestBody) { $schemas += @($Operation.requestBody.representations | ForEach-Object { $_.schema }) }
        $schemas += @($Operation.responses | ForEach-Object { $_.representations | ForEach-Object { $_.schema } })
        if ($schemas -notcontains $Match.schemaName) { return $false }
    }
    return $true
}

function Add-CorrectionTrace {
    param([object]$Operation, [int]$RuleIndex, [object]$Rule)
    if ($null -eq (Get-JsonPropertyValue $Operation 'correctionTrace')) {
        $Operation | Add-Member -NotePropertyName correctionTrace -NotePropertyValue @() -Force | Out-Null
    }
    $trace = @($Operation.correctionTrace) + @([pscustomobject]@{
        RuleIndex = $RuleIndex
        Match = $Rule.match
        Reason = $Rule.reason
        Source = $Rule.source
    })
    $Operation.correctionTrace = $trace
    return
}

function Set-CorrectionProperties {
    param([object]$Target, [object]$Values)
    foreach ($property in $Values.PSObject.Properties | Sort-Object Name) {
        $Target | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force | Out-Null
    }
}

function Apply-CorrectionRule {
    param([object]$Operation, [object]$Rule, [int]$RuleIndex)
    $corrected = Copy-JsonObject $Operation
    Add-CorrectionTrace $corrected $RuleIndex $Rule
    $actions = $Rule.actions

    $requestBodyAction = Get-JsonPropertyValue $actions 'requestBody'
    if ($null -ne $requestBodyAction) {
        if ($null -eq $corrected.requestBody) { $corrected | Add-Member -NotePropertyName requestBody -NotePropertyValue ([pscustomobject]@{}) -Force }
        Set-CorrectionProperties $corrected.requestBody $requestBodyAction
    }

    $parameterActions = Get-JsonPropertyValue $actions 'parameters'
    if ($null -ne $parameterActions) { foreach ($parameterCorrection in @($parameterActions)) {
        $parameter = @($corrected.parameters | Where-Object {
            ($null -eq (Get-JsonPropertyValue $parameterCorrection 'name') -or $_.name -eq $parameterCorrection.name) -and
            ($null -eq (Get-JsonPropertyValue $parameterCorrection 'location') -or $_.location -eq $parameterCorrection.location)
        } | Select-Object -First 1)
        if ($parameter.Count -eq 1) { Set-CorrectionProperties $parameter[0] $parameterCorrection.set }
    } }

    $responseActions = Get-JsonPropertyValue $actions 'responses'
    if ($null -ne $responseActions) { foreach ($responseCorrection in @($responseActions)) {
        foreach ($responseCase in @($corrected.responses | Where-Object { $_.statusSelector.value -eq $responseCorrection.status })) {
            foreach ($representation in @($responseCase.representations | Where-Object { $null -eq (Get-JsonPropertyValue $responseCorrection 'contentType') -or $_.contentType -eq $responseCorrection.contentType })) {
                Set-CorrectionProperties $representation $responseCorrection.set
            }
        }
    } }

    $paginationAction = Get-JsonPropertyValue $actions 'pagination'
    if ($null -ne $paginationAction) {
        if ($null -eq $corrected.pagination) { $corrected | Add-Member -NotePropertyName pagination -NotePropertyValue ([pscustomobject]@{}) -Force }
        Set-CorrectionProperties $corrected.pagination $paginationAction
    }
    $semanticAction = Get-JsonPropertyValue $actions 'semantic'
    if ($null -ne $semanticAction) {
        if ($null -eq $corrected.operationSemantic) { $corrected | Add-Member -NotePropertyName operationSemantic -NotePropertyValue ([pscustomobject]@{}) -Force }
        Set-CorrectionProperties $corrected.operationSemantic $semanticAction
    }
    return $corrected
}

function Apply-ApiCorrections {
    param([object]$Operation, [object]$CorrectionDocument)
    $corrected = Copy-JsonObject $Operation
    $index = 0
    foreach ($rule in @($CorrectionDocument.rules | Sort-Object { Get-JsonPropertyValue $_.match 'operationId' }, { Get-JsonPropertyValue $_.match 'method' }, { Get-JsonPropertyValue $_.match 'path' }, { Get-JsonPropertyValue $_.match 'schemaName' })) {
        if (Test-CorrectionMatch $corrected $rule.match) { $corrected = Apply-CorrectionRule $corrected $rule $index }
        $index++
    }
    return $corrected
}

function Get-ProjectionOverride {
    param([object]$ProjectionDocument, [object]$Operation)
    $override = $ProjectionDocument.operations.PSObject.Properties[$Operation.operationId]
    if ($null -eq $override) { $override = [pscustomobject]@{} } else { $override = $override.Value }
    return $override
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

function ConvertTo-CSharpIdentifier {
    param([string]$Value)
    $identifier = [regex]::Replace($Value, '[^A-Za-z0-9_]', '_')
    $identifier = [regex]::Replace($identifier, '_+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($identifier)) { $identifier = 'Unnamed' }
    if ($identifier[0] -match '[0-9]') { $identifier = "N_$identifier" }
    if ($csharpKeywords.ContainsKey($identifier)) { $identifier = "_${identifier}" }
    return $identifier
}

function Get-OperationSymbol {
    param([object]$Operation)
    $resource = @($Operation.resourcePath | ForEach-Object { ConvertTo-CSharpIdentifier $_ }) -join '_'
    $semantic = ConvertTo-CSharpIdentifier $Operation.operationSemantic.kind
    $operation = ConvertTo-CSharpIdentifier $Operation.operationId
    return "Operation_${resource}_${semantic}_${operation}"
}

$correctionDocument = Get-Content -Raw -LiteralPath $correctionPath | ConvertFrom-Json
$projectionDocument = Get-Content -Raw -LiteralPath $projectionPath | ConvertFrom-Json
$operations = @(Get-ChildItem -LiteralPath $fixtureRoot -Filter '*.json' -File |
    Where-Object { $_.Name -ne 'schemas.json' } |
    Sort-Object Name |
    ForEach-Object {
        $source = Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json
        $corrected = Apply-ApiCorrections $source $correctionDocument
        $override = Get-ProjectionOverride $projectionDocument $corrected
        [pscustomobject]@{ Fixture = $_.Name; Operation = $corrected; Override = $override }
    })

if ($operations.Count -ne $ExpectedOperationCount) { throw "Expected $ExpectedOperationCount operation fixtures, found $($operations.Count)." }

$projectedBindings = @($operations | ForEach-Object {
    $entry = $_
    $op = $entry.Operation
    $override = $entry.Override
    $outputPolicy = Get-JsonPropertyValue $override 'outputPolicy'
    $paging = Get-JsonPropertyValue $override 'paging'
    $supportsShouldProcess = Get-JsonPropertyValue $override 'supportsShouldProcess'
    $confirmImpact = Get-JsonPropertyValue $override 'confirmImpact'
    $requestBody = Get-JsonPropertyValue $op 'requestBody'
    $trace = Get-JsonPropertyValue $op 'correctionTrace'
    $traceItems = if ($null -ne $trace) { @($trace) } else { @() }
    $parameters = @($op.parameters | ForEach-Object {
        $parameterName = if ($_.PSObject.Properties.Name -contains 'projectedName') { $_.projectedName } else { $_.name }
        [pscustomobject]@{
            Name = $parameterName
            ApiName = $_.name
            Type = $_.schema
            Mandatory = [bool]$_.required
            Binding = $_.location
            NullPolicy = $_.nullPolicy
            DefaultValue = if ($_.PSObject.Properties.Name -contains 'defaultValue') { $_.defaultValue } else { $null }
            AppliesTo = @($op.operationId)
        }
    })
    $bindingName = if ($override.PSObject.Properties.Name -contains 'parameterSet') { $override.parameterSet } else { $op.operationSemantic.kind }
    [pscustomobject]@{
        CmdletName = "$($override.verb)-$($override.noun)"
        OperationId = $op.operationId
        Method = $op.method
        PathTemplate = $op.pathTemplate
        ParameterSet = $bindingName
        OperationSemantic = $op.operationSemantic
        PathParameters = @($parameters | Where-Object Binding -eq 'path' | ForEach-Object Name)
        QueryParameters = @($parameters | Where-Object Binding -eq 'query' | ForEach-Object Name)
        BodyModel = if ($null -ne $requestBody) { $requestBody.representations[0].schema } else { $null }
        OutputType = 'Cloudflare.PowerShell.CfDnsRecord'
        PipelineMode = if ($outputPolicy) { $outputPolicy } else { 'single' }
        PagingBehavior = $paging
        SupportsShouldProcess = [bool]$supportsShouldProcess
        ConfirmImpact = if ($confirmImpact) { $confirmImpact } else { 'None' }
        Parameters = $parameters
        CorrectedRequestBody = @($traceItems).Count -gt 0
        CorrectionTrace = $traceItems
    }
})

$cmdlets = @($projectedBindings | Group-Object CmdletName | Sort-Object Name | ForEach-Object {
    $bindings = @($_.Group | Sort-Object OperationId)
    $first = $bindings[0]
    $publicParameters = @($bindings.Parameters | Group-Object Name | Sort-Object Name | ForEach-Object {
        $variants = @($_.Group)
        [pscustomobject]@{
            Name = $_.Name
            Type = $variants[0].Type
            Binding = $variants[0].Binding
            AppliesTo = @($variants | ForEach-Object { $_.AppliesTo })
            RequiredIn = @($variants | Where-Object Mandatory | ForEach-Object { $_.AppliesTo })
            NullPolicy = $variants[0].NullPolicy
            DefaultValue = $variants[0].DefaultValue
        }
    })
    $parameterSets = @($bindings | ForEach-Object {
        [pscustomobject]@{
            Name = $_.ParameterSet
            OperationBinding = [pscustomobject]@{
                OperationId = $_.OperationId
                HttpMethod = $_.Method
                PathTemplate = $_.PathTemplate
                PathParameters = $_.PathParameters
                QueryParameters = $_.QueryParameters
                BodyModel = $_.BodyModel
            }
            RequiredParameters = @($_.Parameters | Where-Object Mandatory | ForEach-Object Name)
            OptionalParameters = @($_.Parameters | Where-Object { -not $_.Mandatory } | ForEach-Object Name)
        }
    })
    $pagingBinding = @($bindings | Where-Object { $null -ne (Get-JsonPropertyValue $_ 'PagingBehavior') } | Select-Object -First 1)
    $impact = ($bindings | Sort-Object { Get-ImpactRank $_.ConfirmImpact } -Descending | Select-Object -First 1).ConfirmImpact
    [pscustomobject]@{
        CmdletName = $_.Name
        OperationBindings = @($parameterSets.OperationBinding)
        ParameterSets = $parameterSets
        Parameters = $publicParameters
        OutputType = $first.OutputType
        PipelineMode = if (@($bindings | Where-Object PipelineMode -eq 'item').Count -gt 0) { 'item' } else { 'single' }
        PagingBehavior = if ($pagingBinding.Count -gt 0) { $pagingBinding[0].PagingBehavior } else { $null }
        SupportsShouldProcess = @($bindings | Where-Object SupportsShouldProcess).Count -gt 0
        ConfirmImpact = $impact
        OverrideTrace = @($bindings | ForEach-Object CorrectionTrace)
    }
})

New-Item -ItemType Directory -Force -Path $projectionRoot, $modelOutputRoot, $metadataOutputRoot | Out-Null
Write-Utf8CrLf (Join-Path $projectionRoot 'CmdletModel.json') ($cmdlets | ConvertTo-Json -Depth 100)

$usedSymbols = @{}
$operationConstants = ($operations | Sort-Object { $_.Operation.operationId } | ForEach-Object {
    $symbol = Get-OperationSymbol $_.Operation
    if ($usedSymbols.ContainsKey($symbol)) {
        $usedSymbols[$symbol]++
        $symbol = "${symbol}_$($usedSymbols[$symbol])"
    } else { $usedSymbols[$symbol] = 1 }
    "    public const string $symbol = `"$($_.Operation.operationId)`";"
}) -join [Environment]::NewLine

$models = @'
// <auto-generated />
#nullable enable
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace Cloudflare.PowerShell;

public readonly struct Optional<T>
{
    private readonly T? _value;
    private Optional(bool isSpecified, T? value) { IsSpecified = isSpecified; _value = value; }
    public bool IsSpecified { get; }
    public T? Value => _value;
    public static Optional<T> Omitted => new(false, default);
    public static Optional<T> From(T? value) => new(true, value);
}

public abstract class CfDnsRecordInput
{
    public Optional<string?> Name { get; set; }
    public Optional<int> Ttl { get; set; }
    public Optional<bool> Proxied { get; set; }
    public abstract string Type { get; }
    protected JsonObject BaseJson()
    {
        var json = new JsonObject();
        if (Name.IsSpecified) json["name"] = Name.Value;
        if (Ttl.IsSpecified) json["ttl"] = Ttl.Value;
        if (Proxied.IsSpecified) json["proxied"] = Proxied.Value;
        json["type"] = Type;
        return json;
    }
    public abstract JsonObject ToJson();
}

public sealed class CfARecordInput : CfDnsRecordInput
{
    public Optional<string?> Content { get; set; }
    public override string Type => "A";
    public override JsonObject ToJson() { var json = BaseJson(); if (Content.IsSpecified) json["content"] = Content.Value; return json; }
}

public sealed class CfMxRecordInput : CfDnsRecordInput
{
    public Optional<string?> Content { get; set; }
    public Optional<int> Priority { get; set; }
    public override string Type => "MX";
    public override JsonObject ToJson() { var json = BaseJson(); if (Content.IsSpecified) json["content"] = Content.Value; if (Priority.IsSpecified) json["priority"] = Priority.Value; return json; }
}

public abstract class CfDataRecordInput : CfDnsRecordInput
{
    public JsonObject? Data { get; set; }
    protected JsonObject DataJson() { var json = BaseJson(); if (Data is not null) json["data"] = Data.DeepClone(); return json; }
}

public sealed class CfCaaRecordInput : CfDataRecordInput
{
    public override string Type => "CAA";
    public override JsonObject ToJson() => DataJson();
}

public sealed class CfHttpsRecordInput : CfDataRecordInput
{
    public override string Type => "HTTPS";
    public override JsonObject ToJson() => DataJson();
}

public sealed class CfSvcbRecordInput : CfDataRecordInput
{
    public override string Type => "SVCB";
    public override JsonObject ToJson() => DataJson();
}

public sealed class CfDnsRecord
{
    [JsonPropertyName("id")] public string? Id { get; set; }
    [JsonPropertyName("name")] public string? Name { get; set; }
    [JsonPropertyName("type")] public string? Type { get; set; }
    [JsonPropertyName("content")] public string? Content { get; set; }
    [JsonPropertyName("ttl")] public int? Ttl { get; set; }
    [JsonPropertyName("proxied")] public bool? Proxied { get; set; }
    [JsonPropertyName("priority")] public int? Priority { get; set; }
    [JsonPropertyName("data")] public JsonObject? Data { get; set; }
    [JsonPropertyName("comment")] public string? Comment { get; set; }
    [JsonPropertyName("tags")] public List<string>? Tags { get; set; }
    [JsonPropertyName("created_on")] public DateTimeOffset? CreatedOn { get; set; }
    [JsonPropertyName("modified_on")] public DateTimeOffset? ModifiedOn { get; set; }
}
'@
Write-Utf8CrLf (Join-Path $modelOutputRoot 'CfDnsRecordModels.cs') $models

$operationsSource = @"
// <auto-generated />
#nullable enable
namespace Cloudflare.PowerShell;

public static class CfDnsRecordOperationMetadata
{
$operationConstants
}
"@
Write-Utf8CrLf (Join-Path $metadataOutputRoot 'CfDnsRecordOperationMetadata.cs') $operationsSource

foreach ($cmdlet in $cmdlets | Sort-Object CmdletName) {
    $className = "Projection_$(ConvertTo-CSharpIdentifier $cmdlet.CmdletName)"
    $bindingIds = @($cmdlet.OperationBindings | ForEach-Object OperationId) -join ';'
    $bindingMethods = @($cmdlet.OperationBindings | ForEach-Object HttpMethod) -join ';'
    $source = @"
// <auto-generated />
#nullable enable
namespace Cloudflare.PowerShell;

public static class $className
{
    public const string CmdletName = "$($cmdlet.CmdletName)";
    public const string OperationIds = "$bindingIds";
    public const string HttpMethods = "$bindingMethods";
    public const string OutputType = "$($cmdlet.OutputType)";
    public const string ConfirmImpact = "$($cmdlet.ConfirmImpact)";
    public const bool SupportsShouldProcess = $($cmdlet.SupportsShouldProcess.ToString().ToLowerInvariant());
}
"@
    Write-Utf8CrLf (Join-Path $metadataOutputRoot "$className.cs") $source
}

[pscustomobject]@{
    CorrectedOperations = @($operations | Where-Object { $null -ne (Get-JsonPropertyValue $_.Operation 'correctionTrace') }).Count
    Cmdlets = @($cmdlets.CmdletName)
    GeneratedFiles = @('Generated/Models/CfDnsRecordModels.cs', 'Generated/Metadata/CfDnsRecordOperationMetadata.cs')
    ProjectionFile = 'artifacts/projection/CmdletModel.json'
}
