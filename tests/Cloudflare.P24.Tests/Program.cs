using System.Text.Json;
using System.Text.Json.Nodes;
using Cloudflare.Normalization;
using Cloudflare.Normalization.Compatibility;

var failures = new List<string>();

void Expect(string name, Func<NormalizedDocument, NormalizedDocument> mutation, ApiChangeKind kind, CompatibilityImpact? impact = null)
{
    var report = CompatibilityEngine.Compare(Base(), mutation(Base()));
    var matches = report.Changes.Where(x => x.Kind == kind).ToArray();
    if (matches.Length == 0 || impact is not null && !matches.Any(x => x.ApiImpact == impact || x.SdkImpact == impact || x.PowerShellImpact == impact))
        failures.Add($"{name}: expected {kind}/{impact}, got {string.Join(',', report.Changes.Select(x => x.Kind).Distinct())}");
    else Console.WriteLine($"PASS {name}");
}

void ExpectPair(string name, Func<NormalizedDocument, NormalizedDocument> oldMutation, Func<NormalizedDocument, NormalizedDocument> newMutation, ApiChangeKind kind, CompatibilityImpact? impact = null)
{
    var report = CompatibilityEngine.Compare(oldMutation(Base()), newMutation(Base()));
    var matches = report.Changes.Where(x => x.Kind == kind).ToArray();
    if (matches.Length == 0 || impact is not null && !matches.Any(x => x.ApiImpact == impact || x.SdkImpact == impact || x.PowerShellImpact == impact))
        failures.Add($"{name}: expected {kind}/{impact}, got {string.Join(',', report.Changes.Select(x => x.Kind).Distinct())}");
    else Console.WriteLine($"PASS {name}");
}

