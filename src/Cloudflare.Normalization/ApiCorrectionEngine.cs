using System.Text.Json.Nodes;

namespace Cloudflare.Normalization;

public sealed class ApiCorrectionEngine
{
    private readonly JsonObject _document;

    public ApiCorrectionEngine(JsonObject document) => _document = document;

    public ApiCorrectionEngine(string path) : this(JsonNode.Parse(File.ReadAllText(path))?.AsObject() ?? throw new InvalidDataException("Correction document must be an object.")) { }

    public NormalizedDocument Apply(NormalizedDocument source)
    {
        foreach (var operation in source.Operations)
        {
            var index = 0;
            foreach (var rule in _document["rules"]?.AsArray().OfType<JsonObject>().OrderBy(x => RuleSortKey(x), StringComparer.Ordinal) ?? Enumerable.Empty<JsonObject>())
            {
                if (!Matches(operation, rule["match"]?.AsObject())) { index++; continue; }
                ApplyActions(operation, rule["actions"]?.AsObject());
                operation.CorrectionTrace.Add(new CorrectionTrace
                {
                    RuleId = $"rule-{index}",
                    Reason = rule["reason"]?.GetValue<string>() ?? string.Empty,
                    Source = rule["source"]?.GetValue<string>() ?? string.Empty,
                    Match = rule["match"]?.ToJsonString() ?? "{}"
                });
                index++;
            }
        }
        return source;
    }

    private static bool Matches(NormalizedOperation operation, JsonObject? match)
    {
        if (match is null) return false;
        if (match["operationId"] is JsonValue operationId && operation.OperationId != operationId.GetValue<string>()) return false;
        if (match["method"] is JsonValue method && !operation.Method.Equals(method.GetValue<string>(), StringComparison.OrdinalIgnoreCase)) return false;
        if (match["path"] is JsonValue path && operation.PathTemplate != path.GetValue<string>()) return false;
        if (match["resourcePath"] is JsonArray resource && !operation.ResourcePath.SequenceEqual(resource.Select(x => x?.GetValue<string>() ?? string.Empty), StringComparer.Ordinal)) return false;
        if (match["schemaName"] is JsonValue schema)
        {
            var name = schema.GetValue<string>();
            var found = operation.Parameters.Any(x => x.Schema == name)
                || operation.RequestBody?.Representations.Any(x => x.Schema == name) == true
                || operation.Responses.SelectMany(x => x.Representations).Any(x => x.Schema == name);
            if (!found) return false;
        }
        return true;
    }

    private static void ApplyActions(NormalizedOperation operation, JsonObject? actions)
    {
        if (actions is null) return;
        if (actions["requestBody"] is JsonObject requestBody)
        {
            operation.RequestBody ??= new NormalizedRequestBody();
            operation.RequestBody.DeclaredContract = requestBody["declaredContract"]?.GetValue<bool>() ?? operation.RequestBody.DeclaredContract;
            operation.RequestBody.EffectivePresence = requestBody["effectivePresence"]?.GetValue<string>() ?? operation.RequestBody.EffectivePresence;
            operation.RequestBody.ObservedCorrection = requestBody["observedCorrection"]?.GetValue<string>() ?? operation.RequestBody.ObservedCorrection;
            if (operation.RequestBody.EffectivePresence == "absent") operation.RequestBody.Presence = "declared-but-observed-absent";
        }
        if (actions["parameters"] is JsonArray parameters)
            foreach (var parameterNode in parameters.OfType<JsonObject>())
            {
                var target = operation.Parameters.FirstOrDefault(x => (parameterNode["name"] is null || x.Name == parameterNode["name"]!.GetValue<string>()) && (parameterNode["location"] is null || x.Location == parameterNode["location"]!.GetValue<string>()));
                if (target is null || parameterNode["set"] is not JsonObject set) continue;
                if (set["name"] is JsonValue name) target.Name = name.GetValue<string>();
                if (set["required"] is JsonValue required) target.Required = required.GetValue<bool>();
                if (set["allowsNull"] is JsonValue nullable) target.AllowsNull = nullable.GetValue<bool>();
                if (set["nullPolicy"] is JsonValue nullPolicy) target.NullPolicy = nullPolicy.GetValue<string>();
            }
        if (actions["responses"] is JsonArray responses)
            foreach (var responseNode in responses.OfType<JsonObject>())
            {
                var status = responseNode["status"]?.GetValue<string>();
                var contentType = responseNode["contentType"]?.GetValue<string>();
                var set = responseNode["set"]?.AsObject();
                foreach (var response in operation.Responses.Where(x => status is null || x.StatusSelector.Value == status))
                    foreach (var representation in response.Representations.Where(x => contentType is null || x.ContentType == contentType))
                    {
                        if (set?["schema"] is JsonValue schema) representation.Schema = schema.GetValue<string>();
                        if (set?["envelopePolicy"] is JsonValue envelope) representation.EnvelopePolicy = envelope.GetValue<string>();
                        if (set?["parsingMode"] is JsonValue parsing) representation.ParsingMode = parsing.GetValue<string>();
                    }
            }
        if (actions["pagination"] is JsonObject pagination)
        {
            operation.Pagination ??= new PaginationModel();
            operation.Pagination.Strategy = pagination["strategy"]?.GetValue<string>() ?? operation.Pagination.Strategy;
            operation.Pagination.NextPageRule = pagination["nextPageRule"]?.GetValue<string>() ?? operation.Pagination.NextPageRule;
            operation.Pagination.StopRule = pagination["stopRule"]?.GetValue<string>() ?? operation.Pagination.StopRule;
            operation.Pagination.Evidence = pagination["evidence"]?.GetValue<string>() ?? operation.Pagination.Evidence;
        }
        if (actions["semantic"] is JsonObject semantic)
        {
            operation.OperationSemantic.Kind = semantic["kind"]?.GetValue<string>() ?? operation.OperationSemantic.Kind;
            operation.OperationSemantic.Source = semantic["source"]?.GetValue<string>() ?? operation.OperationSemantic.Source;
            operation.OperationSemantic.Confidence = semantic["confidence"]?.GetValue<string>() ?? operation.OperationSemantic.Confidence;
        }
    }

    private static string RuleSortKey(JsonObject rule) => string.Join('|', rule["match"]?.AsObject()?.OrderBy(x => x.Key, StringComparer.Ordinal).Select(x => x.Value?.ToJsonString()) ?? []);
}
