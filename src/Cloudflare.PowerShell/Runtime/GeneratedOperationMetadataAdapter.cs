namespace Cloudflare.PowerShell;

/// <summary>
/// Declarative operation metadata emitted by the normalized-model generator.
/// It contains transport facts only; it has no endpoint-specific behavior.
/// </summary>
public sealed class GeneratedOperationMetadata
{
    public string OperationId { get; init; } = string.Empty;
    public string Method { get; init; } = string.Empty;
    public string PathTemplate { get; init; } = string.Empty;
    public IReadOnlyList<GeneratedParameterMetadata> Parameters { get; init; } = [];
    public IReadOnlyList<GeneratedRequestRepresentationMetadata> RequestRepresentations { get; init; } = [];
    public IReadOnlyList<GeneratedResponseRepresentationMetadata> ResponseRepresentations { get; init; } = [];
    public GeneratedPaginationMetadata? Pagination { get; init; }
}

public sealed class GeneratedParameterMetadata
{
    public string Name { get; init; } = string.Empty;
    public string Location { get; init; } = "query";
    public bool Required { get; init; }
}

public sealed class GeneratedMultipartPartMetadata
{
    public string ParameterName { get; init; } = string.Empty;
    public string PartName { get; init; } = string.Empty;
    public string ContentType { get; init; } = "text/plain";
    public string Format { get; init; } = "string";
    public bool Required { get; init; }
}

public sealed class GeneratedRequestRepresentationMetadata
{
    public string ContentType { get; init; } = string.Empty;
    public string BodyParameterName { get; init; } = "body";
    public IReadOnlyList<GeneratedMultipartPartMetadata> Parts { get; init; } = [];
}

public sealed class GeneratedResponseRepresentationMetadata
{
    public int? StatusCode { get; init; }
    public string ContentType { get; init; } = string.Empty;
    public string EnvelopePolicy { get; init; } = "Raw";
    public string ParsingMode { get; init; } = "Json";
}

public sealed class GeneratedPaginationMetadata
{
    public string Strategy { get; init; } = "SinglePage";
    public IReadOnlyList<string> RequestFields { get; init; } = [];
    public IReadOnlyList<string> ResponseFields { get; init; } = [];
    public string? ResultPath { get; init; }
    public string? PageInfoPath { get; init; }
    public string? CurrentPagePath { get; init; }
    public string? TotalPagesPath { get; init; }
    public string? NextCursorPath { get; init; }
    public string? HasMorePath { get; init; }
    public string NextPageRule { get; init; } = string.Empty;
    public string StopRule { get; init; } = string.Empty;
}

/// <summary>
/// Adapts generated declarative metadata into the runtime contracts consumed
/// by <see cref="CloudflareRuntimeDispatcher"/>. OpenAPI types never cross this
/// boundary and no operation id is inspected here.
/// </summary>
public static class GeneratedOperationMetadataAdapter
{
    public static RuntimeOperationMetadata ToRuntime(GeneratedOperationMetadata metadata)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        if (string.IsNullOrWhiteSpace(metadata.OperationId)) throw new ArgumentException("Generated operation id is required.", nameof(metadata));
        if (string.IsNullOrWhiteSpace(metadata.Method)) throw new ArgumentException("Generated HTTP method is required.", nameof(metadata));
        if (string.IsNullOrWhiteSpace(metadata.PathTemplate)) throw new ArgumentException("Generated path template is required.", nameof(metadata));

        return new RuntimeOperationMetadata
        {
            OperationId = metadata.OperationId,
            Method = new HttpMethod(metadata.Method),
            PathTemplate = metadata.PathTemplate,
            Parameters = metadata.Parameters.Select(ToRuntime).ToArray(),
            RequestRepresentations = metadata.RequestRepresentations.Select(ToRuntime).ToArray(),
            ResponseRepresentations = metadata.ResponseRepresentations.Select(ToRuntime).ToArray()
        };
    }

    public static RuntimePaginationMetadata? ToRuntimePagination(GeneratedOperationMetadata metadata)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        return metadata.Pagination is null ? null : ToRuntime(metadata.Pagination);
    }

    public static RuntimePaginationMetadata ToRuntime(GeneratedPaginationMetadata metadata)
    {
        ArgumentNullException.ThrowIfNull(metadata);
        return new RuntimePaginationMetadata
        {
            Strategy = metadata.Strategy,
            RequestFields = metadata.RequestFields,
            ResponseFields = metadata.ResponseFields,
            ResultPath = metadata.ResultPath,
            PageInfoPath = metadata.PageInfoPath,
            CurrentPagePath = metadata.CurrentPagePath,
            TotalPagesPath = metadata.TotalPagesPath,
            NextCursorPath = metadata.NextCursorPath,
            HasMorePath = metadata.HasMorePath,
            NextPageRule = metadata.NextPageRule,
            StopRule = metadata.StopRule
        };
    }

    private static RuntimeParameterMetadata ToRuntime(GeneratedParameterMetadata metadata)
        => new() { Name = metadata.Name, Location = metadata.Location, Required = metadata.Required };

    private static RuntimeRequestRepresentation ToRuntime(GeneratedRequestRepresentationMetadata metadata)
        => new()
        {
            ContentType = metadata.ContentType,
            BodyParameterName = metadata.BodyParameterName,
            Parts = metadata.Parts.Select(part => new RuntimeMultipartPart
            {
                ParameterName = part.ParameterName,
                PartName = part.PartName,
                ContentType = part.ContentType,
                Format = part.Format,
                Required = part.Required
            }).ToArray()
        };

    private static RuntimeResponseRepresentation ToRuntime(GeneratedResponseRepresentationMetadata metadata)
        => new()
        {
            StatusCode = metadata.StatusCode,
            ContentType = metadata.ContentType,
            EnvelopePolicy = metadata.EnvelopePolicy,
            ParsingMode = metadata.ParsingMode
        };
}