Expect("operation added", d => { d.Operations.Add(Operation("extra", "POST")); return d; }, ApiChangeKind.OperationAdded);
Expect("operation removed", d => { d.Operations.RemoveAll(x => x.OperationId == "things-list"); return d; }, ApiChangeKind.OperationRemoved, CompatibilityImpact.Breaking);
Expect("method changed", d => { d.Operations[0].Method = "POST"; return d; }, ApiChangeKind.HttpMethodChanged, CompatibilityImpact.Breaking);
Expect("path changed", d => { d.Operations[0].PathTemplate = "/things/{id}"; return d; }, ApiChangeKind.PathChanged, CompatibilityImpact.Breaking);
Expect("resource path changed", d => { d.Operations[0].ResourcePath = ["accounts"]; return d; }, ApiChangeKind.ResourcePathChanged, CompatibilityImpact.Breaking);
Expect("semantic kind changed", d => { d.Operations[0].OperationSemantic.Kind = "Create"; return d; }, ApiChangeKind.SemanticKindChanged);
Expect("scope binding added", d => { d.Operations[0].ScopeBindings.Add(new ScopeBinding { ParameterName = "account_id", ScopeType = "AccountId", Role = "Parent" }); return d; }, ApiChangeKind.ScopeBindingAdded);
Expect("scope binding removed", d => { d.Operations[0].ScopeBindings.Clear(); return d; }, ApiChangeKind.ScopeBindingRemoved, CompatibilityImpact.Breaking);
Expect("scope binding role changed", d => { d.Operations[0].ScopeBindings[0].Role = "Primary"; return d; }, ApiChangeKind.ScopeBindingRoleChanged, CompatibilityImpact.Breaking);
Expect("primary resource id classification", d => { d.Operations[0].Parameters[1].IsPrimaryResourceId = true; return d; }, ApiChangeKind.PrimaryResourceIdChanged, CompatibilityImpact.Breaking);
Expect("parameter added", d => { d.Operations[0].Parameters.Add(new NormalizedParameter { Name = "filter", Location = "query", Schema = "String", NullPolicy = "omit" }); return d; }, ApiChangeKind.ParameterAdded);
Expect("required parameter", d => { d.Operations[0].Parameters[1].Required = true; return d; }, ApiChangeKind.ParameterBecameRequired, CompatibilityImpact.Breaking);
Expect("optional parameter", d => { d.Operations[0].Parameters[0].Required = false; return d; }, ApiChangeKind.ParameterBecameOptional);
Expect("parameter location", d => { d.Operations[0].Parameters[1].Location = "header"; return d; }, ApiChangeKind.ParameterLocationChanged, CompatibilityImpact.Breaking);
Expect("parameter type", d => { d.Operations[0].Parameters[1].Schema = "Integer"; return d; }, ApiChangeKind.ParameterTypeChanged, CompatibilityImpact.Breaking);
Expect("parameter serialization", d => { d.Operations[0].Parameters[1].Serialization.Style = "spaceDelimited"; return d; }, ApiChangeKind.ParameterSerializationChanged, CompatibilityImpact.Breaking);
Expect("parameter nullability", d => { d.Operations[0].Parameters[1].AllowsNull = true; return d; }, ApiChangeKind.ParameterNullabilityChanged);
Expect("parameter default", d => { d.Operations[0].Parameters[1].DefaultValue = JsonValue.Create("next"); return d; }, ApiChangeKind.DefaultChanged);
Expect("parameter removed", d => { d.Operations[0].Parameters.RemoveAll(x => x.Name == "page"); return d; }, ApiChangeKind.ParameterRemoved, CompatibilityImpact.Breaking);
Expect("request body required", d => { d.Operations[0].RequestBody!.Required = true; return d; }, ApiChangeKind.RequestBodyRequiredChanged, CompatibilityImpact.Breaking);
Expect("request body presence", d => { d.Operations[0].RequestBody!.EffectivePresence = "required"; return d; }, ApiChangeKind.RequestBodyPresenceChanged);
ExpectPair("request content type added", d => d, d => { d.Operations[0].RequestBody!.Representations.Add(new RequestRepresentation { ContentType = "text/plain", Schema = "String" }); return d; }, ApiChangeKind.RequestContentTypeAdded);
Expect("request schema", d => { d.Operations[0].RequestBody!.Representations[0].Schema = "String"; return d; }, ApiChangeKind.RequestSchemaChanged, CompatibilityImpact.Breaking);
ExpectPair("pagination added", d => { d.Operations[0].Pagination = null; return d; }, d => d, ApiChangeKind.PaginationAdded);
Expect("pagination removed", d => { d.Operations[0].Pagination = null; return d; }, ApiChangeKind.PaginationRemoved, CompatibilityImpact.Breaking);
Expect("pagination strategy", d => { d.Operations[0].Pagination!.Strategy = "Cursor"; return d; }, ApiChangeKind.PaginationStrategyChanged, CompatibilityImpact.Breaking);
Expect("request paging field", d => { d.Operations[0].Pagination!.RequestFields = ["cursor"]; return d; }, ApiChangeKind.RequestPagingFieldChanged);
Expect("response paging field", d => { d.Operations[0].Pagination!.ResponseFields = ["next_cursor"]; return d; }, ApiChangeKind.ResponsePagingFieldChanged);
Expect("stop rule", d => { d.Operations[0].Pagination!.StopRule = "next_cursor is null"; return d; }, ApiChangeKind.StopRuleChanged);
Expect("next page rule", d => { d.Operations[0].Pagination!.NextPageRule = "result_info.next_page"; return d; }, ApiChangeKind.NextPageRuleChanged);
Expect("success status added", d => { d.Operations[0].Responses.Add(new NormalizedResponseCase { StatusSelector = new StatusSelector { Kind = "Exact", Value = "201" } }); return d; }, ApiChangeKind.SuccessStatusAdded);
ExpectPair("response content type added", d => d, d => { d.Operations[0].Responses[0].Representations.Add(new ResponseRepresentation { ContentType = "text/plain", Schema = "String" }); return d; }, ApiChangeKind.ResponseContentTypeAdded);
Expect("error response removed", d => { d.Operations[0].Responses.RemoveAll(x => x.StatusSelector.Value == "400"); return d; }, ApiChangeKind.ErrorResponseChanged, CompatibilityImpact.Breaking);
Expect("response content type", d => { d.Operations[0].Responses[0].Representations[0].ContentType = "application/problem+json"; return d; }, ApiChangeKind.ResponseContentTypeRemoved, CompatibilityImpact.Breaking);
Expect("envelope policy", d => { d.Operations[0].Responses[0].Representations[0].EnvelopePolicy = "Raw"; return d; }, ApiChangeKind.EnvelopePolicyChanged, CompatibilityImpact.Breaking);
Expect("parsing mode", d => { d.Operations[0].Responses[0].Representations[0].ParsingMode = "Text"; return d; }, ApiChangeKind.ParsingModeChanged, CompatibilityImpact.Breaking);
Expect("result schema", d => { d.Operations[0].Responses[0].Representations[0].Schema = "Other"; return d; }, ApiChangeKind.ResultSchemaChanged, CompatibilityImpact.Breaking);
Expect("request property added", d => { d.Schemas["ThingRequest"].Properties["description"] = new NormalizedProperty { Name = "description", Schema = "String" }; return d; }, ApiChangeKind.PropertyAdded);
Expect("response property removed", d => { d.Schemas["Thing"].Properties.Remove("name"); return d; }, ApiChangeKind.PropertyRemoved, CompatibilityImpact.Breaking);
Expect("schema type", d => { d.Schemas["Thing"].PrimitiveType = "integer"; return d; }, ApiChangeKind.SchemaTypeChanged, CompatibilityImpact.Breaking);
Expect("property required", d => { d.Schemas["Thing"].Properties["kind"].Required = true; return d; }, ApiChangeKind.PropertyBecameRequired, CompatibilityImpact.Breaking);
Expect("property optional", d => { d.Schemas["Thing"].Properties["name"].Required = false; d.Schemas["Thing"].Properties["kind"].Required = true; return d; }, ApiChangeKind.PropertyBecameOptional);
Expect("property type", d => { d.Schemas["Thing"].Properties["name"].Schema = "Integer"; return d; }, ApiChangeKind.PropertyTypeChanged, CompatibilityImpact.Breaking);
Expect("property nullable", d => { d.Schemas["Thing"].Properties["name"].AllowsNull = true; return d; }, ApiChangeKind.NullableChanged);
Expect("property read-only", d => { d.Schemas["Thing"].Properties["name"].ReadOnly = true; return d; }, ApiChangeKind.ReadOnlyChanged);
Expect("property write-only", d => { d.Schemas["Thing"].Properties["name"].WriteOnly = true; return d; }, ApiChangeKind.WriteOnlyChanged);
Expect("property default", d => { d.Schemas["Thing"].Properties["name"].DefaultValue = JsonValue.Create("other"); return d; }, ApiChangeKind.DefaultChanged);
Expect("enum value added", d => { d.Schemas["ThingKind"].Enum.Add("archived"); return d; }, ApiChangeKind.EnumValueAdded);
Expect("enum value removed", d => { d.Schemas["ThingKind"].Enum.Remove("active"); return d; }, ApiChangeKind.EnumValueRemoved, CompatibilityImpact.Breaking);
Expect("union variant added", d => { d.Schemas["ThingUnion"].OneOf.Add("ThingC"); return d; }, ApiChangeKind.UnionVariantAdded);
Expect("union variant removed", d => { d.Schemas["ThingUnion"].OneOf.Remove("ThingB"); return d; }, ApiChangeKind.UnionVariantRemoved, CompatibilityImpact.Breaking);
Expect("discriminator property", d => { d.Schemas["ThingUnion"].Discriminator!.Property = "kind_name"; return d; }, ApiChangeKind.DiscriminatorPropertyChanged, CompatibilityImpact.Breaking);
Expect("discriminator value", d => { d.Schemas["ThingUnion"].Discriminator!.Variants[0].Value = "renamed"; return d; }, ApiChangeKind.DiscriminatorValueChanged, CompatibilityImpact.Breaking);
Expect("discriminator added", d => { d.Schemas["Thing"].Discriminator = new DiscriminatorModel { Property = "kind" }; return d; }, ApiChangeKind.DiscriminatorAdded);
Expect("discriminator removed", d => { d.Schemas["ThingUnion"].Discriminator = null; return d; }, ApiChangeKind.DiscriminatorRemoved, CompatibilityImpact.Breaking);
Expect("schema composition", d => { d.Schemas["Thing"].AllOf.Add("ThingRequest"); return d; }, ApiChangeKind.SchemaCompositionChanged, CompatibilityImpact.Breaking);

