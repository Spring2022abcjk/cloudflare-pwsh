using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;

namespace Cloudflare.Normalization;

public sealed class OpenApiNormalizer
{
    private readonly OpenApiDocument _document;
    private readonly RefResolver _resolver;
    private readonly Dictionary<string, NormalizedSchema> _schemas = new(StringComparer.Ordinal);

    public OpenApiNormalizer(OpenApiDocument document)
    {
        _document = document;
        _resolver = new RefResolver(document.Root);
    }

    public NormalizedDocument NormalizeOperations(ISet<string>? operationIds = null)
    {
        var result = new NormalizedDocument
        {
            SourcePath = _document.SourcePath,
            SourceRevision = _document.SourceRevision
        };
        var paths = _document.Root["paths"]?.AsObject() ?? throw new InvalidDataException("OpenAPI document has no paths object.");
        foreach (var pathEntry in paths.OrderBy(x => x.Key, StringComparer.Ordinal))
        {
            if (pathEntry.Value is not JsonObject pathItem) continue;
            var inheritedParameters = ReadParameters(pathItem["parameters"], $"#/paths/{Escape(pathEntry.Key)}/parameters");
            foreach (var methodEntry in pathItem.Where(x => IsHttpMethod(x.Key)).OrderBy(x => x.Key, StringComparer.Ordinal))
            {
                if (methodEntry.Value is not JsonObject operation) continue;
                var operationId = StringValue(operation["operationId"]) ?? $"{methodEntry.Key}:{pathEntry.Key}";
                if (operationIds is not null && !operationIds.Contains(operationId)) continue;
                result.Operations.Add(NormalizeOperation(pathEntry.Key, methodEntry.Key, operation, inheritedParameters, operationId));
            }
        }
        result.Operations = result.Operations.OrderBy(x => x.OperationId, StringComparer.Ordinal).ToList();
        result.Schemas = new Dictionary<string, NormalizedSchema>(_schemas, StringComparer.Ordinal);
        return result;
    }

    private NormalizedOperation NormalizeOperation(string path, string method, JsonObject operation, List<NormalizedParameter> inheritedParameters, string operationId)
    {
        var op = new NormalizedOperation
        {
            OperationId = operationId,
            Method = method.ToUpperInvariant(),
            PathTemplate = path,
            ResourcePath = GetResourcePath(path),
            OperationSemantic = InferSemantic(operationId, method, path),
            SourceLocation = $"#/paths/{Escape(path)}/{method}"
        };
        var parameters = new Dictionary<(string Name, string Location), NormalizedParameter>();
        foreach (var parameter in inheritedParameters) parameters[(parameter.Name, parameter.Location)] = parameter;
        foreach (var parameter in ReadParameters(operation["parameters"], $"{op.SourceLocation}/parameters")) parameters[(parameter.Name, parameter.Location)] = parameter;
        op.Parameters = parameters.Values.OrderBy(x => x.Location, StringComparer.Ordinal).ThenBy(x => x.Name, StringComparer.Ordinal).ToList();
        op.ScopeBindings = InferScopeBindings(path, op.Parameters);
        op.RequestBody = NormalizeRequestBody(operation["requestBody"], op.SourceLocation, operationId);
        op.Responses = NormalizeResponses(operation["responses"], op.SourceLocation, operationId);
        op.Pagination = DetectPagination(op, operationId);
        return op;
    }

