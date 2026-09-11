using System.Text;
using System.Text.Json;
using Cloudflare.Normalization;

var projectRoot = Directory.GetCurrentDirectory();
var positionalArgs = args.Where(x => !x.StartsWith("--", StringComparison.Ordinal)).ToArray();
var openApiPath = positionalArgs.Length > 0 ? positionalArgs[0] : Path.Combine(projectRoot, "ref", "api-schemas", "openapi.json");
var updateSnapshots = args.Any(x => x.Equals("--update-snapshots", StringComparison.OrdinalIgnoreCase));
var correctionPath = Path.Combine(projectRoot, "overrides", "api-corrections.json");

var groups = new Dictionary<string, string[]>(StringComparer.Ordinal)
{
    ["zones"] = ["zones-get", "zones-post", "zones-0-get", "zones-0-patch", "zones-0-delete"],
    ["d1-database"] = ["d1-list-databases", "d1-create-database", "d1-get-database", "d1-update-database", "d1-delete-database"],
    ["ai-search-jobs"] = ["ai-search-namespace-instance-list-jobs", "ai-search-namespace-instance-create-job", "ai-search-namespace-instance-get-job", "ai-search-namespace-instance-change-job-status"]
};

var normalized = new OpenApiNormalizer(OpenApiLoader.Load(openApiPath)).NormalizeOperations(groups.Values.SelectMany(x => x).ToHashSet(StringComparer.Ordinal));
new ApiCorrectionEngine(correctionPath).Apply(normalized);
Equal(14, normalized.Operations.Count, "P2.1 selected operation count");

var byId = normalized.Operations.ToDictionary(x => x.OperationId, StringComparer.Ordinal);
CheckZones(byId);
CheckD1(byId);
CheckDeepNested(byId);

foreach (var group in groups)
{
    var operations = group.Value.Select(id => byId[id]).OrderBy(x => x.OperationId, StringComparer.Ordinal).ToList();
    var document = new NormalizedDocument
    {
        Version = normalized.Version,
        SourcePath = normalized.SourcePath,
        SourceRevision = normalized.SourceRevision,
        Operations = operations,
        Schemas = CollectSchemas(normalized, operations)
    };
    var fixtureRoot = Path.Combine(projectRoot, "fixtures", "p2.1", group.Key);
    if (updateSnapshots)
    {
        Directory.CreateDirectory(Path.Combine(fixtureRoot, "operations"));
        WriteJson(Path.Combine(fixtureRoot, "document.json"), document);
        foreach (var operation in operations)
            WriteJson(Path.Combine(fixtureRoot, "operations", operation.OperationId + ".json"), operation);
    }
    else
    {
        CompareFiles(Path.Combine(fixtureRoot, "document.json"), document, $"normalized fixture {group.Key}");
        foreach (var operation in operations)
            CompareFiles(Path.Combine(fixtureRoot, "operations", operation.OperationId + ".json"), operation, $"operation fixture {operation.OperationId}");
    }
    var snapshotPath = Path.Combine(projectRoot, "tests", "golden", "p2.1", group.Key + "-semantic.json");
    if (updateSnapshots) WriteJson(snapshotPath, document);
    else CompareFiles(snapshotPath, document, $"semantic snapshot {group.Key}");
}

Console.WriteLine($"PASS P2.1 normalization resources={groups.Count} operations={normalized.Operations.Count}");
Console.WriteLine("PASS CrossResourceNormalizationTests");
Console.WriteLine("PASS ScopeBindingTests");
return 0;

static Dictionary<string, NormalizedSchema> CollectSchemas(NormalizedDocument source, IReadOnlyList<NormalizedOperation> operations)
{
    var names = new HashSet<string>(StringComparer.Ordinal);
    foreach (var operation in operations)
    {
        foreach (var parameter in operation.Parameters) names.Add(parameter.Schema);
        foreach (var representation in operation.RequestBody?.Representations ?? []) names.Add(representation.Schema);
        foreach (var representation in operation.Responses.SelectMany(x => x.Representations)) names.Add(representation.Schema);
    }
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

static void CheckZones(IReadOnlyDictionary<string, NormalizedOperation> byId)
{
    var list = byId["zones-get"];
    Equal("List", list.OperationSemantic.Kind, "Zones collection semantic");
    Equal("zones", string.Join('/', list.ResourcePath), "Zones resource path");
    Equal("V4PagePaginationArray", list.Pagination?.Strategy, "Zones pagination");
    var zone = byId["zones-0-get"];
    Equal("Primary", zone.ScopeBindings.Single().Role, "Zones primary binding role");
    Equal("Zone", zone.ScopeBindings.Single().ScopeType, "Zones primary binding type");
}

static void CheckD1(IReadOnlyDictionary<string, NormalizedOperation> byId)
{
    var list = byId["d1-list-databases"];
    Equal("Account", list.ScopeBindings.Single().ScopeType, "D1 account binding type");
    Equal("Parent", list.ScopeBindings.Single().Role, "D1 account binding role");
    var database = byId["d1-get-database"];
    Equal(2, database.ScopeBindings.Count, "D1 nested binding count");
    Equal("Primary", database.ScopeBindings.Single(x => x.ParameterName == "database_id").Role, "D1 primary binding role");
    Equal("Database", database.ScopeBindings.Single(x => x.ParameterName == "database_id").ScopeType, "D1 primary binding type");
}

static void CheckDeepNested(IReadOnlyDictionary<string, NormalizedOperation> byId)
{
    var operation = byId["ai-search-namespace-instance-get-job"];
    Equal(4, operation.ScopeBindings.Count, "deep binding count");
    Equal("Parent", operation.ScopeBindings.Single(x => x.ParameterName == "account_id").Role, "deep account role");
    Equal("Namespace", operation.ScopeBindings.Single(x => x.ParameterName == "name").ScopeType, "deep namespace type");
    Equal("Nested", operation.ScopeBindings.Single(x => x.ParameterName == "name").Role, "deep namespace role");
    Equal("Instance", operation.ScopeBindings.Single(x => x.ParameterName == "id").ScopeType, "deep instance type");
    Equal("Nested", operation.ScopeBindings.Single(x => x.ParameterName == "id").Role, "deep instance role");
    Equal("Job", operation.ScopeBindings.Single(x => x.ParameterName == "job_id").ScopeType, "deep primary type");
    Equal("Primary", operation.ScopeBindings.Single(x => x.ParameterName == "job_id").Role, "deep primary role");
    Equal("Nested", byId["ai-search-namespace-instance-list-jobs"].ScopeBindings.Single(x => x.ParameterName == "id").Role, "deep collection parent role");
    Equal("Nested", byId["ai-search-namespace-instance-create-job"].ScopeBindings.Single(x => x.ParameterName == "id").Role, "deep collection create parent role");
    True(operation.ResourcePath.SequenceEqual(["ai", "search", "namespaces", "instances", "jobs"]), "deep resource path");
}

static void WriteJson<T>(string path, T value)
{
    Directory.CreateDirectory(Path.GetDirectoryName(path)!);
    var json = JsonSerializer.Serialize(value, NormalizedJson.Options).Replace("\r\n", "\n", StringComparison.Ordinal);
    File.WriteAllText(path, json.Replace("\r\n", "\n").Replace("\r", "\n").Replace("\n", "\r\n"), new UTF8Encoding(false));
}

static void CompareFiles<T>(string path, T value, string name)
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
