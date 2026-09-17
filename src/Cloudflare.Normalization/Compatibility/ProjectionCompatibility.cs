using System.Text.Json.Nodes;

namespace Cloudflare.Normalization.Compatibility;

public static class ProjectionCompatibility
{
    public static IReadOnlyList<ApiChange> Compare(JsonNode oldProjection, JsonNode newProjection)
    {
        var changes = new List<ApiChange>();
        var oldCmdlets = Cmdlets(oldProjection);
        var newCmdlets = Cmdlets(newProjection);
        foreach (var name in oldCmdlets.Keys.Union(newCmdlets.Keys, StringComparer.Ordinal).OrderBy(x => x, StringComparer.Ordinal))
        {
            if (!oldCmdlets.TryGetValue(name, out var oldCmdlet))
            {
                changes.Add(Change(ApiChangeKind.CmdletAdded, name, $"cmdlets[{name}]", "missing", "present", "projection cmdlet added", CompatibilityImpact.NonBreaking));
                continue;
            }
            if (!newCmdlets.TryGetValue(name, out var newCmdlet))
            {
                changes.Add(Change(ApiChangeKind.CmdletRemoved, name, $"cmdlets[{name}]", "present", "missing", "projection cmdlet removed", CompatibilityImpact.Breaking));
                continue;
            }
            CompareCmdlet(name, oldCmdlet, newCmdlet, changes);
        }
        return changes.OrderBy(x => x.ResourcePath, StringComparer.Ordinal).ThenBy(x => x.Path, StringComparer.Ordinal).ThenBy(x => x.Kind).ToArray();
    }

    public static IReadOnlyList<ApiChange> FindPowerShellNameCollisions(IEnumerable<string> apiNames, string resourcePath = "", string? operationId = null)
    {
        var groups = apiNames
            .Select(name => new { Original = name, Canonical = PowerShellNameCanonicalizer.ToPowerShellName(name) })
            .GroupBy(x => PowerShellNameCanonicalizer.ToIdentityKey(x.Canonical), StringComparer.Ordinal)
            .Where(x => x.Select(v => v.Original).Distinct(StringComparer.Ordinal).Count() > 1)
            .OrderBy(x => x.Key, StringComparer.Ordinal);
        return groups.Select(group => new ApiChange
        {
            Kind = ApiChangeKind.PowerShellNameCollision,
            ResourcePath = resourcePath,
            OperationId = operationId,
            Path = "parameters",
            OldValue = string.Join(';', group.Select(x => x.Original).OrderBy(x => x, StringComparer.Ordinal)),
            NewValue = group.Select(x => x.Canonical).OrderBy(x => x, StringComparer.Ordinal).First(),
            Evidence = "distinct normalized API names collapse to one final PowerShell parameter name",
            ApiImpact = CompatibilityImpact.None,
            SdkImpact = CompatibilityImpact.None,
            PowerShellImpact = CompatibilityImpact.Breaking
        }).ToArray();
    }

