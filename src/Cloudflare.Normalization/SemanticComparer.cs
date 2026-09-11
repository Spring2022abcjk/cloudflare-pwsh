namespace Cloudflare.Normalization;

public sealed record SemanticDifference(string Path, string Expected, string Actual);

public sealed class SemanticComparisonResult
{
    public List<SemanticDifference> Differences { get; } = [];
    public bool IsEquivalent => Differences.Count == 0;
}

public static class SemanticComparer
{
    public static SemanticComparisonResult Compare(NormalizedDocument expected, NormalizedDocument actual)
    {
        var result = new SemanticComparisonResult();
        var expectedOperations = expected.Operations.ToDictionary(x => x.OperationId, StringComparer.Ordinal);
        var actualOperations = actual.Operations.ToDictionary(x => x.OperationId, StringComparer.Ordinal);
        foreach (var id in expectedOperations.Keys.Union(actualOperations.Keys, StringComparer.Ordinal).OrderBy(x => x, StringComparer.Ordinal))
        {
            if (!expectedOperations.TryGetValue(id, out var expectedOperation)) { result.Differences.Add(new($"operations[{id}]", "present", "missing")); continue; }
            if (!actualOperations.TryGetValue(id, out var actualOperation)) { result.Differences.Add(new($"operations[{id}]", "missing", "present")); continue; }
            CompareOperation(expectedOperation, actualOperation, result);
        }
        CompareUnionStructures(expected, actual, result);
        return result;
    }

    private static void CompareOperation(NormalizedOperation expected, NormalizedOperation actual, SemanticComparisonResult result)
    {
        Equal($"{expected.OperationId}.method", expected.Method, actual.Method, result);
        Equal($"{expected.OperationId}.path", expected.PathTemplate, actual.PathTemplate, result);
        Equal($"{expected.OperationId}.semantic.kind", expected.OperationSemantic.Kind, actual.OperationSemantic.Kind, result);
        CompareScopes(expected, actual, result);
        var expectedParameters = expected.Parameters.Select(ParameterKey).OrderBy(x => x, StringComparer.Ordinal).ToArray();
        var actualParameters = actual.Parameters.Select(ParameterKey).OrderBy(x => x, StringComparer.Ordinal).ToArray();
        if (!expectedParameters.SequenceEqual(actualParameters, StringComparer.Ordinal)) Equal($"{expected.OperationId}.parameters", string.Join(';', expectedParameters), string.Join(';', actualParameters), result);
        CompareRequestBody(expected, actual, result);
        var expectedResponses = expected.Responses.Select(ResponseKey).OrderBy(x => x, StringComparer.Ordinal).ToArray();
        var actualResponses = actual.Responses.Select(ResponseKey).OrderBy(x => x, StringComparer.Ordinal).ToArray();
        if (!expectedResponses.SequenceEqual(actualResponses, StringComparer.Ordinal)) Equal($"{expected.OperationId}.responses", string.Join(';', expectedResponses), string.Join(';', actualResponses), result);
        var expectedPagination = expected.Pagination?.Strategy ?? "SinglePage";
        var actualPagination = actual.Pagination?.Strategy ?? "SinglePage";
        Equal($"{expected.OperationId}.pagination", expectedPagination, actualPagination, result);
        Equal($"{expected.OperationId}.effectiveBody", EffectiveBody(expected), EffectiveBody(actual), result);
    }

    private static void CompareScopes(NormalizedOperation expected, NormalizedOperation actual, SemanticComparisonResult result)
    {
        var left = expected.ScopeBindings.Select(x => $"{x.ParameterName}:{x.ScopeType}:{x.Role}").OrderBy(x => x, StringComparer.Ordinal);
        var right = actual.ScopeBindings.Select(x => $"{x.ParameterName}:{x.ScopeType}:{x.Role}").OrderBy(x => x, StringComparer.Ordinal);
        if (!left.SequenceEqual(right, StringComparer.Ordinal)) Equal($"{expected.OperationId}.scopeBindings", string.Join(';', left), string.Join(';', right), result);
    }

    private static void CompareRequestBody(NormalizedOperation expected, NormalizedOperation actual, SemanticComparisonResult result)
    {
        IEnumerable<string> left = expected.RequestBody is null ? Enumerable.Empty<string>() : expected.RequestBody.Representations.Select(x => x.ContentType).OrderBy(x => x, StringComparer.Ordinal);
        IEnumerable<string> right = actual.RequestBody is null ? Enumerable.Empty<string>() : actual.RequestBody.Representations.Select(x => x.ContentType).OrderBy(x => x, StringComparer.Ordinal);
        if (!left.SequenceEqual(right, StringComparer.Ordinal)) Equal($"{expected.OperationId}.request.contentTypes", string.Join(';', left), string.Join(';', right), result);
    }