    private List<NormalizedParameter> ReadParameters(JsonNode? node, string location)
    {
        var result = new List<NormalizedParameter>();
        if (node is not JsonArray array) return result;
        foreach (var raw in array)
        {
            if (raw is null) continue;
            var parameter = raw;
            var sourceRef = string.Empty;
            var obj = _resolver.ResolveObject(parameter, out sourceRef);
            var name = StringValue(obj["name"]) ?? string.Empty;
            var inValue = StringValue(obj["in"]) ?? string.Empty;
            if (string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(inValue)) continue;
            var schemaNode = obj["schema"];
            var schemaName = GetSchemaReferenceName(schemaNode, $"{location}/{name}/schema");
            var schemaObject = ResolveSchemaObject(schemaNode);
            var allowsNull = AllowsNull(schemaObject);
            var defaultValue = schemaObject["default"]?.DeepClone();
            result.Add(new NormalizedParameter
            {
                Name = name,
                Location = inValue,
                Required = BoolValue(obj["required"]) || inValue == "path",
                AllowsNull = allowsNull,
                DefaultValue = defaultValue,
                NullPolicy = allowsNull ? "send-null" : inValue == "path" && (BoolValue(obj["required"]) || inValue == "path") ? "reject-null" : "omit",
                Schema = schemaName,
                Serialization = ReadSerialization(obj["style"], obj["explode"], schemaObject),
                IsParentScopeId = name is "zone_id" or "account_id",
                IsPrimaryResourceId = name.EndsWith("_id", StringComparison.Ordinal) && name is not "zone_id" and not "account_id",
                SourceRef = string.IsNullOrEmpty(sourceRef) ? location : sourceRef
            });
        }
        return result;
    }

    private NormalizedRequestBody? NormalizeRequestBody(JsonNode? node, string location, string operationId)
    {
        if (node is null) return null;
        var sourceRef = string.Empty;
        var body = _resolver.ResolveObject(node, out sourceRef);
        var result = new NormalizedRequestBody
        {
            Required = BoolValue(body["required"]),
            DeclaredContract = true,
            Presence = BoolValue(body["required"]) ? "required" : "declared-but-observed-absent",
            SourceRef = sourceRef
        };
        if (body["content"] is JsonObject content)
        {
            foreach (var entry in content.OrderBy(x => x.Key, StringComparer.Ordinal))
            {
                var media = entry.Value?.AsObject() ?? new JsonObject();
                var schemaName = GetSchemaReferenceName(media["schema"], $"{location}/requestBody/content/{Escape(entry.Key)}/schema", operationId);
                result.Representations.Add(new RequestRepresentation { ContentType = entry.Key, Schema = schemaName, SourceRef = sourceRef });
            }
        }
        return result;
    }

    private List<NormalizedResponseCase> NormalizeResponses(JsonNode? node, string location, string operationId)
    {
        var result = new List<NormalizedResponseCase>();
        if (node is not JsonObject responses) return result;
        foreach (var entry in responses.OrderBy(x => x.Key, StringComparer.Ordinal))
        {
            var response = _resolver.ResolveObject(entry.Value, out var sourceRef);
            var selector = new StatusSelector
            {
                Kind = entry.Key.Equals("default", StringComparison.OrdinalIgnoreCase) ? "Default" : entry.Key.EndsWith('X') ? "Class" : "Exact",
                Value = entry.Key
            };
            var responseCase = new NormalizedResponseCase { StatusSelector = selector };
            if (response["content"] is JsonObject content)
            {
                foreach (var mediaEntry in content.OrderBy(x => x.Key, StringComparer.Ordinal))
                {
                    var media = mediaEntry.Value?.AsObject() ?? new JsonObject();
                    var schemaName = GetSchemaReferenceName(media["schema"], $"{location}/responses/{Escape(entry.Key)}/content/{Escape(mediaEntry.Key)}/schema", operationId);
                    var contentType = mediaEntry.Key.ToLowerInvariant();
                    var isErrorStatus = selector.Kind == "Class" || (selector.Kind == "Exact" && int.TryParse(entry.Key, out var exactStatus) && exactStatus >= 400);
                    responseCase.Representations.Add(new ResponseRepresentation
                    {
                        ContentType = mediaEntry.Key,
                        Schema = schemaName,
                        EnvelopePolicy = isErrorStatus ? (contentType.Contains("json", StringComparison.Ordinal) ? "ErrorEnvelope" : "Raw") : contentType.Contains("json", StringComparison.Ordinal) ? "CloudflareResult" : "Raw",
                        ParsingMode = contentType.Contains("json", StringComparison.Ordinal) ? "Json" : contentType.StartsWith("text/", StringComparison.Ordinal) ? "Text" : "Binary",
                        SourceRef = sourceRef
                    });
                }
            }
            else if (entry.Key == "204")
            {
                responseCase.Representations.Add(new ResponseRepresentation { ContentType = "no-content", Schema = string.Empty, EnvelopePolicy = "None", ParsingMode = "NoContent", SourceRef = sourceRef });
            }
            result.Add(responseCase);
        }
        return result;
    }

