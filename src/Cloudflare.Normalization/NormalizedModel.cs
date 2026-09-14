using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace Cloudflare.Normalization;

public sealed class NormalizedDocument
{
    public int Version { get; set; } = 1;
    public string? SourcePath { get; set; }
    public string? SourceRevision { get; set; }
    public List<NormalizedOperation> Operations { get; set; } = [];
    public Dictionary<string, NormalizedSchema> Schemas { get; set; } = new(StringComparer.Ordinal);
}

public sealed class NormalizedOperation
{
    public string OperationId { get; set; } = string.Empty;
    public string Method { get; set; } = string.Empty;
    public string PathTemplate { get; set; } = string.Empty;
    public List<string> ResourcePath { get; set; } = [];
    public List<ScopeBinding> ScopeBindings { get; set; } = [];
    public OperationSemantic OperationSemantic { get; set; } = new();
    public List<NormalizedParameter> Parameters { get; set; } = [];
    public NormalizedRequestBody? RequestBody { get; set; }
    public List<NormalizedResponseCase> Responses { get; set; } = [];
    public PaginationModel? Pagination { get; set; }
    public string SourceLocation { get; set; } = string.Empty;
    public List<CorrectionTrace> CorrectionTrace { get; set; } = [];
}

public sealed class ScopeBinding
{
    public string ParameterName { get; set; } = string.Empty;
    public string ScopeType { get; set; } = string.Empty;
    public string Role { get; set; } = string.Empty;
}

public sealed class OperationSemantic
{
    public string Kind { get; set; } = "Unknown";
    public string Source { get; set; } = string.Empty;
    public string Confidence { get; set; } = string.Empty;
}

public sealed class NormalizedParameter
{
    public string Name { get; set; } = string.Empty;
    public string Location { get; set; } = string.Empty;
    public bool Required { get; set; }
    public bool AllowsNull { get; set; }
    public JsonNode? DefaultValue { get; set; }
    public string NullPolicy { get; set; } = "omit";
    public string Schema { get; set; } = string.Empty;
    public SerializationModel Serialization { get; set; } = new();
    public bool IsParentScopeId { get; set; }
    public bool IsPrimaryResourceId { get; set; }
    public string SourceRef { get; set; } = string.Empty;
}

public sealed class SerializationModel
{
    public string Style { get; set; } = "form";
    public bool Explode { get; set; }
    public bool AllowReserved { get; set; }
    public string ArrayNotation { get; set; } = "repeat";
    public string ObjectNotation { get; set; } = "dots";
    public string? CustomSerializerId { get; set; }
}

public sealed class NormalizedRequestBody
{
    public bool Required { get; set; }
    public bool DeclaredContract { get; set; }
    public string Presence { get; set; } = "absent";
    public string? EffectivePresence { get; set; }
    public string? ObservedCorrection { get; set; }
    public string Semantics { get; set; } = string.Empty;
    public string SourceRef { get; set; } = string.Empty;
    public List<RequestRepresentation> Representations { get; set; } = [];
}

public sealed class RequestRepresentation
{
    public string ContentType { get; set; } = string.Empty;
    public string Schema { get; set; } = string.Empty;
    public string SourceRef { get; set; } = string.Empty;
}

public sealed class NormalizedResponseCase
{
    public StatusSelector StatusSelector { get; set; } = new();
    public List<ResponseRepresentation> Representations { get; set; } = [];
}

public sealed class StatusSelector
{
    public string Kind { get; set; } = "Default";
    public string Value { get; set; } = "default";
}

public sealed class ResponseRepresentation
{
    public string ContentType { get; set; } = string.Empty;
    public string Schema { get; set; } = string.Empty;
    public string EnvelopePolicy { get; set; } = "Raw";
    public string ParsingMode { get; set; } = "Json";
    public string SourceRef { get; set; } = string.Empty;
}

public sealed class PaginationModel
{
    public string Strategy { get; set; } = "UnknownPagination";
    public List<string> RequestFields { get; set; } = [];
    public List<string> ResponseFields { get; set; } = [];
    public string NextPageRule { get; set; } = string.Empty;
    public string StopRule { get; set; } = string.Empty;
    public string Evidence { get; set; } = string.Empty;
}

public sealed class NormalizedSchema
{
    public string Name { get; set; } = string.Empty;
    public string Kind { get; set; } = "reference";
    public string? SourceRef { get; set; }
    public string? PrimitiveType { get; set; }
    public string? Items { get; set; }
    public string? Format { get; set; }
    public List<string> RequiredProperties { get; set; } = [];
    public Dictionary<string, NormalizedProperty> Properties { get; set; } = new(StringComparer.Ordinal);
    public List<string> OneOf { get; set; } = [];
    public List<string> AnyOf { get; set; } = [];
    public List<string> AllOf { get; set; } = [];
    public DiscriminatorModel? Discriminator { get; set; }
    public JsonNode? SingleValue { get; set; }
    public List<string> Enum { get; set; } = [];
}

public sealed class NormalizedProperty
{
    public string Name { get; set; } = string.Empty;
    public string Schema { get; set; } = string.Empty;
    public bool Required { get; set; }
    public bool AllowsNull { get; set; }
    public JsonNode? DefaultValue { get; set; }
    public string NullPolicy { get; set; } = "omit";
    public bool ReadOnly { get; set; }
    public bool WriteOnly { get; set; }
}

public sealed class DiscriminatorModel
{
    public string Property { get; set; } = string.Empty;
    public bool SingleValue { get; set; }
    public List<DiscriminatorVariant> Variants { get; set; } = [];
}

public sealed class DiscriminatorVariant
{
    public string Schema { get; set; } = string.Empty;
    public string Value { get; set; } = string.Empty;
}

public sealed class CorrectionTrace
{
    public string RuleId { get; set; } = string.Empty;
    public string Reason { get; set; } = string.Empty;
    public string Source { get; set; } = string.Empty;
    public string Match { get; set; } = string.Empty;
}

public static class NormalizedJson
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };
}