    private static string ParameterKey(NormalizedParameter x) => $"{x.Name}:{x.Location}:{x.Required}:{x.AllowsNull}:{x.NullPolicy}:{JsonValue(x.DefaultValue)}";
    private static string ResponseKey(NormalizedResponseCase x) => $"{x.StatusSelector.Kind}:{x.StatusSelector.Value}:{string.Join(',', x.Representations.Select(r => $"{r.ContentType}:{r.EnvelopePolicy}:{r.ParsingMode}").OrderBy(x => x, StringComparer.Ordinal))}";
    private static string EffectiveBody(NormalizedOperation x) => x.RequestBody is null ? "absent" : x.RequestBody.EffectivePresence ?? (x.RequestBody.Required ? "required" : "optional");
    private static string JsonValue(System.Text.Json.Nodes.JsonNode? value) => value?.ToJsonString() ?? "<none>";
    private static void Equal(string path, string expected, string actual, SemanticComparisonResult result) { if (!string.Equals(expected, actual, StringComparison.Ordinal)) result.Differences.Add(new(path, expected, actual)); }

    private static void CompareUnionStructures(NormalizedDocument expected, NormalizedDocument actual, SemanticComparisonResult result)
    {
        foreach (var operation in expected.Operations)
        {
            var actualOperation = actual.Operations.FirstOrDefault(x => x.OperationId == operation.OperationId);
            if (actualOperation is null) continue;
            var expectedNames = SchemaNames(operation);
            var actualNames = SchemaNames(actualOperation);
            foreach (var pair in expectedNames.Zip(actualNames, (left, right) => (left, right)))
            {
                var left = UnionSignature(expected, pair.left, new HashSet<string>(StringComparer.Ordinal));
                var right = UnionSignature(actual, pair.right, new HashSet<string>(StringComparer.Ordinal));
                var expectedIsUnion = expected.Schemas.TryGetValue(pair.left, out var expectedSchema) && (expectedSchema.Discriminator is not null || expectedSchema.OneOf.Count > 0 || expectedSchema.AnyOf.Count > 0);
                if (expectedIsUnion && !left.SequenceEqual(right, StringComparer.Ordinal)) Equal($"{operation.OperationId}.schemaUnion", string.Join(',', left), string.Join(',', right), result);
            }
        }
    }

    private static IEnumerable<string> SchemaNames(NormalizedOperation operation)
    {
        if (operation.RequestBody is not null) foreach (var representation in operation.RequestBody.Representations) yield return representation.Schema;
        foreach (var representation in operation.Responses.SelectMany(x => x.Representations)) if (!string.IsNullOrEmpty(representation.Schema)) yield return representation.Schema;
    }

    private static string[] UnionSignature(NormalizedDocument document, string name, HashSet<string> visited)
    {
        if (string.IsNullOrEmpty(name) || !visited.Add(name) || !document.Schemas.TryGetValue(name, out var schema)) return [name];
        if (schema.Properties.TryGetValue("result", out var resultProperty) && !string.IsNullOrEmpty(resultProperty.Schema))
            return UnionSignature(document, resultProperty.Schema, new HashSet<string>(visited, StringComparer.Ordinal));
        if (schema.AllOf.Count > 0)
        {
            var composed = schema.AllOf.Select(x => UnionSignature(document, x, new HashSet<string>(visited, StringComparer.Ordinal))).OrderByDescending(x => x.Length).FirstOrDefault();
            if (composed is { Length: > 1 }) return composed;
        }
        if (schema.Discriminator?.Variants.Count > 0)
        {
            var values = new List<string>();
            foreach (var variant in schema.Discriminator.Variants)
            {
                if (!string.IsNullOrEmpty(variant.Value)) values.Add(variant.Value);
                else values.AddRange(UnionSignature(document, variant.Schema, new HashSet<string>(visited, StringComparer.Ordinal)));
            }
            return values.OrderBy(x => x, StringComparer.Ordinal).ToArray();
        }
        if (schema.OneOf.Count > 0 || schema.AnyOf.Count > 0)
        {
            return schema.OneOf.Concat(schema.AnyOf).SelectMany(x => UnionSignature(document, x, new HashSet<string>(visited, StringComparer.Ordinal))).OrderBy(x => x, StringComparer.Ordinal).ToArray();
        }
        if (schema.SingleValue is not null) return [schema.SingleValue.GetValue<string>()];
        return [name];
    }
}