var projection = JsonNode.Parse("""
{"cmdlets":[{"cmdletName":"Get-CfThing","parameterSets":["List"],"parameters":[{"name":"ZoneId","requiredIn":["List"],"valueFromPipeline":false,"valueFromPipelineByPropertyName":true}],"outputType":"Thing","supportsShouldProcess":false,"confirmImpact":"None","pagingBehavior":"PageArray"}]}
""")!;
if (ProjectionCompatibility.Compare(projection, projection).Count != 0) failures.Add("projection identity: unexpected changes"); else Console.WriteLine("PASS projection identity");
var projectionMutation = projection.DeepClone();
projectionMutation!["cmdlets"]![0]! ["outputType"] = "Other";
projectionMutation["cmdlets"]![0]!["supportsShouldProcess"] = true;
projectionMutation["cmdlets"]![0]!["parameters"]![0]!["valueFromPipeline"] = true;
var projectionChanges = ProjectionCompatibility.Compare(projection, projectionMutation);
if (!projectionChanges.Any(x => x.Kind == ApiChangeKind.OutputTypeChanged) || !projectionChanges.Any(x => x.Kind == ApiChangeKind.ShouldProcessChanged) || !projectionChanges.Any(x => x.Kind == ApiChangeKind.PipelineBindingChanged)) failures.Add("projection fields: expected typed changes"); else Console.WriteLine("PASS projection fields");
var projectionAdded = projection.DeepClone()!.AsObject();
projectionAdded["cmdlets"]!.AsArray().Add(new JsonObject { ["cmdletName"] = "New-CfOther", ["parameterSets"] = new JsonArray(), ["parameters"] = new JsonArray() });
if (!ProjectionCompatibility.Compare(projection, projectionAdded).Any(x => x.Kind == ApiChangeKind.CmdletAdded)) failures.Add("projection cmdlet added: expected typed change"); else Console.WriteLine("PASS projection cmdlet added");
var projectionRemoved = projection.DeepClone()!.AsObject();
projectionRemoved["cmdlets"]!.AsArray().Clear();
if (!ProjectionCompatibility.Compare(projection, projectionRemoved).Any(x => x.Kind == ApiChangeKind.CmdletRemoved)) failures.Add("projection cmdlet removed: expected typed change"); else Console.WriteLine("PASS projection cmdlet removed");
var projectionParameter = projection.DeepClone()!.AsObject();
projectionParameter["cmdlets"]![0]!["parameters"]!.AsArray().Add(new JsonObject { ["name"] = "Other", ["requiredIn"] = new JsonArray("List") });
if (!ProjectionCompatibility.Compare(projection, projectionParameter).Any(x => x.Kind == ApiChangeKind.PowerShellParameterAdded)) failures.Add("projection parameter added: expected typed change"); else Console.WriteLine("PASS projection parameter added");
var projectionSet = projection.DeepClone()!.AsObject();
projectionSet["cmdlets"]![0]!["parameterSets"]!.AsArray().Add("Get");
if (!ProjectionCompatibility.Compare(projection, projectionSet).Any(x => x.Kind == ApiChangeKind.PowerShellParameterSetChanged)) failures.Add("projection parameter set: expected typed change"); else Console.WriteLine("PASS projection parameter set");
var baseReport = CompatibilityEngine.Compare(Base(), Base());
if (!baseReport.SeveritySummary.ContainsKey("Api:Unknown") || baseReport.FullyCompatible is false) failures.Add("unknown summary/identity: unexpected report state"); else Console.WriteLine("PASS unknown summary and identity");
var parameterSchemaContext = Base();
parameterSchemaContext.Schemas["ThingKind"].Enum.Add("new-value");
var parameterSchemaChanges = CompatibilityEngine.Compare(Base(), parameterSchemaContext).Changes;
if (!parameterSchemaChanges.Any(x => x.Kind == ApiChangeKind.EnumValueAdded && x.Path.Contains("ThingKind[Request]", StringComparison.Ordinal))) failures.Add("parameter schema context: expected Request context"); else Console.WriteLine("PASS parameter schema request context");
var builtProjection = ProjectionModelBuilder.Build(Base());
if (ProjectionCompatibility.Compare(builtProjection, builtProjection).Count != 0) failures.Add("projection builder identity: unexpected changes"); else Console.WriteLine("PASS projection builder identity");
var collisions = ProjectionCompatibility.FindPowerShellNameCollisions(["foo-bar", "foo_bar", "foo.bar"]);
if (collisions.Count != 1 || collisions[0].NewValue != "FooBar" || collisions[0].PowerShellImpact != CompatibilityImpact.Breaking) failures.Add("name collision: expected FooBar collision"); else Console.WriteLine("PASS PowerShell name collision");
var collisionDocument = Base();
collisionDocument.Operations[0].Parameters.Add(new NormalizedParameter { Name = "foo-bar", Location = "query", Schema = "String" });
collisionDocument.Operations[0].Parameters.Add(new NormalizedParameter { Name = "foo_bar", Location = "query", Schema = "String" });
if (ProjectionModelBuilder.FindNameCollisions(collisionDocument).Count != 1) failures.Add("projection builder collision: expected one collision"); else Console.WriteLine("PASS projection builder name collision");
var deterministicOptions = new JsonSerializerOptions { WriteIndented = true };
var deterministicReport1 = CompatibilityEngine.Compare(Base(), collisionDocument);
var deterministicReport2 = CompatibilityEngine.Compare(Base(), collisionDocument);
if (JsonSerializer.Serialize(deterministicReport1, CompatibilityJson.Options) != JsonSerializer.Serialize(deterministicReport2, CompatibilityJson.Options) || CompatibilityReportFormatter.ToMarkdown(deterministicReport1) != CompatibilityReportFormatter.ToMarkdown(deterministicReport2) || builtProjection.ToJsonString(deterministicOptions) != ProjectionModelBuilder.Build(Base()).ToJsonString(deterministicOptions)) failures.Add("determinism: repeated serialization differed"); else Console.WriteLine("PASS deterministic model/report serialization");

