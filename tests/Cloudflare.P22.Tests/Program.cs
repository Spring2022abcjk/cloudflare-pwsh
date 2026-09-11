using System.Text;
using System.Text.Json;
using Cloudflare.Normalization;

var projectRoot = Directory.GetCurrentDirectory();
var positionalArgs = args.Where(x => !x.StartsWith("--", StringComparison.Ordinal)).ToArray();
var openApiPath = positionalArgs.Length > 0 ? positionalArgs[0] : Path.Combine(projectRoot, "ref", "api-schemas", "openapi.json");
var updateSnapshots = args.Any(x => x.Equals("--update-snapshots", StringComparison.OrdinalIgnoreCase));

var cases = new Dictionary<string, string>(StringComparer.Ordinal)
{
    ["dns-export"] = "dns-records-for-a-zone-export-dns-records",
    ["dns-import"] = "dns-records-for-a-zone-import-dns-records",
    ["ai-search-upload"] = "ai-search-namespace-instance-upload-item",
    ["ai-search-download"] = "ai-search-namespace-instance-get-item-content"
};

var document = new OpenApiNormalizer(OpenApiLoader.Load(openApiPath)).NormalizeOperations(cases.Values.ToHashSet(StringComparer.Ordinal));
Equal(4, document.Operations.Count, "P2.2 selected operation count");
var operations = document.Operations.ToDictionary(x => x.OperationId, StringComparer.Ordinal);

CheckDnsExport(operations["dns-records-for-a-zone-export-dns-records"]);
CheckDnsImport(operations["dns-records-for-a-zone-import-dns-records"], document.Schemas);
CheckAiSearchUpload(operations["ai-search-namespace-instance-upload-item"], document.Schemas);
CheckAiSearchDownload(operations["ai-search-namespace-instance-get-item-content"]);

foreach (var item in cases)
{
    var operation = operations[item.Value];
    var snapshot = new NormalizedDocument
    {
        Version = document.Version,
        SourcePath = document.SourcePath,
        SourceRevision = document.SourceRevision,
        Operations = [operation],
        Schemas = CollectSchemas(document, operation)
    };
    var fixtureRoot = Path.Combine(projectRoot, "fixtures", "p2.2", item.Key);
    if (updateSnapshots)
    {
        Directory.CreateDirectory(Path.Combine(fixtureRoot, "operations"));
        WriteJson(Path.Combine(fixtureRoot, "document.json"), snapshot);
        WriteJson(Path.Combine(fixtureRoot, "operations", operation.OperationId + ".json"), operation);
    }
    else
    {
        CompareJson(Path.Combine(fixtureRoot, "document.json"), snapshot, $"normalized fixture {item.Key}");
        CompareJson(Path.Combine(fixtureRoot, "operations", operation.OperationId + ".json"), operation, $"operation fixture {item.Value}");
    }
    var golden = Path.Combine(projectRoot, "tests", "golden", "p2.2", item.Key + "-semantic.json");
    if (updateSnapshots) WriteJson(golden, snapshot);
    else CompareJson(golden, snapshot, $"semantic snapshot {item.Key}");
}

Console.WriteLine("PASS SpecialTransportNormalizationTests");
Console.WriteLine("PASS RequestResponseRepresentationTests");
Console.WriteLine("PASS P2.2 multipart=text/binary coverage");
return 0;

static void CheckDnsExport(NormalizedOperation operation)
{
    True(operation.RequestBody is null, "DNS export request body absent");
    var success = Response(operation, "200");
    Equal("text/plain", success.ContentType, "DNS export content type");
    Equal("Text", success.ParsingMode, "DNS export parsing mode");
    Equal("Raw", success.EnvelopePolicy, "DNS export envelope policy");
    Equal("ErrorEnvelope", Response(operation, "4XX").EnvelopePolicy, "DNS export error envelope");
}

static void CheckDnsImport(NormalizedOperation operation, IReadOnlyDictionary<string, NormalizedSchema> schemas)
{
    True(operation.RequestBody is not null, "DNS import request body present");
    var request = operation.RequestBody!;
    Equal(true, request.Required, "DNS import request required");
    var representation = request.Representations.Single();
    Equal("multipart/form-data", representation.ContentType, "DNS import content type");
    var bodySchema = schemas[representation.Schema];
    Equal("object", bodySchema.Kind, "DNS import body kind");
    True(bodySchema.RequiredProperties.Contains("file", StringComparer.Ordinal), "DNS import file required");
    var fileSchema = schemas[bodySchema.Properties["file"].Schema];
    Equal("string", fileSchema.PrimitiveType, "DNS import file primitive");
    Equal(null, fileSchema.Format, "DNS import file format remains unspecified");
    Equal("CloudflareResult", Response(operation, "200").EnvelopePolicy, "DNS import response envelope");
}

