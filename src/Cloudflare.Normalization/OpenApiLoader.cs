using System.Text.Json.Nodes;

namespace Cloudflare.Normalization;

public sealed class OpenApiDocument
{
    public required string SourcePath { get; init; }
    public required JsonObject Root { get; init; }
    public string? SourceRevision { get; init; }
}

public static class OpenApiLoader
{
    public static OpenApiDocument Load(string path)
    {
        var text = File.ReadAllText(path);
        var root = JsonNode.Parse(text)?.AsObject() ?? throw new InvalidDataException("OpenAPI root must be a JSON object.");
        var revision = root["info"]?["version"]?.GetValue<string>();
        return new OpenApiDocument { SourcePath = Path.GetFileName(path), Root = root, SourceRevision = revision };
    }
}

public sealed class RefResolver
{
    private readonly JsonObject _root;
    public RefResolver(JsonObject root) => _root = root;

    public JsonNode Resolve(string reference, ISet<string>? activeReferences = null)
    {
        if (!reference.StartsWith("#/", StringComparison.Ordinal))
            throw new InvalidDataException($"Only local OpenAPI refs are supported: {reference}");
        reference = reference.TrimEnd('/');
        activeReferences ??= new HashSet<string>(StringComparer.Ordinal);
        if (!activeReferences.Add(reference)) throw new InvalidDataException($"Circular OpenAPI reference: {reference}");
        try
        {
            JsonNode current = _root;
            foreach (var segment in reference[2..].Split('/'))
            {
                var key = segment.Replace("~1", "/", StringComparison.Ordinal).Replace("~0", "~", StringComparison.Ordinal);
                current = current[key] ?? throw new InvalidDataException($"Missing OpenAPI ref segment '{key}' in {reference}");
            }
            return current;
        }
        finally { activeReferences.Remove(reference); }
    }

    public JsonNode ResolveFully(string reference)
    {
        reference = reference.TrimEnd('/');
        var seen = new HashSet<string>(StringComparer.Ordinal) { reference };
        var current = Resolve(reference);
        while (current is JsonObject obj && obj["$ref"] is JsonValue next)
        {
            var nextReference = next.GetValue<string>().TrimEnd('/');
            if (!seen.Add(nextReference)) throw new InvalidDataException($"Circular OpenAPI reference: {nextReference}");
            current = Resolve(nextReference);
        }
        return current;
    }

    public JsonObject ResolveObject(JsonNode? node, out string sourceRef)
    {
        sourceRef = string.Empty;
        if (node is JsonObject obj && obj["$ref"] is JsonValue referenceValue)
        {
            sourceRef = referenceValue.GetValue<string>();
            return ResolveFully(sourceRef).AsObject();
        }
        return node?.AsObject() ?? new JsonObject();
    }
}