    private string GetSchemaReferenceName(JsonNode? node, string location, string? operationId = null)
    {
        if (node is null) return string.Empty;
        if (node is JsonObject obj && obj["$ref"] is JsonValue referenceValue)
        {
            var reference = referenceValue.GetValue<string>();
            var name = ReferenceName(reference);
            EnsureSchema(name, reference, _resolver.Resolve(reference).AsObject());
            return name;
        }
        var inlineName = "Inline_" + StableToken((operationId ?? "schema") + ":" + location);
        EnsureSchema(inlineName, null, node.AsObject());
        return inlineName;
    }

    private void EnsureSchema(string name, string? sourceRef, JsonObject raw)
    {
        if (_schemas.ContainsKey(name)) return;
        var schema = new NormalizedSchema { Name = name, SourceRef = sourceRef, Kind = DetermineKind(raw), PrimitiveType = StringValue(raw["type"]), Format = StringValue(raw["format"]) };
        _schemas[name] = schema;
        if (raw["items"] is not null)
            schema.Items = GetSchemaReferenceName(raw["items"], $"#/components/schemas/{Escape(name)}/items");
        if (raw["additionalProperties"] is JsonValue additionalPropertiesValue && additionalPropertiesValue.TryGetValue<bool>(out var additionalPropertiesAllowed))
            schema.AdditionalPropertiesAllowed = additionalPropertiesAllowed;
        else if (raw["additionalProperties"] is JsonObject additionalPropertiesSchema)
            schema.AdditionalPropertiesSchema = GetSchemaReferenceName(additionalPropertiesSchema, $"#/components/schemas/{Escape(name)}/additionalProperties");
        if (raw["required"] is JsonArray required)
            schema.RequiredProperties = required.Select(x => x?.GetValue<string>() ?? string.Empty).Where(x => x.Length > 0).OrderBy(x => x, StringComparer.Ordinal).ToList();
        foreach (var property in (raw["properties"]?.AsObject() ?? new JsonObject()).OrderBy(x => x.Key, StringComparer.Ordinal))
        {
            var propertyName = property.Key;
            var propertySchema = property.Value;
            var propertyRef = GetSchemaReferenceName(propertySchema, $"#/components/schemas/{Escape(name)}/properties/{Escape(propertyName)}");
            var propertyObject = ResolveSchemaObject(propertySchema);
            var isRequired = schema.RequiredProperties.Contains(propertyName, StringComparer.Ordinal);
            var allowsNull = AllowsNull(propertyObject);
            schema.Properties[propertyName] = new NormalizedProperty
            {
                Name = propertyName,
                Schema = propertyRef,
                Required = isRequired,
                AllowsNull = allowsNull,
                DefaultValue = propertyObject["default"]?.DeepClone(),
                NullPolicy = allowsNull ? "send-null" : isRequired ? "reject-null" : "omit",
                ReadOnly = BoolValue(propertyObject["readOnly"]),
                WriteOnly = BoolValue(propertyObject["writeOnly"])
            };
        }
        foreach (var key in new[] { "oneOf", "anyOf", "allOf" })
        {
            if (raw[key] is not JsonArray alternatives) continue;
            var target = key switch { "oneOf" => schema.OneOf, "anyOf" => schema.AnyOf, _ => schema.AllOf };
            for (var alternativeIndex = 0; alternativeIndex < alternatives.Count; alternativeIndex++)
            {
                var alternative = alternatives[alternativeIndex];
                var alternativeName = GetSchemaReferenceName(alternative, $"#/components/schemas/{Escape(name)}/{key}/{alternativeIndex}");
                if (!string.IsNullOrEmpty(alternativeName)) target.Add(alternativeName);
            }
        }
        if (raw["enum"] is JsonArray values)
        {
            schema.Enum = values.Select(ScalarText).ToList();
            if (schema.Enum.Count == 1) schema.SingleValue = values[0]?.DeepClone();
        }
        if (raw["const"] is not null) schema.SingleValue = raw["const"]!.DeepClone();
        var ownSingleValue = FindSingleTypeValue(raw, new HashSet<string>(StringComparer.Ordinal));
        if (!string.IsNullOrEmpty(ownSingleValue)) schema.SingleValue = JsonValue.Create(ownSingleValue);
        var explicitProperty = raw["discriminator"]?["propertyName"]?.GetValue<string>();
        var variants = FindDiscriminatorVariants(raw, name);
        if (!string.IsNullOrWhiteSpace(explicitProperty) || variants.Count > 0)
        {
            schema.Discriminator = new DiscriminatorModel { Property = explicitProperty ?? "type", SingleValue = variants.Count > 0, Variants = variants };
        }
    }

