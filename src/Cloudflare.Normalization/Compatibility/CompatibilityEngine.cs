using System.Text.Json;
using System.Text.Json.Nodes;

namespace Cloudflare.Normalization.Compatibility;

public static class CompatibilityEngine
{
    public static CompatibilityReport Compare(NormalizedDocument oldDocument, NormalizedDocument newDocument)
    {
        var changes = new List<ApiChange>();
        var oldOperations = oldDocument.Operations.ToDictionary(x => x.OperationId, StringComparer.Ordinal);
        var newOperations = newDocument.Operations.ToDictionary(x => x.OperationId, StringComparer.Ordinal);

        foreach (var operationId in oldOperations.Keys.Union(newOperations.Keys, StringComparer.Ordinal).OrderBy(x => x, StringComparer.Ordinal))
        {
            if (!oldOperations.TryGetValue(operationId, out var oldOperation))
            {
                Add(changes, ApiChangeKind.OperationAdded, newOperations[operationId], null, $"operations[{operationId}]", "missing", "present", "operation exists only in new normalized model", CompatibilityImpact.NonBreaking, CompatibilityImpact.NonBreaking, CompatibilityImpact.NonBreaking);
                continue;
            }
            if (!newOperations.TryGetValue(operationId, out var newOperation))
            {
                Add(changes, ApiChangeKind.OperationRemoved, oldOperation, null, $"operations[{operationId}]", "present", "missing", "operation exists only in old normalized model", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
                continue;
            }
            CompareOperation(oldDocument, newDocument, oldOperation, newOperation, changes);
        }

        CompareSchemas(oldDocument, newDocument, changes);
        return CompatibilityReport.Create("P2.4", oldDocument.SourceRevision ?? string.Empty, newDocument.SourceRevision ?? string.Empty, changes);
    }

    private static void CompareOperation(NormalizedDocument oldDocument, NormalizedDocument newDocument, NormalizedOperation oldOperation, NormalizedOperation newOperation, List<ApiChange> changes)
    {
        var resource = Resource(oldOperation);
        if (!Equal(oldOperation.Method, newOperation.Method)) Add(changes, ApiChangeKind.HttpMethodChanged, oldOperation, null, $"{oldOperation.OperationId}.method", oldOperation.Method, newOperation.Method, "normalized operation method", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
        if (!Equal(oldOperation.PathTemplate, newOperation.PathTemplate)) Add(changes, ApiChangeKind.PathChanged, oldOperation, null, $"{oldOperation.OperationId}.path", oldOperation.PathTemplate, newOperation.PathTemplate, "normalized operation path template", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
        if (!SequenceEqual(oldOperation.ResourcePath, newOperation.ResourcePath)) Add(changes, ApiChangeKind.ResourcePathChanged, oldOperation, null, $"{oldOperation.OperationId}.resourcePath", Join(oldOperation.ResourcePath), Join(newOperation.ResourcePath), "normalized resource path", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
        if (!Equal(oldOperation.OperationSemantic.Kind, newOperation.OperationSemantic.Kind)) Add(changes, ApiChangeKind.SemanticKindChanged, oldOperation, null, $"{oldOperation.OperationId}.semantic.kind", oldOperation.OperationSemantic.Kind, newOperation.OperationSemantic.Kind, "normalized operation semantic", CompatibilityImpact.Behavioral, CompatibilityImpact.PotentiallyBreaking, CompatibilityImpact.PotentiallyBreaking);

        CompareScopes(oldOperation, newOperation, changes);
        CompareParameters(oldDocument, newDocument, oldOperation, newOperation, changes);
        CompareRequestBody(oldDocument, newDocument, oldOperation, newOperation, changes);
        CompareResponses(oldDocument, newDocument, oldOperation, newOperation, changes);
        ComparePagination(oldOperation, newOperation, changes);
        _ = resource;
    }

    private static void CompareScopes(NormalizedOperation oldOperation, NormalizedOperation newOperation, List<ApiChange> changes)
    {
        var oldBindings = oldOperation.ScopeBindings.ToDictionary(x => x.ParameterName, StringComparer.Ordinal);
        var newBindings = newOperation.ScopeBindings.ToDictionary(x => x.ParameterName, StringComparer.Ordinal);
        foreach (var name in oldBindings.Keys.Union(newBindings.Keys, StringComparer.Ordinal).OrderBy(x => x, StringComparer.Ordinal))
        {
            if (!oldBindings.TryGetValue(name, out var oldBinding))
            {
                var newBinding = newBindings[name];
                Add(changes, ApiChangeKind.ScopeBindingAdded, newOperation, null, $"{newOperation.OperationId}.scopeBindings[{name}]", "missing", Signature(newBinding), "scope binding added", CompatibilityImpact.Behavioral, CompatibilityImpact.PotentiallyBreaking, CompatibilityImpact.Breaking);
            }
            else if (!newBindings.TryGetValue(name, out var newBinding))
                Add(changes, ApiChangeKind.ScopeBindingRemoved, oldOperation, null, $"{oldOperation.OperationId}.scopeBindings[{name}]", Signature(oldBinding), "missing", "scope binding removed", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
            else if (!Equal(Signature(oldBinding), Signature(newBinding)))
                Add(changes, ApiChangeKind.ScopeBindingRoleChanged, oldOperation, null, $"{oldOperation.OperationId}.scopeBindings[{name}]", Signature(oldBinding), Signature(newBinding), "scope binding type/role changed", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
        }
    }

    private static void CompareParameters(NormalizedDocument oldDocument, NormalizedDocument newDocument, NormalizedOperation oldOperation, NormalizedOperation newOperation, List<ApiChange> changes)
    {
        var oldByName = oldOperation.Parameters.ToDictionary(x => x.Name, StringComparer.Ordinal);
        var newByName = newOperation.Parameters.ToDictionary(x => x.Name, StringComparer.Ordinal);
        foreach (var name in oldByName.Keys.Union(newByName.Keys, StringComparer.Ordinal).OrderBy(x => x, StringComparer.Ordinal))
        {
            if (!oldByName.TryGetValue(name, out var oldParameter))
            {
                var added = newByName[name];
                var impact = added.Required ? CompatibilityImpact.Breaking : CompatibilityImpact.NonBreaking;
                Add(changes, ApiChangeKind.ParameterAdded, newOperation, null, $"{newOperation.OperationId}.parameters[{name}]", "missing", Signature(added), "normalized parameter added", impact, impact, impact);
                continue;
            }
            if (!newByName.TryGetValue(name, out var newParameter))
            {
                Add(changes, ApiChangeKind.ParameterRemoved, oldOperation, null, $"{oldOperation.OperationId}.parameters[{name}]", Signature(oldParameter), "missing", "normalized parameter removed", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
                continue;
            }
            if (!Equal(oldParameter.Location, newParameter.Location)) Add(changes, ApiChangeKind.ParameterLocationChanged, oldOperation, null, $"{oldOperation.OperationId}.parameters[{name}].location", oldParameter.Location, newParameter.Location, "normalized parameter location", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
            if (!oldParameter.Required && newParameter.Required) Add(changes, ApiChangeKind.ParameterBecameRequired, oldOperation, null, $"{oldOperation.OperationId}.parameters[{name}].required", "false", "true", "optional parameter became required", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
            if (oldParameter.Required && !newParameter.Required) Add(changes, ApiChangeKind.ParameterBecameOptional, oldOperation, null, $"{oldOperation.OperationId}.parameters[{name}].required", "true", "false", "required parameter became optional", CompatibilityImpact.NonBreaking, CompatibilityImpact.NonBreaking, CompatibilityImpact.NonBreaking);
            if (oldParameter.IsPrimaryResourceId != newParameter.IsPrimaryResourceId) Add(changes, ApiChangeKind.PrimaryResourceIdChanged, oldOperation, null, $"{oldOperation.OperationId}.parameters[{name}].isPrimaryResourceId", oldParameter.IsPrimaryResourceId.ToString(), newParameter.IsPrimaryResourceId.ToString(), "normalized primary resource identifier classification", CompatibilityImpact.Behavioral, CompatibilityImpact.PotentiallyBreaking, CompatibilityImpact.Breaking);
            if (!Equal(SchemaSignature(oldDocument, oldParameter.Schema), SchemaSignature(newDocument, newParameter.Schema))) Add(changes, ApiChangeKind.ParameterTypeChanged, oldOperation, null, $"{oldOperation.OperationId}.parameters[{name}].schema", SchemaSignature(oldDocument, oldParameter.Schema), SchemaSignature(newDocument, newParameter.Schema), "normalized parameter schema signature", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
            if (oldParameter.AllowsNull != newParameter.AllowsNull || !Equal(oldParameter.NullPolicy, newParameter.NullPolicy)) Add(changes, ApiChangeKind.ParameterNullabilityChanged, oldOperation, null, $"{oldOperation.OperationId}.parameters[{name}].nullability", $"allowsNull={oldParameter.AllowsNull};policy={oldParameter.NullPolicy}", $"allowsNull={newParameter.AllowsNull};policy={newParameter.NullPolicy}", "normalized parameter nullability/presence policy", CompatibilityImpact.Behavioral, CompatibilityImpact.PotentiallyBreaking, CompatibilityImpact.PotentiallyBreaking);
            if (!Equal(Json(oldParameter.DefaultValue), Json(newParameter.DefaultValue))) Add(changes, ApiChangeKind.DefaultChanged, oldOperation, null, $"{oldOperation.OperationId}.parameters[{name}].default", Json(oldParameter.DefaultValue), Json(newParameter.DefaultValue), "normalized parameter default", CompatibilityImpact.Behavioral, CompatibilityImpact.Behavioral, CompatibilityImpact.Behavioral);
            if (!Equal(Serialization(oldParameter.Serialization), Serialization(newParameter.Serialization))) Add(changes, ApiChangeKind.ParameterSerializationChanged, oldOperation, null, $"{oldOperation.OperationId}.parameters[{name}].serialization", Serialization(oldParameter.Serialization), Serialization(newParameter.Serialization), "normalized parameter serialization", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
        }
    }

    private static void CompareRequestBody(NormalizedDocument oldDocument, NormalizedDocument newDocument, NormalizedOperation oldOperation, NormalizedOperation newOperation, List<ApiChange> changes)
    {
        if (oldOperation.RequestBody is null && newOperation.RequestBody is null) return;
        if (oldOperation.RequestBody is null)
        {
            Add(changes, ApiChangeKind.RequestBodyPresenceChanged, newOperation, null, $"{newOperation.OperationId}.requestBody", "absent", "present", "normalized request body became present", CompatibilityImpact.Behavioral, CompatibilityImpact.PotentiallyBreaking, CompatibilityImpact.Breaking);
            return;
        }
        if (newOperation.RequestBody is null)
        {
            Add(changes, ApiChangeKind.RequestBodyPresenceChanged, oldOperation, null, $"{oldOperation.OperationId}.requestBody", "present", "absent", "normalized request body became absent", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
            return;
        }

        if (oldOperation.RequestBody.Required != newOperation.RequestBody.Required)
        {
            var becameRequired = !oldOperation.RequestBody.Required && newOperation.RequestBody.Required;
            Add(changes, ApiChangeKind.RequestBodyRequiredChanged, oldOperation, null, $"{oldOperation.OperationId}.requestBody.required", oldOperation.RequestBody.Required.ToString(), newOperation.RequestBody.Required.ToString(), "normalized request body requiredness", becameRequired ? CompatibilityImpact.Breaking : CompatibilityImpact.NonBreaking, becameRequired ? CompatibilityImpact.Breaking : CompatibilityImpact.NonBreaking, becameRequired ? CompatibilityImpact.Breaking : CompatibilityImpact.NonBreaking);
        }
        var oldPresence = $"{oldOperation.RequestBody.Presence}:{oldOperation.RequestBody.EffectivePresence}";
        var newPresence = $"{newOperation.RequestBody.Presence}:{newOperation.RequestBody.EffectivePresence}";
        if (!Equal(oldPresence, newPresence)) Add(changes, ApiChangeKind.RequestBodyPresenceChanged, oldOperation, null, $"{oldOperation.OperationId}.requestBody.presence", oldPresence, newPresence, "normalized request body presence policy", CompatibilityImpact.Behavioral, CompatibilityImpact.PotentiallyBreaking, CompatibilityImpact.Breaking);

        var oldRepresentations = oldOperation.RequestBody.Representations.ToDictionary(x => x.ContentType, StringComparer.OrdinalIgnoreCase);
        var newRepresentations = newOperation.RequestBody.Representations.ToDictionary(x => x.ContentType, StringComparer.OrdinalIgnoreCase);
        foreach (var contentType in oldRepresentations.Keys.Union(newRepresentations.Keys, StringComparer.OrdinalIgnoreCase).OrderBy(x => x, StringComparer.OrdinalIgnoreCase))
        {
            if (!oldRepresentations.TryGetValue(contentType, out var oldRepresentation))
            {
                Add(changes, ApiChangeKind.RequestContentTypeAdded, newOperation, null, $"{newOperation.OperationId}.requestBody.contentType", "missing", contentType, "normalized request representation added", CompatibilityImpact.NonBreaking, CompatibilityImpact.NonBreaking, CompatibilityImpact.NonBreaking);
                continue;
            }
            if (!newRepresentations.TryGetValue(contentType, out var newRepresentation))
            {
                Add(changes, ApiChangeKind.RequestContentTypeRemoved, oldOperation, null, $"{oldOperation.OperationId}.requestBody.contentType", contentType, "missing", "normalized request representation removed", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
                continue;
            }
            if (!Equal(SchemaSignature(oldDocument, oldRepresentation.Schema), SchemaSignature(newDocument, newRepresentation.Schema))) Add(changes, ApiChangeKind.RequestSchemaChanged, oldOperation, null, $"{oldOperation.OperationId}.requestBody.representations[{contentType}].schema", SchemaSignature(oldDocument, oldRepresentation.Schema), SchemaSignature(newDocument, newRepresentation.Schema), "normalized request representation schema", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
        }
    }

    private static void CompareResponses(NormalizedDocument oldDocument, NormalizedDocument newDocument, NormalizedOperation oldOperation, NormalizedOperation newOperation, List<ApiChange> changes)
    {
        var oldResponses = oldOperation.Responses.ToDictionary(x => Selector(x.StatusSelector), StringComparer.Ordinal);
        var newResponses = newOperation.Responses.ToDictionary(x => Selector(x.StatusSelector), StringComparer.Ordinal);
        foreach (var selector in oldResponses.Keys.Union(newResponses.Keys, StringComparer.Ordinal).OrderBy(x => x, StringComparer.Ordinal))
        {
            if (!oldResponses.TryGetValue(selector, out var oldResponse))
            {
                var added = newResponses[selector];
                Add(changes, IsError(added.StatusSelector) ? ApiChangeKind.ErrorResponseChanged : ApiChangeKind.SuccessStatusAdded, newOperation, null, $"{newOperation.OperationId}.responses[{selector}]", "missing", selector, "normalized response status added", CompatibilityImpact.NonBreaking, CompatibilityImpact.NonBreaking, CompatibilityImpact.NonBreaking);
                continue;
            }
            if (!newResponses.TryGetValue(selector, out var newResponse))
            {
                Add(changes, IsError(oldResponse.StatusSelector) ? ApiChangeKind.ErrorResponseChanged : ApiChangeKind.SuccessStatusRemoved, oldOperation, null, $"{oldOperation.OperationId}.responses[{selector}]", selector, "missing", "normalized response status removed", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
                continue;
            }
            var oldRepresentations = oldResponse.Representations.ToDictionary(x => x.ContentType, StringComparer.OrdinalIgnoreCase);
            var newRepresentations = newResponse.Representations.ToDictionary(x => x.ContentType, StringComparer.OrdinalIgnoreCase);
            foreach (var contentType in oldRepresentations.Keys.Union(newRepresentations.Keys, StringComparer.OrdinalIgnoreCase).OrderBy(x => x, StringComparer.OrdinalIgnoreCase))
            {
                if (!oldRepresentations.TryGetValue(contentType, out var oldRepresentation))
                {
                    Add(changes, IsError(newResponse.StatusSelector) ? ApiChangeKind.ErrorResponseChanged : ApiChangeKind.ResponseContentTypeAdded, newOperation, null, $"{newOperation.OperationId}.responses[{selector}].contentType", "missing", contentType, "normalized response representation added", CompatibilityImpact.NonBreaking, CompatibilityImpact.NonBreaking, CompatibilityImpact.NonBreaking);
                    continue;
                }
                if (!newRepresentations.TryGetValue(contentType, out var newRepresentation))
                {
                    Add(changes, IsError(oldResponse.StatusSelector) ? ApiChangeKind.ErrorResponseChanged : ApiChangeKind.ResponseContentTypeRemoved, oldOperation, null, $"{oldOperation.OperationId}.responses[{selector}].contentType", contentType, "missing", "normalized response representation removed", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
                    continue;
                }
                if (!Equal(oldRepresentation.EnvelopePolicy, newRepresentation.EnvelopePolicy)) Add(changes, ApiChangeKind.EnvelopePolicyChanged, oldOperation, null, $"{oldOperation.OperationId}.responses[{selector}].representations[{contentType}].envelopePolicy", oldRepresentation.EnvelopePolicy, newRepresentation.EnvelopePolicy, "normalized response envelope policy", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
                if (!Equal(oldRepresentation.ParsingMode, newRepresentation.ParsingMode)) Add(changes, ApiChangeKind.ParsingModeChanged, oldOperation, null, $"{oldOperation.OperationId}.responses[{selector}].representations[{contentType}].parsingMode", oldRepresentation.ParsingMode, newRepresentation.ParsingMode, "normalized response parsing mode", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
                if (!Equal(SchemaSignature(oldDocument, oldRepresentation.Schema), SchemaSignature(newDocument, newRepresentation.Schema))) Add(changes, ApiChangeKind.ResultSchemaChanged, oldOperation, null, $"{oldOperation.OperationId}.responses[{selector}].representations[{contentType}].schema", SchemaSignature(oldDocument, oldRepresentation.Schema), SchemaSignature(newDocument, newRepresentation.Schema), "normalized response schema signature", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
            }
        }
    }

    private static void ComparePagination(NormalizedOperation oldOperation, NormalizedOperation newOperation, List<ApiChange> changes)
    {
        if (oldOperation.Pagination is null && newOperation.Pagination is not null) { Add(changes, ApiChangeKind.PaginationAdded, newOperation, null, $"{newOperation.OperationId}.pagination", "absent", newOperation.Pagination.Strategy, "normalized pagination added", CompatibilityImpact.Behavioral, CompatibilityImpact.Behavioral, CompatibilityImpact.Behavioral); return; }
        if (oldOperation.Pagination is not null && newOperation.Pagination is null) { Add(changes, ApiChangeKind.PaginationRemoved, oldOperation, null, $"{oldOperation.OperationId}.pagination", oldOperation.Pagination.Strategy, "absent", "normalized pagination removed", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking); return; }
        if (oldOperation.Pagination is null || newOperation.Pagination is null) return;
        if (!Equal(oldOperation.Pagination.Strategy, newOperation.Pagination.Strategy)) Add(changes, ApiChangeKind.PaginationStrategyChanged, oldOperation, null, $"{oldOperation.OperationId}.pagination.strategy", oldOperation.Pagination.Strategy, newOperation.Pagination.Strategy, "normalized pagination strategy", CompatibilityImpact.Behavioral, CompatibilityImpact.PotentiallyBreaking, CompatibilityImpact.Breaking);
        if (!SequenceEqual(oldOperation.Pagination.RequestFields, newOperation.Pagination.RequestFields)) Add(changes, ApiChangeKind.RequestPagingFieldChanged, oldOperation, null, $"{oldOperation.OperationId}.pagination.requestFields", Join(oldOperation.Pagination.RequestFields), Join(newOperation.Pagination.RequestFields), "normalized pagination request fields", CompatibilityImpact.Behavioral, CompatibilityImpact.PotentiallyBreaking, CompatibilityImpact.Breaking);
        if (!SequenceEqual(oldOperation.Pagination.ResponseFields, newOperation.Pagination.ResponseFields)) Add(changes, ApiChangeKind.ResponsePagingFieldChanged, oldOperation, null, $"{oldOperation.OperationId}.pagination.responseFields", Join(oldOperation.Pagination.ResponseFields), Join(newOperation.Pagination.ResponseFields), "normalized pagination response fields", CompatibilityImpact.Behavioral, CompatibilityImpact.PotentiallyBreaking, CompatibilityImpact.Breaking);
        if (!Equal(oldOperation.Pagination.NextPageRule, newOperation.Pagination.NextPageRule)) Add(changes, ApiChangeKind.NextPageRuleChanged, oldOperation, null, $"{oldOperation.OperationId}.pagination.nextPageRule", oldOperation.Pagination.NextPageRule, newOperation.Pagination.NextPageRule, "normalized pagination next-page rule", CompatibilityImpact.Behavioral, CompatibilityImpact.PotentiallyBreaking, CompatibilityImpact.Breaking);
        if (!Equal(oldOperation.Pagination.StopRule, newOperation.Pagination.StopRule)) Add(changes, ApiChangeKind.StopRuleChanged, oldOperation, null, $"{oldOperation.OperationId}.pagination.stopRule", oldOperation.Pagination.StopRule, newOperation.Pagination.StopRule, "normalized pagination stop rule", CompatibilityImpact.Behavioral, CompatibilityImpact.PotentiallyBreaking, CompatibilityImpact.Breaking);
    }

    private static void CompareSchemas(NormalizedDocument oldDocument, NormalizedDocument newDocument, List<ApiChange> changes)
    {
        var names = oldDocument.Schemas.Keys.Union(newDocument.Schemas.Keys, StringComparer.Ordinal).OrderBy(x => x, StringComparer.Ordinal);
        var contexts = SchemaContexts(oldDocument).Concat(SchemaContexts(newDocument)).GroupBy(x => x.Key, StringComparer.Ordinal).ToDictionary(x => x.Key, x => x.SelectMany(v => v.Value).ToHashSet(StringComparer.Ordinal), StringComparer.Ordinal);
        foreach (var name in names)
        {
            if (!oldDocument.Schemas.TryGetValue(name, out var oldSchema))
            {
                var context = ContextFor(name, contexts, "Unknown");
                AddSchema(changes, ApiChangeKind.SchemaAdded, newDocument.Schemas[name], $"{name}[{context}]", "missing", SchemaSignature(newDocument, name), "normalized schema added", CompatibilityImpact.NonBreaking, CompatibilityImpact.NonBreaking, CompatibilityImpact.NonBreaking);
                continue;
            }
            if (!newDocument.Schemas.TryGetValue(name, out var newSchema))
            {
                var context = ContextFor(name, contexts, "Unknown");
                AddSchema(changes, ApiChangeKind.SchemaRemoved, oldSchema, $"{name}[{context}]", SchemaSignature(oldDocument, name), "missing", "normalized schema removed", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
                continue;
            }
            var contextValues = contexts.TryGetValue(name, out var found) && found.Count > 0 ? found : new HashSet<string>(["Unknown"], StringComparer.Ordinal);
            foreach (var context in contextValues.OrderBy(x => x, StringComparer.Ordinal)) CompareSchema(oldDocument, newDocument, oldSchema, newSchema, context, changes);
        }
    }

    private static void CompareSchema(NormalizedDocument oldDocument, NormalizedDocument newDocument, NormalizedSchema oldSchema, NormalizedSchema newSchema, string context, List<ApiChange> changes)
    {
        var prefix = $"{oldSchema.Name}[{context}]";
        if (!Equal(oldSchema.Kind, newSchema.Kind) || !Equal(oldSchema.PrimitiveType, newSchema.PrimitiveType) || !Equal(oldSchema.Format, newSchema.Format)) AddSchema(changes, ApiChangeKind.SchemaTypeChanged, oldSchema, prefix, SchemaSignature(oldDocument, oldSchema.Name), SchemaSignature(newDocument, newSchema.Name), "normalized schema kind/type/format", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
        if (!SequenceEqual(oldSchema.AllOf, newSchema.AllOf)) AddSchema(changes, ApiChangeKind.SchemaCompositionChanged, oldSchema, $"{prefix}.allOf", Join(oldSchema.AllOf), Join(newSchema.AllOf), "normalized schema allOf composition", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
        var propertyNames = oldSchema.Properties.Keys.Union(newSchema.Properties.Keys, StringComparer.Ordinal).OrderBy(x => x, StringComparer.Ordinal);
        foreach (var propertyName in propertyNames)
        {
            if (!oldSchema.Properties.TryGetValue(propertyName, out var oldProperty))
            {
                var added = newSchema.Properties[propertyName];
                var impacts = context == "Request" && added.Required ? (CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking) : (CompatibilityImpact.NonBreaking, CompatibilityImpact.NonBreaking, CompatibilityImpact.NonBreaking);
                AddSchema(changes, ApiChangeKind.PropertyAdded, newSchema, $"{prefix}.properties[{propertyName}]", "missing", PropertySignature(newDocument, added), "normalized schema property added", impacts.Item1, impacts.Item2, impacts.Item3);
                continue;
            }
            if (!newSchema.Properties.TryGetValue(propertyName, out var newProperty))
            {
                AddSchema(changes, ApiChangeKind.PropertyRemoved, oldSchema, $"{prefix}.properties[{propertyName}]", PropertySignature(oldDocument, oldProperty), "missing", "normalized schema property removed", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
                continue;
            }
            if (!oldProperty.Required && newProperty.Required) AddSchema(changes, ApiChangeKind.PropertyBecameRequired, oldSchema, $"{prefix}.properties[{propertyName}].required", "false", "true", "schema property became required", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
            if (oldProperty.Required && !newProperty.Required) AddSchema(changes, ApiChangeKind.PropertyBecameOptional, oldSchema, $"{prefix}.properties[{propertyName}].required", "true", "false", "schema property became optional", context == "Response" ? CompatibilityImpact.PotentiallyBreaking : CompatibilityImpact.NonBreaking, context == "Response" ? CompatibilityImpact.PotentiallyBreaking : CompatibilityImpact.NonBreaking, context == "Response" ? CompatibilityImpact.PotentiallyBreaking : CompatibilityImpact.NonBreaking);
            if (!Equal(SchemaSignature(oldDocument, oldProperty.Schema), SchemaSignature(newDocument, newProperty.Schema))) AddSchema(changes, ApiChangeKind.PropertyTypeChanged, oldSchema, $"{prefix}.properties[{propertyName}].schema", SchemaSignature(oldDocument, oldProperty.Schema), SchemaSignature(newDocument, newProperty.Schema), "normalized property schema signature", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
            if (oldProperty.AllowsNull != newProperty.AllowsNull || !Equal(oldProperty.NullPolicy, newProperty.NullPolicy)) AddSchema(changes, ApiChangeKind.NullableChanged, oldSchema, $"{prefix}.properties[{propertyName}].nullability", $"allowsNull={oldProperty.AllowsNull};policy={oldProperty.NullPolicy}", $"allowsNull={newProperty.AllowsNull};policy={newProperty.NullPolicy}", "normalized property nullability", CompatibilityImpact.Behavioral, CompatibilityImpact.PotentiallyBreaking, CompatibilityImpact.PotentiallyBreaking);
            if (oldProperty.ReadOnly != newProperty.ReadOnly) AddSchema(changes, ApiChangeKind.ReadOnlyChanged, oldSchema, $"{prefix}.properties[{propertyName}].readOnly", oldProperty.ReadOnly.ToString(), newProperty.ReadOnly.ToString(), "normalized property readOnly", CompatibilityImpact.Behavioral, CompatibilityImpact.PotentiallyBreaking, CompatibilityImpact.PotentiallyBreaking);
            if (oldProperty.WriteOnly != newProperty.WriteOnly) AddSchema(changes, ApiChangeKind.WriteOnlyChanged, oldSchema, $"{prefix}.properties[{propertyName}].writeOnly", oldProperty.WriteOnly.ToString(), newProperty.WriteOnly.ToString(), "normalized property writeOnly", CompatibilityImpact.Behavioral, CompatibilityImpact.PotentiallyBreaking, CompatibilityImpact.PotentiallyBreaking);
            if (!Equal(Json(oldProperty.DefaultValue), Json(newProperty.DefaultValue))) AddSchema(changes, ApiChangeKind.DefaultChanged, oldSchema, $"{prefix}.properties[{propertyName}].default", Json(oldProperty.DefaultValue), Json(newProperty.DefaultValue), "normalized property default", CompatibilityImpact.Behavioral, CompatibilityImpact.Behavioral, CompatibilityImpact.Behavioral);
        }
        foreach (var value in oldSchema.Enum.Except(newSchema.Enum, StringComparer.Ordinal).OrderBy(x => x, StringComparer.Ordinal)) AddSchema(changes, ApiChangeKind.EnumValueRemoved, oldSchema, $"{prefix}.enum", value, "missing", "enum value removed", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
        foreach (var value in newSchema.Enum.Except(oldSchema.Enum, StringComparer.Ordinal).OrderBy(x => x, StringComparer.Ordinal)) AddSchema(changes, ApiChangeKind.EnumValueAdded, newSchema, $"{prefix}.enum", "missing", value, "enum value added", CompatibilityImpact.NonBreaking, CompatibilityImpact.PotentiallyBreaking, CompatibilityImpact.PotentiallyBreaking);
        var oldVariants = oldSchema.OneOf.Concat(oldSchema.AnyOf).ToHashSet(StringComparer.Ordinal);
        var newVariants = newSchema.OneOf.Concat(newSchema.AnyOf).ToHashSet(StringComparer.Ordinal);
        foreach (var value in oldVariants.Except(newVariants, StringComparer.Ordinal).OrderBy(x => x, StringComparer.Ordinal)) AddSchema(changes, ApiChangeKind.UnionVariantRemoved, oldSchema, $"{prefix}.union", value, "missing", "union variant removed", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
        foreach (var value in newVariants.Except(oldVariants, StringComparer.Ordinal).OrderBy(x => x, StringComparer.Ordinal)) AddSchema(changes, ApiChangeKind.UnionVariantAdded, newSchema, $"{prefix}.union", "missing", value, "union variant added", CompatibilityImpact.NonBreaking, CompatibilityImpact.PotentiallyBreaking, CompatibilityImpact.PotentiallyBreaking);
        if (oldSchema.Discriminator is null && newSchema.Discriminator is not null) AddSchema(changes, ApiChangeKind.DiscriminatorAdded, newSchema, $"{prefix}.discriminator", "absent", newSchema.Discriminator.Property, "schema discriminator added", CompatibilityImpact.Behavioral, CompatibilityImpact.PotentiallyBreaking, CompatibilityImpact.PotentiallyBreaking);
        if (oldSchema.Discriminator is not null && newSchema.Discriminator is null) AddSchema(changes, ApiChangeKind.DiscriminatorRemoved, oldSchema, $"{prefix}.discriminator", oldSchema.Discriminator.Property, "absent", "schema discriminator removed", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
        if (oldSchema.Discriminator is not null && newSchema.Discriminator is not null)
        {
            if (!Equal(oldSchema.Discriminator.Property, newSchema.Discriminator.Property)) AddSchema(changes, ApiChangeKind.DiscriminatorPropertyChanged, oldSchema, $"{prefix}.discriminator.property", oldSchema.Discriminator.Property, newSchema.Discriminator.Property, "schema discriminator property", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
            var oldValues = oldSchema.Discriminator.Variants.Select(x => $"{x.Schema}={x.Value}").OrderBy(x => x, StringComparer.Ordinal).ToArray();
            var newValues = newSchema.Discriminator.Variants.Select(x => $"{x.Schema}={x.Value}").OrderBy(x => x, StringComparer.Ordinal).ToArray();
            if (!oldValues.SequenceEqual(newValues, StringComparer.Ordinal)) AddSchema(changes, ApiChangeKind.DiscriminatorValueChanged, oldSchema, $"{prefix}.discriminator.variants", Join(oldValues), Join(newValues), "schema discriminator mapping", CompatibilityImpact.Breaking, CompatibilityImpact.Breaking, CompatibilityImpact.Breaking);
        }
    }

    private static Dictionary<string, HashSet<string>> SchemaContexts(NormalizedDocument document)
    {
        var result = new Dictionary<string, HashSet<string>>(StringComparer.Ordinal);
        foreach (var operation in document.Operations)
        {
            foreach (var schema in operation.Parameters.Select(x => x.Schema)) Walk(schema, "Request", result, document);
            foreach (var schema in operation.RequestBody?.Representations.Select(x => x.Schema) ?? []) Walk(schema, "Request", result, document);
            foreach (var schema in operation.Responses.SelectMany(x => x.Representations).Select(x => x.Schema)) Walk(schema, "Response", result, document);
        }
        return result;
    }

    private static void Walk(string name, string context, Dictionary<string, HashSet<string>> result, NormalizedDocument document)
    {
        if (string.IsNullOrWhiteSpace(name) || !document.Schemas.ContainsKey(name)) return;
        if (!result.TryGetValue(name, out var contexts)) result[name] = contexts = new HashSet<string>(StringComparer.Ordinal);
        if (!contexts.Add(context)) return;
        var schema = document.Schemas[name];
        foreach (var child in schema.Properties.Values.Select(x => x.Schema).Concat(schema.OneOf).Concat(schema.AnyOf).Concat(schema.AllOf)) Walk(child, context, result, document);
    }

    private static void Add(List<ApiChange> changes, ApiChangeKind kind, NormalizedOperation operation, string? schemaName, string path, string oldValue, string newValue, string evidence, CompatibilityImpact api, CompatibilityImpact sdk, CompatibilityImpact powerShell)
        => changes.Add(new ApiChange { Kind = kind, ResourcePath = Resource(operation), OperationId = operation.OperationId, SchemaName = schemaName, Path = path, OldValue = oldValue, NewValue = newValue, Evidence = evidence, ApiImpact = api, SdkImpact = sdk, PowerShellImpact = powerShell });

    private static void AddSchema(List<ApiChange> changes, ApiChangeKind kind, NormalizedSchema schema, string path, string oldValue, string newValue, string evidence, CompatibilityImpact api, CompatibilityImpact sdk, CompatibilityImpact powerShell)
        => changes.Add(new ApiChange { Kind = kind, ResourcePath = string.Empty, SchemaName = schema.Name, Path = path, OldValue = oldValue, NewValue = newValue, Evidence = evidence, ApiImpact = api, SdkImpact = sdk, PowerShellImpact = powerShell });

    private static string Resource(NormalizedOperation operation) => string.Join('/', operation.ResourcePath);
    private static string ContextFor(string name, Dictionary<string, HashSet<string>> contexts, string fallback) => contexts.TryGetValue(name, out var found) && found.Count > 0 ? found.OrderBy(x => x, StringComparer.Ordinal).First() : fallback;
    private static string Selector(StatusSelector selector) => $"{selector.Kind}:{selector.Value}";
    private static bool IsError(StatusSelector selector) => selector.Value.StartsWith('4') || selector.Value.StartsWith('5') || selector.Value.Equals("default", StringComparison.OrdinalIgnoreCase);
    private static string Signature(ScopeBinding binding) => $"{binding.ScopeType}:{binding.Role}";
    private static string Signature(NormalizedParameter parameter) => $"{parameter.Location}:{parameter.Schema}:{parameter.Required}:{parameter.AllowsNull}";
    private static string Serialization(SerializationModel model) => $"{model.Style}:{model.Explode}:{model.AllowReserved}:{model.ArrayNotation}:{model.ObjectNotation}:{model.CustomSerializerId}";
    private static string PropertySignature(NormalizedDocument document, NormalizedProperty property) => $"{SchemaSignature(document, property.Schema)}:required={property.Required}:nullable={property.AllowsNull}";
    private static string SchemaSignature(NormalizedDocument document, string name) => document.Schemas.TryGetValue(name, out var schema) ? $"{schema.Name}:{schema.Kind}:{schema.PrimitiveType}:{schema.Format}:enum={Join(schema.Enum)}:oneOf={Join(schema.OneOf)}:anyOf={Join(schema.AnyOf)}" : $"missing:{name}";
    private static string Json(JsonNode? value) => value?.ToJsonString() ?? "<none>";
    private static string Join(IEnumerable<string> values) => string.Join(';', values.OrderBy(x => x, StringComparer.Ordinal));
    private static bool Equal(string? left, string? right) => string.Equals(left, right, StringComparison.Ordinal);
    private static bool SequenceEqual(IEnumerable<string> left, IEnumerable<string> right) => left.OrderBy(x => x, StringComparer.Ordinal).SequenceEqual(right.OrderBy(x => x, StringComparer.Ordinal), StringComparer.Ordinal);
}
