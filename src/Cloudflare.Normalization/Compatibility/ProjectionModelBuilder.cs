using System.Text.Json.Nodes;

namespace Cloudflare.Normalization.Compatibility;

public static class ProjectionModelBuilder
{
    public sealed class ProjectionBuildOptions
    {
        public bool ResolveDeterministicParameterSetCollisions { get; init; }
    }

    public sealed record ProjectionParameterSetAssignment(
        string OperationId,
        string CmdletName,
        string BaseParameterSet,
        string ParameterSet,
        string ResolutionRule);

    public static IReadOnlyList<ApiChange> FindNameCollisions(NormalizedDocument document, JsonObject? projectionPolicy = null)
    {
        var changes = new List<ApiChange>();
        foreach (var operation in document.Operations.OrderBy(x => x.OperationId, StringComparer.Ordinal))
        {
            var policy = OperationPolicy(projectionPolicy, operation.OperationId);
            var groups = operation.Parameters
                .Select(parameter => new { ApiName = parameter.Name, ProjectedName = ProjectedName(policy, parameter.Name) })
                .GroupBy(x => x.ProjectedName, StringComparer.Ordinal)
                .Where(group => group.Select(x => x.ApiName).Distinct(StringComparer.Ordinal).Count() > 1)
                .OrderBy(group => group.Key, StringComparer.Ordinal);
            foreach (var group in groups)
            {
                changes.Add(new ApiChange
                {
                    Kind = ApiChangeKind.PowerShellNameCollision,
                    ResourcePath = string.Join('/', operation.ResourcePath),
                    OperationId = operation.OperationId,
                    Path = $"{operation.OperationId}.parameters",
                    OldValue = string.Join(';', group.Select(x => x.ApiName).OrderBy(x => x, StringComparer.Ordinal)),
                    NewValue = group.Key,
                    Evidence = "distinct normalized API parameter names collapse to one PowerShell parameter name",
                    ApiImpact = CompatibilityImpact.None,
                    SdkImpact = CompatibilityImpact.None,
                    PowerShellImpact = CompatibilityImpact.Breaking
                });
            }
        }
        return changes;
    }

    public static JsonObject Build(
        NormalizedDocument document,
        JsonObject? projectionPolicy = null,
        ProjectionBuildOptions? options = null)
    {
        var assignments = GetParameterSetAssignments(document, projectionPolicy, options);
        var cmdlets = new Dictionary<string, CmdletAccumulator>(StringComparer.Ordinal);
        foreach (var operation in document.Operations.OrderBy(x => x.OperationId, StringComparer.Ordinal))
        {
            var policy = OperationPolicy(projectionPolicy, operation.OperationId);
            var assignment = assignments.Single(x => x.OperationId == operation.OperationId);
            var parameterSet = assignment.ParameterSet;
            var cmdletName = assignment.CmdletName;
            if (!cmdlets.TryGetValue(cmdletName, out var cmdlet)) cmdlets[cmdletName] = cmdlet = new CmdletAccumulator(cmdletName);
            cmdlet.Add(operation, parameterSet, policy);
        }

        var result = new JsonArray();
        foreach (var cmdlet in cmdlets.Values.OrderBy(x => x.Name, StringComparer.Ordinal)) result.Add(cmdlet.ToJson());
        return new JsonObject { ["cmdlets"] = result };
    }

