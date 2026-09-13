[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Utf8CrLf {
    param([string]$Path, [string]$Content)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
    [IO.File]::WriteAllText($Path, $normalized, [Text.UTF8Encoding]::new($false))
}

function ConvertTo-CSharpString {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return 'null' }
    return ($Value.ToString() | ConvertTo-Json -Compress)
}

function Normalize-LineEndings {
    param([string]$Content)
    return $Content.Replace("`r`n", "`n").Replace("`r", "`n")
}

$cmdletModels = @(
    [ordered]@{
        cmdletName = 'Get-CfZone'
        className = 'GetCfZoneCommand'
        outputType = 'Cloudflare.PowerShell.CfZone'
        parameterSets = @('Get', 'List')
        parameterNames = @('ZoneId', 'AccountId', 'AccountName', 'Direction', 'Match', 'Name', 'Order', 'Page', 'PerPage', 'Status', 'Type')
        operationIds = @('zones-0-get', 'zones-get')
        supportsShouldProcess = $false
        confirmImpact = 'None'
        help = [ordered]@{ synopsis = 'Gets a Cloudflare zone.'; description = 'Gets zones visible to the authenticated account and writes one typed zone per pipeline object.'; source = 'Override' }
    },
    [ordered]@{
        cmdletName = 'Get-CfDnsRecord'
        className = 'GetCfDnsRecordCommand'
        outputType = 'Cloudflare.PowerShell.CfDnsRecord'
        parameterSets = @('Get', 'List')
        parameterNames = @('ZoneId', 'DnsRecordId', 'IncludeShadowMetadata', 'Comment', 'CommentAbsent', 'CommentContains', 'CommentEndswith', 'CommentExact', 'CommentPresent', 'CommentStartswith', 'Content', 'ContentContains', 'ContentEndswith', 'ContentExact', 'ContentStartswith', 'Direction', 'Match', 'Name', 'NameContains', 'NameEndswith', 'NameExact', 'NameStartswith', 'Order', 'Page', 'PerPage', 'Proxied', 'Search', 'ShadowedByName', 'ShadowingName', 'Tag', 'TagContains', 'TagEndswith', 'TagExact', 'TagMatch', 'TagPresent', 'TagStartswith', 'Type')
        operationIds = @('dns-records-for-a-zone-dns-record-details', 'dns-records-for-a-zone-list-dns-records')
        supportsShouldProcess = $false
        confirmImpact = 'None'
        help = [ordered]@{ synopsis = 'Gets Cloudflare DNS records.'; description = 'Gets one or more typed DNS records through the shared runtime.'; source = 'DeterministicDefault' }
    },
    [ordered]@{
        cmdletName = 'New-CfDnsRecord'
        className = 'NewCfDnsRecordCommand'
        outputType = 'Cloudflare.PowerShell.CfDnsRecord'
        parameterSets = @('Create')
        parameterNames = @('ZoneId', 'Record', 'IncludeShadowMetadata')
        operationIds = @('dns-records-for-a-zone-create-dns-record')
        supportsShouldProcess = $true
        confirmImpact = 'Medium'
        help = [ordered]@{ synopsis = 'Creates a Cloudflare DNS record.'; description = 'Creates a typed DNS record using the generated request model.'; source = 'DeterministicDefault' }
    },
    [ordered]@{
        cmdletName = 'Remove-CfDnsRecord'
        className = 'RemoveCfDnsRecordCommand'
        outputType = 'Cloudflare.PowerShell.CfDnsRecord'
        parameterSets = @('Delete')
        parameterNames = @('ZoneId', 'DnsRecordId')
        operationIds = @('dns-records-for-a-zone-delete-dns-record')
        supportsShouldProcess = $true
        confirmImpact = 'High'
        help = [ordered]@{ synopsis = 'Removes a Cloudflare DNS record.'; description = 'Removes one DNS record by zone and record identifier.'; source = 'DeterministicDefault' }
    },
    [ordered]@{
        cmdletName = 'Set-CfDnsRecord'
        className = 'SetCfDnsRecordCommand'
        outputType = 'Cloudflare.PowerShell.CfDnsRecord'
        parameterSets = @('Replace', 'Edit')
        parameterNames = @('ZoneId', 'DnsRecordId', 'Replace', 'Edit')
        operationIds = @('dns-records-for-a-zone-update-dns-record', 'dns-records-for-a-zone-patch-dns-record')
        supportsShouldProcess = $true
        confirmImpact = 'High'
        help = [ordered]@{ synopsis = 'Updates a Cloudflare DNS record.'; description = 'Replaces or edits one DNS record through the shared runtime.'; source = 'DeterministicDefault' }
    }
)