    private List<DiscriminatorVariant> FindDiscriminatorVariants(JsonObject raw, string owner)
    {
        var refs = new List<string>();
        foreach (var key in new[] { "oneOf", "anyOf" })
            if (raw[key] is JsonArray alternatives) refs.AddRange(alternatives.Select(x => x is JsonObject o && o["$ref"] is JsonValue r ? ReferenceName(r.GetValue<string>()) : string.Empty).Where(x => x.Length > 0));
        var variants = new List<DiscriminatorVariant>();
        foreach (var reference in refs.Distinct(StringComparer.Ordinal))
        {
            foreach (var value in FindTypeValues(_resolver.Resolve($"#/components/schemas/{reference}").AsObject(), new HashSet<string>(StringComparer.Ordinal)))
                variants.Add(new DiscriminatorVariant { Schema = reference, Value = value });
        }
        return variants.OrderBy(x => x.Value, StringComparer.Ordinal).ThenBy(x => x.Schema, StringComparer.Ordinal).ToList();
    }

    private List<string> FindTypeValues(JsonObject raw, HashSet<string> visited)
    {
        if (raw["properties"]?["type"]?["enum"] is JsonArray directValues && directValues.Count == 1)
            return [ScalarText(directValues[0])];
        var values = new List<string>();
        foreach (var key in new[] { "oneOf", "anyOf", "allOf" })
            if (raw[key] is JsonArray alternatives)
                foreach (var item in alternatives)
                {
                    if (item is JsonObject reference && reference["$ref"] is JsonValue referenceValue)
                    {
                        var referenceText = referenceValue.GetValue<string>();
                        if (visited.Add(referenceText)) values.AddRange(FindTypeValues(_resolver.Resolve(referenceText).AsObject(), visited));
                    }
                    else if (item is JsonObject inline) values.AddRange(FindTypeValues(inline, visited));
                }
        return values;
    }