    public static IReadOnlyList<ProjectionParameterSetAssignment> GetParameterSetAssignments(
        NormalizedDocument document,
        JsonObject? projectionPolicy = null,
        ProjectionBuildOptions? options = null)
    {
        var candidates = document.Operations
            .OrderBy(x => x.OperationId, StringComparer.Ordinal)
            .Select(operation =>
            {
                var policy = OperationPolicy(projectionPolicy, operation.OperationId);
                var explicitParameterSet = String(policy?["parameterSet"]);
                return new Candidate(
                    operation,
                    String(policy?["verb"]) ?? Verb(operation),
                    String(policy?["noun"]) ?? Noun(operation),
                    explicitParameterSet ?? operation.OperationSemantic.Kind,
                    explicitParameterSet is not null);
            })
            .ToList();

        var assignments = candidates.ToDictionary(
            x => x.Operation.OperationId,
            x => new ProjectionParameterSetAssignment(
                x.Operation.OperationId,
                $"{x.Verb}-{x.Noun}",
                x.BaseParameterSet,
                x.BaseParameterSet,
                "None"),
            StringComparer.Ordinal);

        if (options?.ResolveDeterministicParameterSetCollisions != true) return assignments.Values.OrderBy(x => x.OperationId, StringComparer.Ordinal).ToArray();

        foreach (var group in candidates
                     .GroupBy(x => $"{x.Verb}-{x.Noun}\u001f{x.BaseParameterSet}", StringComparer.Ordinal)
                     .Where(x => x.Count() > 1)
                     .OrderBy(x => x.Key, StringComparer.Ordinal))
        {
            var members = group.OrderBy(x => x.Operation.OperationId, StringComparer.Ordinal).ToArray();
            // Explicit public policy is authoritative. A generic rule may not
            // silently rename an explicitly declared parameter set.
            if (members.Any(x => x.HasExplicitParameterSet)) continue;

            var scopeKeys = members.Select(x => ScopeKey(x.Operation)).ToArray();
            var scopeParameterSets = scopeKeys
                .Select(scopeKey => $"{members[0].BaseParameterSet}By{PowerShellNameCanonicalizer.ToPowerShellName(ScopeSuffix(scopeKey))}")
                .ToArray();
            if (scopeKeys.Distinct(StringComparer.Ordinal).Count() == members.Length && HasUniqueFinalIdentities(members, scopeParameterSets))
            {
                for (var index = 0; index < members.Length; index++)
                {
                    var member = members[index];
                    assignments[member.Operation.OperationId] = assignments[member.Operation.OperationId] with
                    {
                        ParameterSet = scopeParameterSets[index],
                        ResolutionRule = "ScopeKey"
                    };
                }
                continue;
            }

            var methods = members.Select(x => x.Operation.Method).ToArray();
            var methodParameterSets = methods
                .Select(method => $"{members[0].BaseParameterSet}ByHttp{PowerShellNameCanonicalizer.ToPowerShellName(method.ToLowerInvariant())}")
                .ToArray();
            if (methods.Distinct(StringComparer.Ordinal).Count() == members.Length && HasUniqueFinalIdentities(members, methodParameterSets))
            {
                for (var index = 0; index < members.Length; index++)
                {
                    var member = members[index];
                    assignments[member.Operation.OperationId] = assignments[member.Operation.OperationId] with
                    {
                        ParameterSet = methodParameterSets[index],
                        ResolutionRule = "HttpMethod"
                    };
                }
            }
        }

        return assignments.Values.OrderBy(x => x.OperationId, StringComparer.Ordinal).ToArray();
    }

    private static JsonObject? OperationPolicy(JsonObject? policy, string operationId)
        => policy?["operations"]?[operationId] as JsonObject;

    private static string Verb(NormalizedOperation operation) => operation.OperationSemantic.Kind switch
    {
        "List" or "Get" or "Download" => "Get",
        "Create" or "Upload" => "New",
        "Update" or "Edit" => "Set",
        "Delete" => "Remove",
        _ => "Invoke"
    };

    private static string Noun(NormalizedOperation operation)
        => string.Concat(operation.ResourcePath.Select(ToTitle));

    private static string? Rename(JsonObject? policy, string apiName)
        => (policy?["parameterRenames"] as JsonObject)?[apiName] is JsonValue value && value.TryGetValue<string>(out var name) ? name : null;

    private static string ProjectedName(JsonObject? policy, string apiName)
        => Rename(policy, apiName) ?? ToTitle(apiName);

    private static string? String(JsonNode? node)
        => node is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;

    private static string ScopeKey(NormalizedOperation operation)
    {
        var scopes = operation.ScopeBindings
            .OrderBy(x => x.ScopeType, StringComparer.Ordinal)
            .ThenBy(x => x.Role, StringComparer.Ordinal)
            .ThenBy(x => x.ParameterName, StringComparer.Ordinal)
            .Select(x => $"{x.ScopeType}:{x.Role}:{x.ParameterName}")
            .ToArray();
        return scopes.Length == 0 ? "Unscoped" : string.Join('+', scopes);
    }

    private static string ScopeSuffix(string scopeKey)
    {
        var values = scopeKey.Split('+', StringSplitOptions.RemoveEmptyEntries)
            .Select(value => string.Join("", value.Split(':', StringSplitOptions.RemoveEmptyEntries).Select(ToTitle)))
            .ToArray();
        return values.Length == 0 ? "Unscoped" : string.Join("And", values);
    }

    private static string ToTitle(string value)
        => string.Concat(value.Split(['-', '_'], StringSplitOptions.RemoveEmptyEntries).Select(x => x.Length == 0 ? string.Empty : char.ToUpperInvariant(x[0]) + x[1..]));

    private static bool HasUniqueFinalIdentities(IReadOnlyList<Candidate> members, IReadOnlyList<string> parameterSets)
        => PowerShellNameCanonicalizer.AreUnique(members.Select((member, index) => $"{member.Verb}-{member.Noun}\u001f{parameterSets[index]}"));

    private sealed record Candidate(
        NormalizedOperation Operation,
        string Verb,
        string Noun,
        string BaseParameterSet,
        bool HasExplicitParameterSet);

