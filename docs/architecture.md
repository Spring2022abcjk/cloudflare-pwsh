# Architecture

## Pipeline

The project uses the following boundary between API interpretation, projection, generation, and runtime:

```text
Cloudflare OpenAPI
        ↓
OpenAPI Loader / $ref Resolver
        ↓
Normalizer
        ↓
Raw Normalized API Model
        ↓
API Corrections
        ↓
Corrected Normalized API Model
        ↓
PowerShell Projection
        ↓
CmdletModel / Generated Model Metadata
        ↓
Deterministic Generator
        ↓
Generated C# Models + Metadata
        ↓
Runtime
        ↓
Handwritten PowerShell UX
```

Raw OpenAPI never enters the PowerShell emitter. All PowerShell generation is based on the corrected normalized model plus `overrides/powershell-projection.json`.

The normalized model describes the API contract: method, path, parameters, request bodies, responses, schema composition, presence/nullability, resource bindings, pagination, authentication evidence, and semantic provenance. It does not contain `Get`/`New`/`Set`/`Remove`, `ShouldProcess`, `ConfirmImpact`, PowerShell parameter names, help wording, or other UX policy.

API corrections and PowerShell projection overrides are separate:

- `overrides/api-corrections.json` changes the interpreted API contract and retains a correction trace.
- `overrides/powershell-projection.json` chooses the public verb/noun, parameter names, confirmation policy, output policy, and help-oriented metadata.

Generated C# is currently limited to typed models and operation/projection metadata under `src/Cloudflare.PowerShell/Generated`. The public ergonomic surface remains handwritten in `module/Cloudflare.PowerShell/Cloudflare.PowerShell.psm1`. Generated files are never hand-edited. A generated `PSCmdlet` surface is an isolated experiment, not the current implementation route.

## Confirmed Architecture Facts

### DNS vertical slice

The six DNS operations `create`, `list`, `get`, `update`, `edit`, and `delete` pass through normalization, correction, projection, generated metadata/models, runtime, mock HTTP, typed output, error mapping, and golden tests.

### Typed unions

DNS `anyOf`/`oneOf`/`allOf` composition is retained by the normalized model. Representative typed request inputs include `A`, `MX`, `CAA`, `HTTPS`, and `SVCB`. Union schemas must not silently become `object`, `Dictionary<string, object>`, or `PSCustomObject`-only models.

### Presence semantics

The model distinguishes omitted, explicit null, and specified value. `Optional<T>` carries this state into generated input serialization; the distinction must remain intact from OpenAPI through JSON output.

### Response modeling

Envelope policy belongs to `ApiResponseRepresentation`, not the whole operation. Response cases support exact statuses, status classes, and default responses, with JSON, text, binary, and no-content parsing modes.

### Resource scopes

Scope is represented by any number of `ScopeBinding` entries. `zone_id`, `account_id`, namespace, instance, database, and other identifiers are bindings with parent, nested, or primary roles; a single `ScopeKind` is not the primary model.

### Operation semantics

`List`, `Get`, `Create`, and related kinds are inferred semantic labels with source and confidence. They are not treated as raw OpenAPI facts.

### Pagination

Pagination is a shared-runtime concern. Normalization records the detected strategy and evidence; endpoint emitters do not own page loops. DNS currently proves `V4PagePaginationArray` and item-oriented pipeline output.

### Multi-operation projection

PUT and PATCH DNS operations can share the public `Set-CfDnsRecord` projection while retaining independent operation bindings, requiredness, and applicability in each parameter set.

## P2.1 Generalization Facts

P2.1 is a model stress test, not an endpoint-count exercise. Zones, D1, and deep AI Search fixtures are selected to test ordinary CRUD, account scope, and nested bindings. A new behavior is classified before implementation as general normalized-model capability, API correction, or PowerShell projection policy. Resource-specific conditionals in the emitter are not an accepted extension mechanism.

## P2.2 Transport Facts

P2.2 confirms that the normalized model can represent the four special transport cases found in the pinned OpenAPI source without adding model fields:

- DNS export uses a successful `text/plain` response and normalizes to `Raw`.
- DNS import and AI Search item upload use `multipart/form-data`; both preserve the required file part, while only the AI Search file is explicitly declared as binary in the source schema.
- AI Search item download uses a successful `application/octet-stream` response and normalizes to `Raw`.
- JSON success responses use `CloudflareResult`; exact JSON 4xx/5xx responses use `ErrorEnvelope`.

The normalizer records these facts in request/response representations, content types, envelope policies, and parsing modes. The current PowerShell runtime remains JSON/envelope-only; multipart serialization, raw-body handling, and production streaming are intentionally deferred to the runtime phase.

## P2.3 PowerShell Projection Facts

P2.3 adds a separate projection overlay for PowerShell-only policy. The overlay can select deterministic PowerShell parameter names, pipeline binding, output type, output policy, confirmation, and help metadata without changing the normalized API fixtures or the P2.1 compatibility projection.

The generated `Get-CfZone` `PSCmdlet` is an isolated net10 experiment because the current host's `System.Management.Automation` assembly is net10 while the production module is net8. It proves command metadata loading, not HTTP dispatch. The handwritten module remains the runtime reference until generated dispatch has equivalent mock coverage.

## Deferred Boundaries

Production retry/idempotency policy, legacy authentication, multipart and binary runtime handling, streaming, complete pagination strategies, full generated help, module publishing, real-account integration, and the final handwritten-vs-generated-cmdlet decision remain unresolved. HTTP 2xx with `success=false` also remains intentionally unresolved.