$requiredSourceClasses = @('GetCfZoneCommand', 'GetCfDnsRecordCommand', 'NewCfDnsRecordCommand', 'RemoveCfDnsRecordCommand', 'SetCfDnsRecordCommand')
$cmdletTemplatePath = Join-Path $ProjectRoot 'tools/templates/P32RepresentativeCmdlets.cs.tmpl'
$cmdletSourcePath = Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Cmdlets/P32RepresentativeCmdlets.cs'
$cmdletTemplate = Get-Content -Raw -LiteralPath $cmdletTemplatePath -Encoding UTF8
Write-Utf8CrLf $cmdletSourcePath $cmdletTemplate
$cmdletSource = Get-Content -Raw -LiteralPath $cmdletSourcePath -Encoding UTF8
$baseSource = Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Runtime/CloudflareCmdletBase.cs') -Encoding UTF8
foreach ($className in $requiredSourceClasses) {
    if ($cmdletSource -notmatch "public sealed class $className\s*:") { throw "Generated P3.2 source is missing '$className'." }
}
if ((Normalize-LineEndings $cmdletSource) -ne (Normalize-LineEndings $cmdletTemplate)) { throw 'Generated P3.2 cmdlet source differs from its checked-in template.' }
if (($cmdletSource + $baseSource) -notmatch 'GeneratedOperationMetadataAdapter') { throw 'Generated P3.2 source is not connected to the metadata adapter.' }
foreach ($forbiddenPattern in @(
        'new\s+HttpRequestMessage',
        '\bHttpClient\b',
        '\bJsonSerializer\b',
        '\bQuerySerializer\b',
        '\bTask\.Delay\b',
        '\bGetAsyncEnumerator\b',
        '\bMoveNextAsync\b',
        '\bCloudflareApiException\b',
        '\bThrowCloudflareError\b')) {
    if ($cmdletSource -match $forbiddenPattern) { throw "Generated P3.2 source contains forbidden runtime logic: $forbiddenPattern" }
}
if ($cmdletSource -notmatch 'Cf(?:Zone|DnsRecord)RuntimeMetadata\.Get') { throw 'Generated P3.2 source is missing generated runtime metadata dispatch.' }
Write-Output 'PASS P3.2 generator/template and generated-source boundary checks'

$artifact = [ordered]@{
    version = 1
    stage = 'P3.2'
    source = 'corrected projection model and generated runtime metadata'
    cmdlets = $cmdletModels
    commonInfrastructureParameters = @('BaseUrl', 'Token', 'Handler')
}
$artifactPath = Join-Path $ProjectRoot 'artifacts/p3.2/CmdletModel.json'
Write-Utf8CrLf $artifactPath ($artifact | ConvertTo-Json -Depth 30)

$zoneModel = @'
// <auto-generated />
#nullable enable
using System.Text.Json.Serialization;

namespace Cloudflare.PowerShell;