    private sealed class CmdletAccumulator(string name)
    {
        private readonly Dictionary<string, ParameterAccumulator> _parameters = new(StringComparer.Ordinal);
        private readonly List<JsonObject> _parameterSets = [];
        private readonly List<string> _operationIds = [];
        private string? _outputType;
        private bool _supportsShouldProcess;
        private string _confirmImpact = "None";
        private string? _pagingBehavior;

        public string Name { get; } = name;

        public void Add(NormalizedOperation operation, string parameterSet, JsonObject? policy)
        {
            _operationIds.Add(operation.OperationId);
            var required = new JsonArray();
            foreach (var parameter in operation.Parameters.OrderBy(x => x.Location, StringComparer.Ordinal).ThenBy(x => x.Name, StringComparer.Ordinal))
            {
                var projectedName = ProjectedName(policy, parameter.Name);
                if (!_parameters.TryGetValue(projectedName, out var accumulator)) _parameters[projectedName] = accumulator = new ParameterAccumulator(projectedName);
                accumulator.Add(parameter, parameterSet, projectedName);
                if (parameter.Required) required.Add(projectedName);
            }
            _parameterSets.Add(new JsonObject
            {
                ["name"] = parameterSet,
                ["required"] = required,
                ["operationId"] = operation.OperationId
            });

            var explicitOutput = String(policy?["outputType"]);
            if (!string.IsNullOrWhiteSpace(explicitOutput)) _outputType = explicitOutput;
            _supportsShouldProcess |= policy?["supportsShouldProcess"]?.GetValue<bool>() ?? Mutates(operation);
            _confirmImpact = MaxImpact(_confirmImpact, String(policy?["confirmImpact"]) ?? DefaultImpact(operation));
            if (operation.Pagination is not null) _pagingBehavior = String(policy?["paging"]) ?? "shared-runtime";
        }

        public JsonObject ToJson()
        {
            var parameters = new JsonArray();
            foreach (var parameter in _parameters.Values.OrderBy(x => x.Name, StringComparer.Ordinal)) parameters.Add(parameter.ToJson());
            var sets = new JsonArray();
            foreach (var set in _parameterSets.OrderBy(x => String(x["name"]) ?? string.Empty, StringComparer.Ordinal)) sets.Add(set);
            var operationIds = new JsonArray();
            foreach (var operationId in _operationIds.OrderBy(x => x, StringComparer.Ordinal)) operationIds.Add(operationId);
            return new JsonObject
            {
                ["cmdletName"] = Name,
                ["operationIds"] = operationIds,
                ["parameterSets"] = sets,
                ["parameters"] = parameters,
                ["outputType"] = _outputType ?? "System.Management.Automation.PSObject",
                ["supportsShouldProcess"] = _supportsShouldProcess,
                ["confirmImpact"] = _confirmImpact,
                ["pagingBehavior"] = _pagingBehavior is null ? null : JsonValue.Create(_pagingBehavior)
            };
        }

        private static string? Rename(JsonObject? policy, string apiName)
            => (policy?["parameterRenames"] as JsonObject)?[apiName] is JsonValue value && value.TryGetValue<string>(out var name) ? name : null;

        private static string ProjectedName(JsonObject? policy, string apiName)
            => Rename(policy, apiName) ?? ToTitle(apiName);

        private static bool Mutates(NormalizedOperation operation)
            => operation.Method is "POST" or "PUT" or "PATCH" or "DELETE";

        private static string DefaultImpact(NormalizedOperation operation)
            => operation.Method == "DELETE" ? "High" : Mutates(operation) ? "Medium" : "None";

        private static string MaxImpact(string left, string right)
        {
            var rank = new Dictionary<string, int>(StringComparer.Ordinal) { ["None"] = 0, ["Low"] = 1, ["Medium"] = 2, ["High"] = 3 };
            return rank.GetValueOrDefault(right, 0) > rank.GetValueOrDefault(left, 0) ? right : left;
        }
    }

    private sealed class ParameterAccumulator(string name)
    {
        private readonly HashSet<string> _requiredIn = new(StringComparer.Ordinal);
        private bool _valueFromPipeline;
        private bool _valueFromPipelineByPropertyName;

        public string Name { get; } = name;

        public void Add(NormalizedParameter parameter, string parameterSet, string projectedName)
        {
            if (parameter.Required) _requiredIn.Add(parameterSet);
            _valueFromPipeline |= parameter.Location == "path" && parameter.IsPrimaryResourceId;
            _valueFromPipelineByPropertyName |= parameter.Location == "path";
        }

        public JsonObject ToJson()
        {
            var requiredIn = new JsonArray();
            foreach (var value in _requiredIn.OrderBy(x => x, StringComparer.Ordinal)) requiredIn.Add(value);
            return new JsonObject
            {
                ["name"] = Name,
                ["requiredIn"] = requiredIn,
                ["valueFromPipeline"] = _valueFromPipeline,
                ["valueFromPipelineByPropertyName"] = _valueFromPipelineByPropertyName
            };
        }
    }
}