    private string FindSingleTypeValue(JsonObject raw, HashSet<string> visited)
    {
        if (raw["properties"]?["type"]?["enum"] is JsonArray values && values.Count == 1) return ScalarText(values[0]);
        foreach (var key in new[] { "oneOf", "anyOf" })
            if (raw[key] is JsonArray alternatives)
                foreach (var item in alternatives)
                {
                    if (item is JsonObject reference && reference["$ref"] is JsonValue referenceValue)
                    {
                        var referenceText = referenceValue.GetValue<string>();
                        if (visited.Add(referenceText))
                        {
                            var found = FindSingleTypeValue(_resolver.Resolve(referenceText).AsObject(), visited);
                            if (!string.IsNullOrEmpty(found)) return found;
                        }
                    }
                }
        if (raw["allOf"] is JsonArray allOf)
            foreach (var item in allOf)
            {
                if (item is JsonObject reference && reference["$ref"] is JsonValue value)
                {
                    var referenceText = value.GetValue<string>();
                    if (visited.Add(referenceText))
                    {
                        var found = FindSingleTypeValue(_resolver.Resolve(referenceText).AsObject(), visited);
                        if (!string.IsNullOrEmpty(found)) return found;
                    }
                }
                else if (item is JsonObject inline)
                {
                    var found = FindSingleTypeValue(inline, visited);
                    if (!string.IsNullOrEmpty(found)) return found;
                }
            }
        return string.Empty;
    }

    private JsonObject ResolveSchemaObject(JsonNode? node)
    {
        if (node is JsonObject obj && obj["$ref"] is JsonValue reference) return _resolver.Resolve(reference.GetValue<string>()).AsObject();
        return node?.AsObject() ?? new JsonObject();
    }

    private bool IsCloudflareEnvelope(string schemaName)
    {
        if (!_schemas.TryGetValue(schemaName, out var schema)) return schemaName.Contains("response", StringComparison.OrdinalIgnoreCase);
        return schema.Properties.ContainsKey("success") || schema.Properties.ContainsKey("result") || schema.Properties.ContainsKey("errors") || schemaName.Contains("response", StringComparison.OrdinalIgnoreCase);
    }

    private PaginationModel? DetectPagination(NormalizedOperation operation, string operationId)
    {
        if (!operation.Method.Equals("GET", StringComparison.OrdinalIgnoreCase)) return operation.Responses.Count > 0 ? new PaginationModel { Strategy = "SinglePage", StopRule = "single response", Evidence = "non-GET operation" } : null;
        var hasPage = operation.Parameters.Any(x => x.Location == "query" && x.Name == "page")
            && operation.Parameters.Any(x => x.Location == "query" && x.Name == "per_page");
        var first = operation.Responses.SelectMany(x => x.Representations).FirstOrDefault(x => x.ContentType.Contains("json", StringComparison.OrdinalIgnoreCase));
        var pageLike = first is not null && hasPage && (first.Schema.Contains("collection", StringComparison.OrdinalIgnoreCase) || IsPageArraySchema(first.Schema));
        if (pageLike)
            return new PaginationModel { Strategy = "V4PagePaginationArray", RequestFields = operation.Parameters.Where(x => x.Name is "page" or "per_page").Select(x => x.Name).ToList(), ResponseFields = ["result", "result_info"], NextPageRule = "page + 1", StopRule = "empty result page", Evidence = "query page/per_page plus result collection schema" };
        return operation.Responses.Count > 0 ? new PaginationModel { Strategy = "SinglePage", StopRule = "single response", Evidence = "no recognized page-array pattern" } : null;
    }

    private bool IsPageArraySchema(string schemaName)
    {
        if (string.IsNullOrEmpty(schemaName)) return false;
        return HasSchemaProperty(schemaName, "result_info", new HashSet<string>(StringComparer.Ordinal))
            && TryGetSchemaProperty(schemaName, "result", out var resultProperty, new HashSet<string>(StringComparer.Ordinal))
            && _schemas.TryGetValue(resultProperty.Schema, out var resultSchema)
            && resultSchema.Kind == "array";
    }

    private bool HasSchemaProperty(string schemaName, string propertyName, HashSet<string> visited)
    {
        if (!visited.Add(schemaName) || !_schemas.TryGetValue(schemaName, out var schema)) return false;
        if (schema.Properties.ContainsKey(propertyName)) return true;
        return schema.AllOf.Any(x => HasSchemaProperty(x, propertyName, visited));
    }