public sealed class CfZone
{
    [JsonPropertyName("id")] public string? Id { get; set; }
    [JsonPropertyName("name")] public string? Name { get; set; }
    [JsonPropertyName("status")] public string? Status { get; set; }
    [JsonPropertyName("type")] public string? Type { get; set; }
}
'@
Write-Utf8CrLf (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Models/CfZoneModels.cs') $zoneModel

$zoneOperationIds = @{
    'zones-0-get' = 'Operation_zones_Get_zones_0_get'
    'zones-get' = 'Operation_zones_List_zones_get'
}
$zoneOperations = @'
// <auto-generated />
#nullable enable
namespace Cloudflare.PowerShell;

public static class CfZoneOperationMetadata
{
    public const string Operation_zones_Get_zones_0_get = "zones-0-get";
    public const string Operation_zones_List_zones_get = "zones-get";
}
'@
Write-Utf8CrLf (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Metadata/CfZoneOperationMetadata.cs') $zoneOperations

$zoneRuntime = @'
// <auto-generated />
#nullable enable
namespace Cloudflare.PowerShell;

public static class CfZoneRuntimeMetadata
{
    public static IReadOnlyList<GeneratedOperationMetadata> Operations { get; } =
    [
        new GeneratedOperationMetadata
        {
            OperationId = "zones-0-get",
            Method = "GET",
            PathTemplate = "/zones/{zone_id}",
            Parameters = [new GeneratedParameterMetadata { Name = "zone_id", Location = "path", Required = true }],
            RequestRepresentations = [],
            ResponseRepresentations =
            [
                new GeneratedResponseRepresentationMetadata { StatusCode = 200, ContentType = "application/json", EnvelopePolicy = "CloudflareResult", ParsingMode = "Json" },
                new GeneratedResponseRepresentationMetadata { StatusCode = null, ContentType = "application/json", EnvelopePolicy = "ErrorEnvelope", ParsingMode = "Json" }
            ],
            Pagination = new GeneratedPaginationMetadata { Strategy = "SinglePage", RequestFields = [], ResponseFields = [], StopRule = "single response" }
        },
        new GeneratedOperationMetadata
        {
            OperationId = "zones-get",
            Method = "GET",
            PathTemplate = "/zones",
            Parameters =
            [
                new GeneratedParameterMetadata { Name = "account.id", Location = "query", Required = false },
                new GeneratedParameterMetadata { Name = "account.name", Location = "query", Required = false },
                new GeneratedParameterMetadata { Name = "direction", Location = "query", Required = false },
                new GeneratedParameterMetadata { Name = "match", Location = "query", Required = false },
                new GeneratedParameterMetadata { Name = "name", Location = "query", Required = false },
                new GeneratedParameterMetadata { Name = "order", Location = "query", Required = false },
                new GeneratedParameterMetadata { Name = "page", Location = "query", Required = false },
                new GeneratedParameterMetadata { Name = "per_page", Location = "query", Required = false },
                new GeneratedParameterMetadata { Name = "status", Location = "query", Required = false },
                new GeneratedParameterMetadata { Name = "type", Location = "query", Required = false }
            ],
            RequestRepresentations = [],
            ResponseRepresentations =
            [
                new GeneratedResponseRepresentationMetadata { StatusCode = 200, ContentType = "application/json", EnvelopePolicy = "CloudflareResult", ParsingMode = "Json" },
                new GeneratedResponseRepresentationMetadata { StatusCode = null, ContentType = "application/json", EnvelopePolicy = "ErrorEnvelope", ParsingMode = "Json" }
            ],
            Pagination = new GeneratedPaginationMetadata
            {
                Strategy = "V4PagePaginationArray",
                RequestFields = ["page", "per_page"],
                ResponseFields = ["result", "result_info"],
                ResultPath = "result",
                PageInfoPath = "result_info",
                CurrentPagePath = "result_info.page",
                TotalPagesPath = "result_info.total_pages",
                NextPageRule = "page + 1",
                StopRule = "empty result page"
            }
        }
    ];

    public static GeneratedOperationMetadata Get(string operationId)
        => Operations.Single(x => x.OperationId.Equals(operationId, StringComparison.Ordinal));
}
'@
Write-Utf8CrLf (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Metadata/CfZoneRuntimeMetadata.cs') $zoneRuntime

$helpSource = @'
// <auto-generated />
#nullable enable
namespace Cloudflare.PowerShell;

public sealed record GeneratedHelpModel(string Synopsis, string Description, string Source);

public static class P32CmdletHelpMetadata
{
    public static IReadOnlyDictionary<string, GeneratedHelpModel> Commands { get; } =
        new Dictionary<string, GeneratedHelpModel>(StringComparer.Ordinal)
        {
            ["Get-CfZone"] = new("Gets a Cloudflare zone.", "Gets zones visible to the authenticated account and writes one typed zone per pipeline object.", "Override"),
            ["Get-CfDnsRecord"] = new("Gets Cloudflare DNS records.", "Gets one or more typed DNS records through the shared runtime.", "DeterministicDefault"),
            ["New-CfDnsRecord"] = new("Creates a Cloudflare DNS record.", "Creates a typed DNS record using the generated request model.", "DeterministicDefault"),
            ["Remove-CfDnsRecord"] = new("Removes a Cloudflare DNS record.", "Removes one DNS record by zone and record identifier.", "DeterministicDefault"),
            ["Set-CfDnsRecord"] = new("Updates a Cloudflare DNS record.", "Replaces or edits one DNS record through the shared runtime.", "DeterministicDefault")
        };
}
'@
Write-Utf8CrLf (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Metadata/P32CmdletHelpMetadata.cs') $helpSource

[pscustomobject]@{
    Stage = 'P3.2'
    Cmdlets = @($cmdletModels.cmdletName)
    ProjectionArtifact = 'artifacts/p3.2/CmdletModel.json'
    GeneratedSource = 'src/Cloudflare.PowerShell/Generated/Cmdlets/P32RepresentativeCmdlets.cs'
    RuntimeMetadata = @('CfZoneRuntimeMetadata', 'CfDnsRecordRuntimeMetadata')
} | ConvertTo-Json -Depth 10