if (args.Length >= 2)
{
    var oldPath = args[0];
    var newPath = args[1];
    var outputRoot = args.Length >= 3 ? args[2] : Path.Combine("artifacts", "compatibility");
    var oldDocument = new OpenApiNormalizer(OpenApiLoader.Load(oldPath)).NormalizeOperations();
    var newDocument = new OpenApiNormalizer(OpenApiLoader.Load(newPath)).NormalizeOperations();
    var oldRevision = args.Length >= 4 ? args[3] : Revision(oldPath);
    var newRevision = args.Length >= 5 ? args[4] : Revision(newPath);
    oldDocument.SourceRevision = oldRevision;
    newDocument.SourceRevision = newRevision;
    var report = CompatibilityEngine.Compare(oldDocument, newDocument);
    Directory.CreateDirectory(outputRoot);
    var jsonPath = Path.Combine(outputRoot, $"{oldRevision}-to-{newRevision}.json");
    var markdownPath = Path.Combine(outputRoot, $"{oldRevision}-to-{newRevision}.md");
    File.WriteAllText(jsonPath, JsonSerializer.Serialize(report, CompatibilityJson.Options) + Environment.NewLine);
    File.WriteAllText(markdownPath, CompatibilityReportFormatter.ToMarkdown(report));
    Console.WriteLine($"PASS real revision diff {report.Changes.Count} changes -> {jsonPath}");

    if (args.Length >= 7)
    {
        var policy = JsonNode.Parse(File.ReadAllText(args[5]))?.AsObject() ?? new JsonObject();
        var projectionRoot = args.Length >= 7 ? args[6] : Path.Combine(outputRoot, "projection");
        Directory.CreateDirectory(projectionRoot);
        var oldProjection = ProjectionModelBuilder.Build(oldDocument, policy);
        var newProjection = ProjectionModelBuilder.Build(newDocument, policy);
        var oldProjectionPath = Path.Combine(projectionRoot, $"{oldRevision}-projection.json");
        var newProjectionPath = Path.Combine(projectionRoot, $"{newRevision}-projection.json");
        File.WriteAllText(oldProjectionPath, oldProjection.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) + Environment.NewLine);
        File.WriteAllText(newProjectionPath, newProjection.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) + Environment.NewLine);
        var realProjectionChanges = ProjectionCompatibility.Compare(oldProjection, newProjection)
            .Concat(ProjectionModelBuilder.FindNameCollisions(oldDocument, policy))
            .Concat(ProjectionModelBuilder.FindNameCollisions(newDocument, policy));
        var projectionReport = CompatibilityReport.Create("P2.4-projection", oldRevision, newRevision, realProjectionChanges);
        var projectionJsonPath = Path.Combine(projectionRoot, $"{oldRevision}-to-{newRevision}.json");
        var projectionMarkdownPath = Path.Combine(projectionRoot, $"{oldRevision}-to-{newRevision}.md");
        File.WriteAllText(projectionJsonPath, JsonSerializer.Serialize(projectionReport, CompatibilityJson.Options) + Environment.NewLine);
        File.WriteAllText(projectionMarkdownPath, CompatibilityReportFormatter.ToMarkdown(projectionReport));
        Console.WriteLine($"PASS real projection diff {projectionReport.Changes.Count} changes -> {projectionJsonPath}");
    }
}