    private bool TryGetSchemaProperty(string schemaName, string propertyName, out NormalizedProperty property, HashSet<string> visited)
    {
        property = new NormalizedProperty();
        if (!visited.Add(schemaName) || !_schemas.TryGetValue(schemaName, out var schema)) return false;
        if (schema.Properties.TryGetValue(propertyName, out property!)) return true;
        foreach (var child in schema.AllOf.AsEnumerable().Reverse())
            if (TryGetSchemaProperty(child, propertyName, out property, visited)) return true;
        return false;
    }

    private static List<ScopeBinding> InferScopeBindings(string path, IReadOnlyList<NormalizedParameter> parameters)
    {
        var pathNames = PathParameterNames(path);
        var nonGlobal = pathNames.Where(x => !IsGlobalScopeParameter(x)).ToList();
        var primaryName = path.TrimEnd('/').EndsWith('}') ? nonGlobal.LastOrDefault() : null;
        var bindings = new List<ScopeBinding>();
        foreach (var parameter in parameters.Where(x => x.Location == "path"))
        {
            if (!pathNames.Contains(parameter.Name, StringComparer.Ordinal)) continue;
            var scopeType = InferScopeType(path, parameter.Name);
            var role = parameter.Name.Equals("account_id", StringComparison.OrdinalIgnoreCase) ? "Parent"
                : parameter.Name is "zone_id" or "zone_identifier" && IsTopLevelResourceIdentifier(path, parameter.Name) ? "Primary"
                : parameter.Name is "zone_id" or "zone_identifier" ? "Parent"
                : parameter.Name.Equals(primaryName, StringComparison.Ordinal) ? "Primary"
                : "Nested";
            parameter.IsParentScopeId = role == "Parent";
            parameter.IsPrimaryResourceId = role == "Primary";
            bindings.Add(new ScopeBinding { ParameterName = parameter.Name, ScopeType = scopeType, Role = role });
        }
        return bindings;
    }

    private static List<string> PathParameterNames(string path)
        => path.Split('/', StringSplitOptions.RemoveEmptyEntries)
            .Where(x => x.StartsWith('{') && x.EndsWith('}'))
            .Select(x => x[1..^1])
            .ToList();

    private static bool IsGlobalScopeParameter(string name)
        => name is "zone_id" or "zone_identifier" or "account_id" or "user_id";

    private static bool IsTopLevelResourceIdentifier(string path, string parameterName)
    {
        var segments = path.Split('/', StringSplitOptions.RemoveEmptyEntries);
        for (var index = 1; index < segments.Length; index++)
        {
            if (segments[index] != "{" + parameterName + "}") continue;
            var parent = segments[index - 1];
            var hasLiteralAfter = segments.Skip(index + 1).Any(x => !x.StartsWith('{'));
            return parent is "zones" or "accounts" or "users" && !hasLiteralAfter;
        }
        return false;
    }

    private static string InferScopeType(string path, string parameterName)
    {
        if (parameterName is "zone_id" or "zone_identifier") return "Zone";
        if (parameterName == "account_id") return "Account";
        var segments = path.Split('/', StringSplitOptions.RemoveEmptyEntries);
        var marker = "{" + parameterName + "}";
        var index = Array.IndexOf(segments, marker);
        if (index > 0) return ToTitle(Singularize(segments[index - 1]));
        if (parameterName.EndsWith("_id", StringComparison.Ordinal)) return ToTitle(parameterName[..^3]);
        return ToTitle(parameterName);
    }

    private static string Singularize(string value)
        => value.EndsWith("ies", StringComparison.Ordinal) ? value[..^3] + "y"
        : value.EndsWith('s') && !value.EndsWith("ss", StringComparison.Ordinal) ? value[..^1]
        : value;