    private static void CompareCmdlet(string name, JsonObject oldCmdlet, JsonObject newCmdlet, List<ApiChange> changes)
    {
        var oldSets = Values(oldCmdlet["parameterSets"]);
        var newSets = Values(newCmdlet["parameterSets"]);
        if (!oldSets.SequenceEqual(newSets, StringComparer.Ordinal)) changes.Add(Change(ApiChangeKind.PowerShellParameterSetChanged, name, $"cmdlets[{name}].parameterSets", Join(oldSets), Join(newSets), "PowerShell parameter-set names", CompatibilityImpact.Breaking));
        var oldParameters = Objects(oldCmdlet["parameters"]).ToDictionary(x => String(x["name"]), StringComparer.Ordinal);
        var newParameters = Objects(newCmdlet["parameters"]).ToDictionary(x => String(x["name"]), StringComparer.Ordinal);
        foreach (var parameter in oldParameters.Keys.Union(newParameters.Keys, StringComparer.Ordinal).OrderBy(x => x, StringComparer.Ordinal))
        {
            if (!oldParameters.TryGetValue(parameter, out var oldValue)) { changes.Add(Change(ApiChangeKind.PowerShellParameterAdded, name, $"cmdlets[{name}].parameters[{parameter}]", "missing", "present", "PowerShell parameter added", CompatibilityImpact.NonBreaking)); continue; }
            if (!newParameters.TryGetValue(parameter, out var newValue)) { changes.Add(Change(ApiChangeKind.PowerShellParameterRemoved, name, $"cmdlets[{name}].parameters[{parameter}]", "present", "missing", "PowerShell parameter removed", CompatibilityImpact.Breaking)); continue; }
            var oldRequired = Join(Values(oldValue["requiredIn"])); var newRequired = Join(Values(newValue["requiredIn"]));
            if (!string.Equals(oldRequired, newRequired, StringComparison.Ordinal)) changes.Add(Change(ApiChangeKind.PowerShellParameterBecameMandatory, name, $"cmdlets[{name}].parameters[{parameter}].requiredIn", oldRequired, newRequired, "PowerShell required parameter-set membership", CompatibilityImpact.Breaking));
            var oldPipeline = $"{Bool(oldValue["valueFromPipeline"])}:{Bool(oldValue["valueFromPipelineByPropertyName"])}"; var newPipeline = $"{Bool(newValue["valueFromPipeline"])}:{Bool(newValue["valueFromPipelineByPropertyName"])}";
            if (!string.Equals(oldPipeline, newPipeline, StringComparison.Ordinal)) changes.Add(Change(ApiChangeKind.PipelineBindingChanged, name, $"cmdlets[{name}].parameters[{parameter}].pipeline", oldPipeline, newPipeline, "PowerShell pipeline binding", CompatibilityImpact.Behavioral));
        }
        CompareScalar(ApiChangeKind.OutputTypeChanged, name, oldCmdlet, newCmdlet, "outputType", changes, CompatibilityImpact.PotentiallyBreaking);
        CompareScalar(ApiChangeKind.ShouldProcessChanged, name, oldCmdlet, newCmdlet, "supportsShouldProcess", changes, CompatibilityImpact.Breaking);
        CompareScalar(ApiChangeKind.ConfirmImpactChanged, name, oldCmdlet, newCmdlet, "confirmImpact", changes, CompatibilityImpact.Behavioral);
        CompareScalar(ApiChangeKind.PagingBehaviorChanged, name, oldCmdlet, newCmdlet, "pagingBehavior", changes, CompatibilityImpact.Breaking);
    }

    private static void CompareScalar(ApiChangeKind kind, string name, JsonObject oldValue, JsonObject newValue, string property, List<ApiChange> changes, CompatibilityImpact impact)
    {
        var oldText = Value(oldValue[property]); var newText = Value(newValue[property]);
        if (!string.Equals(oldText, newText, StringComparison.Ordinal)) changes.Add(Change(kind, name, $"cmdlets[{name}].{property}", oldText, newText, $"PowerShell projection {property}", impact));
    }

    private static ApiChange Change(ApiChangeKind kind, string name, string path, string oldValue, string newValue, string evidence, CompatibilityImpact powerShell)
        => new() { Kind = kind, ResourcePath = string.Empty, OperationId = name, Path = path, OldValue = oldValue, NewValue = newValue, Evidence = evidence, ApiImpact = CompatibilityImpact.None, SdkImpact = CompatibilityImpact.None, PowerShellImpact = powerShell };

    private static Dictionary<string, JsonObject> Cmdlets(JsonNode node) => Objects(node["cmdlets"]).ToDictionary(x => String(x["cmdletName"]), StringComparer.Ordinal);
    private static IEnumerable<JsonObject> Objects(JsonNode? node) => node is JsonArray array ? array.OfType<JsonObject>() : [];
    private static string[] Values(JsonNode? node) => node is JsonArray array ? array.Select(Value).OrderBy(x => x, StringComparer.Ordinal).ToArray() : [];
    private static string Value(JsonNode? node) => node is null ? "<none>" : node.ToJsonString();
    private static string String(JsonNode? node) => node is JsonValue value && value.TryGetValue<string>(out var text) ? text : Value(node);
    private static string Bool(JsonNode? node) => node is JsonValue value && value.TryGetValue<bool>(out var flag) ? flag.ToString() : Value(node);
    private static string Join(IEnumerable<string> values) => string.Join(';', values);
}
