using System.Text.Json;
using Cloudflare.Normalization;

var projectRoot = Directory.GetCurrentDirectory();
var openApiPath = args.Length > 0 ? args[0] : Path.Combine(projectRoot, "ref", "api-schemas", "openapi.json");
var outputRoot = args.Length > 1 ? args[1] : Path.Combine(projectRoot, "artifacts", "generated-normalized", "dns-records");
var operationIds = new HashSet<string>(new[]
{
    "dns-records-for-a-zone-create-dns-record",
    "dns-records-for-a-zone-list-dns-records",
    "dns-records-for-a-zone-dns-record-details",
    "dns-records-for-a-zone-update-dns-record",
    "dns-records-for-a-zone-patch-dns-record",
    "dns-records-for-a-zone-delete-dns-record"
}, StringComparer.Ordinal);

var document = OpenApiLoader.Load(openApiPath);
Equal(true, document.Root.ContainsKey("paths"), "loader paths");
var raw = new OpenApiNormalizer(document).NormalizeOperations(operationIds);
Equal(6, raw.Operations.Count, "normalized DNS operation count");
Equal(true, raw.Operations.All(x => x.SourceLocation.StartsWith("#/paths/", StringComparison.Ordinal)), "source locations");
var rawDelete = raw.Operations.Single(x => x.OperationId.EndsWith("delete-dns-record", StringComparison.Ordinal));
Equal(true, rawDelete.RequestBody?.DeclaredContract == true, "raw DELETE declared body");

var corrected = new ApiCorrectionEngine(Path.Combine(projectRoot, "overrides", "api-corrections.json")).Apply(raw);
Equal("absent", rawDelete.RequestBody?.EffectivePresence, "corrected DELETE effective body");
Equal(1, rawDelete.CorrectionTrace.Count, "correction trace");
Equal("V4PagePaginationArray", corrected.Operations.Single(x => x.OperationId.Contains("list-dns-records", StringComparison.Ordinal)).Pagination?.Strategy, "pagination recognition");
Equal(true, corrected.Operations.All(x => x.Responses.Any(r => r.StatusSelector.Value == "4XX")), "response class");

var unionValues = corrected.Schemas.Values.SelectMany(x => x.Discriminator?.Variants.Select(v => v.Value) ?? []).Where(x => x.Length > 0).ToHashSet(StringComparer.Ordinal);
foreach (var value in new[] { "A", "MX", "CAA", "HTTPS", "SVCB" }) Equal(true, unionValues.Contains(value), $"discriminator {value}");

Directory.CreateDirectory(outputRoot);
foreach (var operation in corrected.Operations.OrderBy(x => x.OperationId, StringComparer.Ordinal))
    File.WriteAllText(Path.Combine(outputRoot, operation.OperationId + ".json"), JsonSerializer.Serialize(operation, NormalizedJson.Options));
File.WriteAllText(Path.Combine(Path.GetDirectoryName(outputRoot)!, "document.json"), JsonSerializer.Serialize(corrected, NormalizedJson.Options));

var handwritten = HandwrittenFixtureLoader.Load(Path.Combine(projectRoot, "fixtures", "dns-records"));
var comparison = SemanticComparer.Compare(handwritten, corrected);
if (!comparison.IsEquivalent)
{
    foreach (var difference in comparison.Differences.Take(20)) Console.Error.WriteLine($"DIFF {difference.Path}: expected={difference.Expected}; actual={difference.Actual}");
    return 1;
}

var miniPath = Path.Combine(projectRoot, "tests", "fixtures", "openapi-mini.json");
var miniDocument = OpenApiLoader.Load(miniPath);
var mini = new OpenApiNormalizer(miniDocument).NormalizeOperations();
var miniList = mini.Operations.Single(x => x.OperationId == "things-list");
Equal(5, miniList.Responses.Count, "mini response selector count");
Equal("Class", miniList.Responses.Single(x => x.StatusSelector.Value == "4XX").StatusSelector.Kind, "mini response class");
Equal("Default", miniList.Responses.Single(x => x.StatusSelector.Value == "default").StatusSelector.Kind, "mini default response");
Equal("Text", miniList.Responses.Single(x => x.StatusSelector.Value == "201").Representations[0].ParsingMode, "mini text response");
Equal("Binary", miniList.Responses.Single(x => x.StatusSelector.Value == "default").Representations[0].ParsingMode, "mini binary response");
Equal("NoContent", miniList.Responses.Single(x => x.StatusSelector.Value == "204").Representations[0].ParsingMode, "mini no-content response");
var miniCreate = mini.Operations.Single(x => x.OperationId == "things-create");
Equal(4, miniCreate.RequestBody?.Representations.Count, "mini request representations");
Equal("operation override", miniList.Parameters.Single(x => x.Name == "zone_id").SourceRef.Contains("/parameters", StringComparison.Ordinal) ? "operation override" : "wrong", "parameter source");
var nested = mini.Operations.Single(x => x.OperationId == "nested-things-list");
Equal(true, nested.ScopeBindings.Any(x => x.ScopeType == "Account" && x.Role == "Parent"), "nested account scope");
Equal(true, nested.ScopeBindings.Any(x => x.ScopeType == "Namespace" && x.Role == "Nested"), "nested namespace scope");
Equal(true, nested.ScopeBindings.Any(x => x.ScopeType == "Instance" && x.Role == "Nested"), "nested instance scope");
try
{
    _ = new RefResolver(miniDocument.Root).ResolveFully("#/components/schemas/CycleA");
    return 1;
}
catch (InvalidDataException ex) when (ex.Message.Contains("Circular", StringComparison.Ordinal)) { }

Console.WriteLine($"PASS OpenAPI loader/ref-normalizer/semantic-diff operations={corrected.Operations.Count} schemas={corrected.Schemas.Count}");
return 0;

static void Equal<T>(T expected, T actual, string name)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual)) throw new InvalidOperationException($"{name}: expected '{expected}', got '{actual}'");
}