    private static OperationSemantic InferSemantic(string operationId, string method, string path)
    {
        var lower = operationId.ToLowerInvariant();
        if (method.Equals("GET", StringComparison.OrdinalIgnoreCase) && !path.TrimEnd('/').EndsWith('}') && lower.EndsWith("-get", StringComparison.Ordinal))
            return new OperationSemantic { Kind = "List", Source = "CollectionPathHeuristic", Confidence = "Medium" };
        foreach (var pair in new[] { ("list", "List"), ("details", "Get"), ("get", "Get"), ("create", "Create"), ("update", "Update"), ("overwrite", "Update"), ("patch", "Edit"), ("edit", "Edit"), ("delete", "Delete"), ("export", "Download"), ("import", "Upload") })
            if (lower.Contains(pair.Item1, StringComparison.Ordinal)) return new OperationSemantic { Kind = pair.Item2, Source = "OperationIdHeuristic", Confidence = "High" };
        var methodKind = method.ToUpperInvariant() switch { "GET" => "Get", "POST" => "Create", "PUT" => "Update", "PATCH" => "Edit", "DELETE" => "Delete", _ => "Unknown" };
        return new OperationSemantic { Kind = methodKind, Source = "MethodHeuristic", Confidence = "Low" };
    }

    private static List<string> GetResourcePath(string path)
    {
        var values = path.Split('/', StringSplitOptions.RemoveEmptyEntries).Where(x => !x.StartsWith('{')).ToList();
        var result = new List<string>();
        for (var index = 0; index < values.Count; index++)
        {
            var value = values[index];
            if (value is "zones" or "accounts" or "users") continue;
            var parts = value.Split(new[] { '_', '-' }, StringSplitOptions.RemoveEmptyEntries);
            result.AddRange(parts.Length > 1 ? parts : [value]);
        }
        if (result.Count == 0 && values.Count > 0) result.AddRange(values[0].Split(new[] { '_', '-' }, StringSplitOptions.RemoveEmptyEntries));
        return result;
    }

    private static SerializationModel ReadSerialization(JsonNode? style, JsonNode? explode, JsonObject schema)
    {
        var type = StringValue(schema["type"]);
        var array = type == "array" ? "repeat" : "repeat";
        var objectNotation = type == "object" ? "dots" : "dots";
        return new SerializationModel { Style = StringValue(style) ?? "form", Explode = explode is null || BoolValue(explode), ArrayNotation = array, ObjectNotation = objectNotation };
    }

    private static string DetermineKind(JsonObject raw)
        => raw["oneOf"] is JsonArray || raw["anyOf"] is JsonArray ? "union" : StringValue(raw["type"]) switch { "object" => "object", "array" => "array", "string" when raw["enum"] is JsonArray => "enum", null => "reference", _ => "primitive" };

    private static bool AllowsNull(JsonObject schema) => BoolValue(schema["nullable"]) || schema["type"] is JsonArray types && types.Any(x => x?.GetValue<string>() == "null");
    private static bool IsHttpMethod(string value) => value is "get" or "put" or "post" or "delete" or "patch" or "head" or "options" or "trace";
    private static bool BoolValue(JsonNode? node) => node is JsonValue value && value.TryGetValue<bool>(out var result) && result;
    private static string? StringValue(JsonNode? node) => node is JsonValue value && value.TryGetValue<string>(out var result) ? result : null;
    private static string ScalarText(JsonNode? node) => node is null ? string.Empty : node is JsonValue value && value.TryGetValue<string>(out var text) ? text : node.ToJsonString().Trim('"');
    private static string ReferenceName(string reference) => reference[(reference.LastIndexOf('/') + 1)..];
    private static string Escape(string value) => value.Replace("~", "~0", StringComparison.Ordinal).Replace("/", "~1", StringComparison.Ordinal);
    private static string StableToken(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)))[..12];
    private static string ToTitle(string value) => string.Concat(value.Split(new[] { '_', '-' }, StringSplitOptions.RemoveEmptyEntries).Select(x => x.Length == 0 ? string.Empty : char.ToUpperInvariant(x[0]) + x[1..]));
}
