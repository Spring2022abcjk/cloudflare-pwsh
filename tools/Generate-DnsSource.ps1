[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$fixtureRoot = Join-Path $ProjectRoot 'fixtures/dns-records'
$outputRoot = Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated'
$projectionRoot = Join-Path $ProjectRoot 'artifacts/projection'
$cmdletOutputRoot = Join-Path $outputRoot 'Cmdlets'
$correctionPath = Join-Path $ProjectRoot 'overrides/api-corrections.yaml'
$projectionPath = Join-Path $ProjectRoot 'overrides/powershell-projection.yaml'

function Get-YamlValue {
    param([string]$Block, [string]$Name)
    $match = [regex]::Match($Block, "(?m)^\s+$([regex]::Escape($Name)):\s*(?<value>[^\r\n#]+)")
    if (-not $match.Success) { return $null }
    return $match.Groups['value'].Value.Trim()
}

function Get-OperationOverride {
    param([string]$Yaml, [string]$OperationId)
    $escaped = [regex]::Escape($OperationId)
    $match = [regex]::Match($Yaml, "(?ms)^  ${escaped}:\r?\n(?<body>.*?)(?=^  \S|^defaults:|\z)")
    $body = if ($match.Success) { $match.Groups['body'].Value } else { '' }
    [pscustomobject]@{
        Verb = Get-YamlValue $body 'verb'
        Noun = Get-YamlValue $body 'noun'
        OutputPolicy = Get-YamlValue $body 'outputPolicy'
        Paging = Get-YamlValue $body 'paging'
        ParameterSet = Get-YamlValue $body 'parameterSet'
        SupportsShouldProcess = (Get-YamlValue $body 'supportsShouldProcess') -eq 'true'
        ConfirmImpact = Get-YamlValue $body 'confirmImpact'
    }
}

function Apply-ApiCorrections {
    param([object]$Operation, [string]$Corrections)
    $corrected = $Operation | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    if ($corrected.operationId -eq 'dns-records-for-a-zone-delete-dns-record') {
        $corrected.requestBody | Add-Member -NotePropertyName effectivePresence -NotePropertyValue 'absent' -Force
        $corrected.requestBody | Add-Member -NotePropertyName observedCorrection -NotePropertyValue 'wrapper-does-not-send-body' -Force
    }
    return $corrected
}

$correctionText = Get-Content -Raw -LiteralPath $correctionPath
$projectionText = Get-Content -Raw -LiteralPath $projectionPath
$operations = @(Get-ChildItem -LiteralPath $fixtureRoot -Filter '*.json' -File |
    Where-Object { $_.Name -ne 'schemas.json' } |
    Sort-Object Name |
    ForEach-Object {
        $source = Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json
        $corrected = Apply-ApiCorrections $source $correctionText
        $override = Get-OperationOverride $projectionText $corrected.operationId
        [pscustomobject]@{
            Fixture = $_.Name
            Operation = $corrected
            Override = $override
            Corrected = $corrected.operationId -eq 'dns-records-for-a-zone-delete-dns-record'
        }
    })

if ($operations.Count -ne 6) { throw "Expected six DNS operation fixtures, found $($operations.Count)." }

$projectedBindings = @($operations | ForEach-Object {
    $op = $_.Operation
    $override = $_.Override
    $parameters = @($op.parameters | ForEach-Object {
        [pscustomobject]@{
            Name = $_.name
            Type = $_.schema
            Mandatory = [bool]$_.required
            Binding = $_.location
            NullPolicy = $_.nullPolicy
            DefaultValue = if ($_.PSObject.Properties.Name -contains 'defaultValue') { $_.defaultValue } else { $null }
        }
    })
    [pscustomobject]@{
        CmdletName = "$($override.Verb)-$($override.Noun)"
        OperationId = $op.operationId
        Method = $op.method
        PathTemplate = $op.pathTemplate
        ParameterSet = $override.ParameterSet
        OutputType = 'Cloudflare.PowerShell.CfDnsRecord'
        PipelineMode = if ($override.OutputPolicy) { $override.OutputPolicy } else { 'single' }
        PagingBehavior = $override.Paging
        SupportsShouldProcess = $override.SupportsShouldProcess
        ConfirmImpact = $override.ConfirmImpact
        Parameters = $parameters
        CorrectedRequestBody = $_.Corrected
    }
})

$cmdlets = @($projectedBindings | Group-Object CmdletName | Sort-Object Name | ForEach-Object {
    $bindings = @($_.Group | Sort-Object OperationId)
    $first = $bindings[0]
    $itemBindings = @($bindings | Where-Object { $_.PipelineMode -eq 'item' })
    $pagingBindings = @($bindings | Where-Object { $_.PagingBehavior })
    $shouldProcessBindings = @($bindings | Where-Object { $_.SupportsShouldProcess })
    $correctedBindings = @($bindings | Where-Object { $_.CorrectedRequestBody })
    $impactBinding = @($bindings | Sort-Object ConfirmImpact -Descending | Select-Object -First 1)
    [pscustomobject]@{
        CmdletName = $_.Name
        OperationId = if ($bindings.Count -eq 1) { $first.OperationId } else { $null }
        Method = if ($bindings.Count -eq 1) { $first.Method } else { 'MULTI' }
        PathTemplate = $first.PathTemplate
        ParameterSet = if ($bindings.Count -eq 1) { $first.ParameterSet } else { 'Replace,Edit' }
        OperationBindings = @($bindings | ForEach-Object {
            [pscustomobject]@{ OperationId = $_.OperationId; Method = $_.Method; PathTemplate = $_.PathTemplate; ParameterSet = $_.ParameterSet }
        })
        OutputType = $first.OutputType
        PipelineMode = if ($itemBindings.Count -gt 0) { 'item' } else { 'single' }
        PagingBehavior = if ($pagingBindings.Count -gt 0) { $pagingBindings[0].PagingBehavior } else { $null }
        SupportsShouldProcess = [bool]($shouldProcessBindings.Count -gt 0)
        ConfirmImpact = if ($impactBinding.Count -gt 0) { $impactBinding[0].ConfirmImpact } else { $null }
        Parameters = $first.Parameters
        CorrectedRequestBody = [bool]($correctedBindings.Count -gt 0)
    }
})

New-Item -ItemType Directory -Force -Path $projectionRoot, $outputRoot, $cmdletOutputRoot | Out-Null
$cmdlets | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $projectionRoot 'CmdletModel.json') -Encoding utf8NoBOM

