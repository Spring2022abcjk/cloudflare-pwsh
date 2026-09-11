using System.Text.Json;
using System.Text.Json.Nodes;

namespace Cloudflare.Normalization;

public static class HandwrittenFixtureLoader
{
    public static NormalizedDocument Load(string directory)
    {
        var document = new NormalizedDocument { SourcePath = "fixtures/dns-records" };
        foreach (var path in Directory.EnumerateFiles(directory, "*.json", SearchOption.TopDirectoryOnly).OrderBy(x => x, StringComparer.OrdinalIgnoreCase))
        {
            if (Path.GetFileName(path).Equals("schemas.json", StringComparison.OrdinalIgnoreCase)) continue;
            var operation = JsonSerializer.Deserialize<NormalizedOperation>(File.ReadAllText(path), NormalizedJson.Options) ?? throw new InvalidDataException(path);
            if (operation.RequestBody?.Presence == "declared-but-observed-absent") operation.RequestBody.EffectivePresence = "absent";
            document.Operations.Add(operation);
        }
        var schemasPath = Path.Combine(directory, "schemas.json");
        if (File.Exists(schemasPath))
        {
            var root = JsonNode.Parse(File.ReadAllText(schemasPath))?.AsObject();
            foreach (var schemaNode in root?["schemas"]?.AsArray()?.OfType<JsonObject>() ?? [])
            {
                var schema = new NormalizedSchema
                {
                    Name = schemaNode["name"]?.GetValue<string>() ?? string.Empty,
                    Kind = schemaNode["kind"]?.GetValue<string>() ?? "reference",
                    RequiredProperties = schemaNode["requiredProperties"]?.AsArray()?.Select(x => x?.GetValue<string>() ?? string.Empty).ToList() ?? [],
                    Properties = new Dictionary<string, NormalizedProperty>(StringComparer.Ordinal),
                    OneOf = schemaNode["oneOf"]?.AsArray()?.Select(x => x?.GetValue<string>() ?? string.Empty).ToList() ?? [],
                    AnyOf = schemaNode["anyOf"]?.AsArray()?.Select(x => x?.GetValue<string>() ?? string.Empty).ToList() ?? [],
                    AllOf = schemaNode["allOf"]?.AsArray()?.Select(x => x?.GetValue<string>() ?? string.Empty).ToList() ?? []
                };
                if (schemaNode["singleValue"] is JsonValue singleValue)
                {
                    var value = singleValue.TryGetValue<string>(out var text) ? text : singleValue.DeepClone()?.ToJsonString() ?? string.Empty;
                    schema.SingleValue = JsonValue.Create(value);
                }
                if (schemaNode["variants"] is JsonArray variants)
                {
                    schema.Discriminator = new DiscriminatorModel
                    {
                        Property = schemaNode["discriminator"]?["property"]?.GetValue<string>() ?? "type",
                        SingleValue = true,
                        Variants = variants.Select(x =>
                        {
                            var name = x?.GetValue<string>() ?? string.Empty;
                            var value = name.Split("Record", StringSplitOptions.None)[0].Replace("Create", string.Empty, StringComparison.Ordinal).Replace("Edit", string.Empty, StringComparison.Ordinal);
                            return new DiscriminatorVariant { Schema = name, Value = value };
                        }).ToList()
                    };
                }
                if (schemaNode["discriminator"] is JsonObject discriminator && schema.Discriminator is null)
                    schema.Discriminator = new DiscriminatorModel { Property = discriminator["property"]?.GetValue<string>() ?? "type", SingleValue = discriminator["singleValue"]?.GetValue<bool>() ?? false };
                if (schemaNode["properties"] is JsonArray properties)
                    foreach (var property in properties.Select(x => x?.GetValue<string>() ?? string.Empty)) schema.Properties[property] = new NormalizedProperty { Name = property, Schema = property };
                document.Schemas[schema.Name] = schema;
            }
        }
        document.Operations = document.Operations.OrderBy(x => x.OperationId, StringComparer.Ordinal).ToList();
        return document;
    }
}
