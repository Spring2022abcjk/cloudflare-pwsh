using System.Text.Json;
using System.Text.Json.Serialization;

namespace Cloudflare.Normalization.Compatibility;

public enum ApiChangeKind
{
    OperationAdded,
    OperationRemoved,
    HttpMethodChanged,
    PathChanged,
    ResourcePathChanged,
    SemanticKindChanged,
    ScopeBindingAdded,
    ScopeBindingRemoved,
    ScopeBindingRoleChanged,
    PrimaryResourceIdChanged,
    PaginationAdded,
    PaginationRemoved,
    PaginationStrategyChanged,
    RequestPagingFieldChanged,
    ResponsePagingFieldChanged,
    StopRuleChanged,
    NextPageRuleChanged,
    RequestBodyRequiredChanged,
    RequestBodyPresenceChanged,
    RequestContentTypeAdded,
    RequestContentTypeRemoved,
    RequestSchemaChanged,
    ParameterAdded,
    ParameterRemoved,
    ParameterBecameRequired,
    ParameterBecameOptional,
    ParameterTypeChanged,
    ParameterLocationChanged,
    ParameterSerializationChanged,
    ParameterNullabilityChanged,
    DefaultChanged,
    PropertyAdded,
    PropertyRemoved,
    PropertyBecameRequired,
    PropertyBecameOptional,
    PropertyTypeChanged,
    NullableChanged,
    ReadOnlyChanged,
    WriteOnlyChanged,
    EnumValueAdded,
    EnumValueRemoved,
    UnionVariantAdded,
    UnionVariantRemoved,
    DiscriminatorAdded,
    DiscriminatorRemoved,
    DiscriminatorPropertyChanged,
    DiscriminatorValueChanged,
    SuccessStatusAdded,
    SuccessStatusRemoved,
    ResponseContentTypeAdded,
    ResponseContentTypeRemoved,
    EnvelopePolicyChanged,
    ParsingModeChanged,
    ResultSchemaChanged,
    ErrorResponseChanged,
    SchemaTypeChanged,
    SchemaAdded,
    SchemaRemoved,
    SchemaCompositionChanged,
    CmdletAdded,
    CmdletRemoved,
    PowerShellParameterAdded,
    PowerShellParameterRemoved,
    PowerShellParameterBecameMandatory,
    PowerShellParameterSetChanged,
    PipelineBindingChanged,
    OutputTypeChanged,
    ShouldProcessChanged,
    ConfirmImpactChanged,
    PagingBehaviorChanged,
    PowerShellNameCollision
}

public enum CompatibilityImpact
{
    None,
    NonBreaking,
    Behavioral,
    PotentiallyBreaking,
    Breaking,
    Unknown
}

public sealed class ApiChange
{
    public ApiChangeKind Kind { get; init; }
    public string ResourcePath { get; init; } = string.Empty;
    public string? OperationId { get; init; }
    public string? SchemaName { get; init; }
    public string Path { get; init; } = string.Empty;
    public string OldValue { get; init; } = string.Empty;
    public string NewValue { get; init; } = string.Empty;
    public string Evidence { get; init; } = string.Empty;
    public CompatibilityImpact ApiImpact { get; init; }
    public CompatibilityImpact SdkImpact { get; init; }
    public CompatibilityImpact PowerShellImpact { get; init; }
}

public sealed class CompatibilityReport
{
    public string Stage { get; init; } = "P2.4";
    public string OldSourceRevision { get; init; } = string.Empty;
    public string NewSourceRevision { get; init; } = string.Empty;
    public List<ApiChange> Changes { get; init; } = [];
    public Dictionary<string, int> SeveritySummary { get; init; } = new(StringComparer.Ordinal);
    public bool FullyCompatible => Changes.Count == 0 && !Changes.Any(x => x.ApiImpact == CompatibilityImpact.Unknown || x.SdkImpact == CompatibilityImpact.Unknown || x.PowerShellImpact == CompatibilityImpact.Unknown);

    public static CompatibilityReport Create(string stage, string oldSourceRevision, string newSourceRevision, IEnumerable<ApiChange> changes)
    {
        var ordered = changes.OrderBy(x => x.ResourcePath, StringComparer.Ordinal)
            .ThenBy(x => x.OperationId, StringComparer.Ordinal)
            .ThenBy(x => x.SchemaName, StringComparer.Ordinal)
            .ThenBy(x => x.Path, StringComparer.Ordinal)
            .ThenBy(x => x.Kind)
            .ThenBy(x => x.OldValue, StringComparer.Ordinal)
            .ThenBy(x => x.NewValue, StringComparer.Ordinal)
            .ToList();
        var summary = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var dimension in new[] { "Api", "Sdk", "PowerShell" })
        {
            foreach (var impact in Enum.GetValues<CompatibilityImpact>())
            {
                summary[$"{dimension}:{impact}"] = dimension switch
                {
                    "Api" => ordered.Count(x => x.ApiImpact == impact),
                    "Sdk" => ordered.Count(x => x.SdkImpact == impact),
                    _ => ordered.Count(x => x.PowerShellImpact == impact)
                };
            }
        }
        summary["Changes"] = ordered.Count;
        return new CompatibilityReport
        {
            Stage = stage,
            OldSourceRevision = oldSourceRevision,
            NewSourceRevision = newSourceRevision,
            Changes = ordered,
            SeveritySummary = summary
        };
    }
}

public static class CompatibilityJson
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new JsonStringEnumConverter() }
    };
}