if (failures.Count > 0)
{
    foreach (var failure in failures) Console.Error.WriteLine($"FAIL {failure}");
    return 1;
}
Console.WriteLine("PASS P2.4 synthetic compatibility suite");
return 0;

static NormalizedDocument Base()
{
    var document = new NormalizedDocument { SourceRevision = "synthetic-old" };
    document.Operations.Add(Operation("things-list", "GET"));
    document.Schemas["String"] = new NormalizedSchema { Name = "String", Kind = "primitive", PrimitiveType = "string" };
    document.Schemas["Integer"] = new NormalizedSchema { Name = "Integer", Kind = "primitive", PrimitiveType = "integer" };
    document.Schemas["ThingKind"] = new NormalizedSchema { Name = "ThingKind", Kind = "enum", PrimitiveType = "string", Enum = ["active", "deleted"] };
    document.Schemas["Thing"] = new NormalizedSchema { Name = "Thing", Kind = "object", Properties = new(StringComparer.Ordinal)
    {
        ["name"] = new NormalizedProperty { Name = "name", Schema = "String", Required = true },
        ["kind"] = new NormalizedProperty { Name = "kind", Schema = "ThingKind", Required = false }
    }};
    document.Schemas["ThingRequest"] = new NormalizedSchema { Name = "ThingRequest", Kind = "object", Properties = new(StringComparer.Ordinal)
    {
        ["name"] = new NormalizedProperty { Name = "name", Schema = "String", Required = true }
    }};
    document.Schemas["ThingUnion"] = new NormalizedSchema { Name = "ThingUnion", Kind = "union", OneOf = ["ThingA", "ThingB"], Discriminator = new DiscriminatorModel { Property = "kind", Variants = [new DiscriminatorVariant { Schema = "ThingA", Value = "a" }, new DiscriminatorVariant { Schema = "ThingB", Value = "b" }] } };
    document.Schemas["Other"] = new NormalizedSchema { Name = "Other", Kind = "object" };
    return document;
}