static void CheckAiSearchUpload(NormalizedOperation operation, IReadOnlyDictionary<string, NormalizedSchema> schemas)
{
    True(operation.RequestBody is not null, "AI Search upload request body present");
    var request = operation.RequestBody!;
    Equal("multipart/form-data", request.Representations.Single().ContentType, "AI Search upload content type");
    var bodySchema = schemas[request.Representations.Single().Schema];
    True(bodySchema.RequiredProperties.Contains("file", StringComparer.Ordinal), "AI Search upload file required");
    var fileSchema = schemas[bodySchema.Properties["file"].Schema];
    Equal("string", fileSchema.PrimitiveType, "AI Search upload file primitive");
    Equal("binary", fileSchema.Format, "AI Search upload file format");
    Equal("CloudflareResult", Response(operation, "200").EnvelopePolicy, "AI Search upload response envelope");
}

static void CheckAiSearchDownload(NormalizedOperation operation)
{
    var success = Response(operation, "200");
    Equal("application/octet-stream", success.ContentType, "AI Search download content type");
    Equal("Binary", success.ParsingMode, "AI Search download parsing mode");
    Equal("Raw", success.EnvelopePolicy, "AI Search download envelope policy");
    foreach (var status in new[] { "400", "403", "404", "503" })
        Equal("ErrorEnvelope", Response(operation, status).EnvelopePolicy, $"AI Search {status} error envelope");
    Equal("Get", operation.OperationSemantic.Kind, "AI Search download semantic");
}

static ResponseRepresentation Response(NormalizedOperation operation, string status)
    => operation.Responses.Single(x => x.StatusSelector.Value == status).Representations.Single();

static Dictionary<string, NormalizedSchema> CollectSchemas(NormalizedDocument source, NormalizedOperation operation)
{
    var names = new HashSet<string>(StringComparer.Ordinal);
    foreach (var parameter in operation.Parameters) names.Add(parameter.Schema);
    foreach (var representation in operation.RequestBody?.Representations ?? []) names.Add(representation.Schema);
    foreach (var representation in operation.Responses.SelectMany(x => x.Representations)) names.Add(representation.Schema);
    var result = new Dictionary<string, NormalizedSchema>(StringComparer.Ordinal);
    var pending = new Queue<string>(names.Where(x => !string.IsNullOrEmpty(x)).OrderBy(x => x, StringComparer.Ordinal));
    while (pending.Count > 0)
    {
        var name = pending.Dequeue();
        if (result.ContainsKey(name)) continue;
        result[name] = source.Schemas[name];
        var schema = result[name];
        foreach (var child in schema.Properties.Values.Select(x => x.Schema).Concat(schema.OneOf).Concat(schema.AnyOf).Concat(schema.AllOf).Where(x => !string.IsNullOrEmpty(x)).OrderBy(x => x, StringComparer.Ordinal))
            if (source.Schemas.ContainsKey(child)) pending.Enqueue(child);
    }
    return result;
}

static void WriteJson<T>(string path, T value)
{
    Directory.CreateDirectory(Path.GetDirectoryName(path)!);
    var json = JsonSerializer.Serialize(value, NormalizedJson.Options).Replace("\r\n", "\n", StringComparison.Ordinal);
    File.WriteAllText(path, json.Replace("\r\n", "\n").Replace("\r", "\n").Replace("\n", "\r\n"), new UTF8Encoding(false));
}

static void CompareJson<T>(string path, T value, string name)
{
    var expected = File.ReadAllText(path).Replace("\r\n", "\n", StringComparison.Ordinal);
    var actual = JsonSerializer.Serialize(value, NormalizedJson.Options).Replace("\r\n", "\n", StringComparison.Ordinal);
    Equal(expected, actual, name);
}

static void Equal<T>(T expected, T actual, string name)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual)) throw new InvalidOperationException($"{name}: expected '{expected}', got '{actual}'");
}

static void True(bool value, string name)
{
    if (!value) throw new InvalidOperationException($"{name}: assertion failed");
}