$operationConstants = ($operations | ForEach-Object {
    $name = switch ($_.Operation.operationId) {
        'dns-records-for-a-zone-list-dns-records' { 'ListOperationId' }
        'dns-records-for-a-zone-create-dns-record' { 'CreateOperationId' }
        'dns-records-for-a-zone-dns-record-details' { 'GetOperationId' }
        'dns-records-for-a-zone-update-dns-record' { 'UpdateOperationId' }
        'dns-records-for-a-zone-patch-dns-record' { 'EditOperationId' }
        'dns-records-for-a-zone-delete-dns-record' { 'DeleteOperationId' }
        default { throw "Unknown operation $($_.Operation.operationId)" }
    }
    "    public const string $name = `"$($_.Operation.operationId)`";"
}) -join [Environment]::NewLine

$models = @'
// <auto-generated />
#nullable enable
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace Cloudflare.PowerShell;

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

public sealed class CfDnsRecordInput
{
    public string? Name { get; init; }
    public int? Ttl { get; init; }
    public string? Type { get; init; }
    public string? Content { get; init; }
    public int? Priority { get; init; }
    public bool? Proxied { get; init; }
    public JsonObject? Data { get; init; }

    public JsonObject ToJson()
    {
        var json = new JsonObject();
        if (Name is not null) json["name"] = Name;
        if (Ttl.HasValue) json["ttl"] = Ttl.Value;
        if (Type is not null) json["type"] = Type;
        if (Content is not null) json["content"] = Content;
        if (Priority.HasValue) json["priority"] = Priority.Value;
        if (Proxied.HasValue) json["proxied"] = Proxied.Value;
        if (Data is not null) json["data"] = Data.DeepClone();
        return json;
    }
}
'@

$operationsSource = @"
// <auto-generated />
namespace Cloudflare.PowerShell;

public static class CfDnsRecordOperations
{
$operationConstants
}
"@

$models | Set-Content -LiteralPath (Join-Path $outputRoot 'CfDnsRecordModels.cs') -Encoding utf8NoBOM
$operationsSource | Set-Content -LiteralPath (Join-Path $outputRoot 'CfDnsRecordOperations.cs') -Encoding utf8NoBOM

foreach ($cmdlet in $cmdlets | Sort-Object CmdletName) {
    $className = $cmdlet.CmdletName.Replace('-', '')
    $parameterSet = if ($cmdlet.ParameterSet) { $cmdlet.ParameterSet } else { '' }
    $operationIds = @($cmdlet.OperationBindings | ForEach-Object OperationId) -join ';'
    $methods = @($cmdlet.OperationBindings | ForEach-Object Method) -join ';'
    $cmdletSource = @"
// <auto-generated />
#nullable enable
namespace Cloudflare.PowerShell;

public static class $className
{
    public const string OperationId = "$operationIds";
    public const string HttpMethod = "$methods";
    public const string PathTemplate = "$($cmdlet.PathTemplate)";
    public const string OutputType = "$($cmdlet.OutputType)";
    public const string ParameterSet = "$parameterSet";
    public const bool SupportsShouldProcess = $($cmdlet.SupportsShouldProcess.ToString().ToLowerInvariant());
}
"@
    $cmdletSource | Set-Content -LiteralPath (Join-Path $cmdletOutputRoot "$($cmdlet.CmdletName).cs") -Encoding utf8NoBOM
}

[pscustomobject]@{
    CorrectedOperations = @($operations | Where-Object Corrected).Count
    Cmdlets = @($cmdlets.CmdletName)
    GeneratedFiles = @('Generated/CfDnsRecordModels.cs', 'Generated/CfDnsRecordOperations.cs') + @($cmdlets | ForEach-Object { "Generated/Cmdlets/$($_.CmdletName).cs" })
    ProjectionFile = 'artifacts/projection/CmdletModel.json'
}