static NormalizedOperation Operation(string id, string method)
{
    return new NormalizedOperation
    {
        OperationId = id, Method = method, PathTemplate = "/things", ResourcePath = ["zones", "things"],
        OperationSemantic = new OperationSemantic { Kind = "List" },
        ScopeBindings = [new ScopeBinding { ParameterName = "zone_id", ScopeType = "ZoneId", Role = "Parent" }],
        Parameters = [
            new NormalizedParameter { Name = "zone_id", Location = "path", Required = true, Schema = "String", NullPolicy = "reject-null" },
            new NormalizedParameter { Name = "page", Location = "query", Schema = "ThingKind", DefaultValue = JsonValue.Create("first"), Serialization = new SerializationModel { Style = "form", Explode = true } }
        ],
        RequestBody = new NormalizedRequestBody { Representations = [new RequestRepresentation { ContentType = "application/json", Schema = "ThingRequest" }] },
        Responses = [
            new NormalizedResponseCase { StatusSelector = new StatusSelector { Kind = "Exact", Value = "200" }, Representations = [new ResponseRepresentation { ContentType = "application/json", Schema = "Thing", EnvelopePolicy = "CloudflareResult", ParsingMode = "Json" }] },
            new NormalizedResponseCase { StatusSelector = new StatusSelector { Kind = "Exact", Value = "400" }, Representations = [new ResponseRepresentation { ContentType = "application/json", Schema = "Other" }] }
        ],
        Pagination = new PaginationModel { Strategy = "PageArray", RequestFields = ["page"], ResponseFields = ["result_info.page"], StopRule = "page >= total_pages" }
    };
}

static string Revision(string path) => Path.GetFileNameWithoutExtension(path).Replace("openapi", "revision", StringComparison.OrdinalIgnoreCase);
