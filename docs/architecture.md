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

Generated C# currently includes typed models and operation/projection metadata under `src/Cloudflare.PowerShell/Generated`. P3.2 has validated a generated `PSCmdlet` public surface for five representative commands; the public handwritten module remains the behavior reference for comparison while broader migration is deferred. Generated files are never hand-edited. The shared runtime is a production runtime foundation, but the repository is not release-ready merely because that foundation is complete.

## Confirmed Architecture Facts

### DNS vertical slice

The six DNS operations `create`, `list`, `get`, `update`, `edit`, and `delete` pass through normalization, correction, projection, generated metadata/models, runtime, mock HTTP, typed output, error mapping, and golden tests.

### Typed unions

DNS `anyOf`/`oneOf`/`allOf` composition is retained by the normalized model. Representative typed request inputs include `A`, `MX`, `CAA`, `HTTPS`, and `SVCB`. Union schemas must not silently become `object`, `Dictionary<string, object>`, or `PSCustomObject`-only models. When `additionalProperties` has a known normalized schema, the schema reference is retained and the capability-driven model projection may emit a typed `Dictionary<string, T>`; unknown map values remain a capability gap.

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

The generated `Get-CfZone` `PSCmdlet` was initially isolated as a net10 experiment because the current host's `System.Management.Automation` assembly is net10 while the production module was net8; that `CS1705` evidence drove the repository-wide net10 migration. It proves command metadata loading, not HTTP dispatch. The handwritten module remains the runtime reference until generated dispatch has equivalent mock coverage. Both binary-cmdlet projects compile against the private, build-only `System.Management.Automation` 7.6.0 package and rely on the importing `pwsh` host for runtime SMA. The supported baseline is PowerShell 7.6+ and .NET 10 on the Windows-first host; see [ADR 0001](./adr/0001-net10-powershell76-baseline.md).

## P2.4 Compatibility Facts

Compatibility comparison consumes two normalized documents and derives two deterministic PowerShell CmdletModels through `ProjectionModelBuilder`. `CompatibilityEngine` and `ProjectionCompatibility` emit typed `ApiChange` records with independent API, SDK, and PowerShell impact dimensions. `CompatibilityReportFormatter` emits deterministic JSON and Markdown artifacts for both API and projection reports. Raw OpenAPI revision text is used only as input to normalization; the comparison itself operates on normalized semantics. Synthetic mutation tests establish the change taxonomy before the pinned real revision comparison is run.

## P3 Runtime Direction

P3 introduces a shared runtime between operation metadata and HTTP transport:

```text
OperationMetadata + BoundParameters + CancellationToken
        ↓
Generic Dispatcher
        ↓
Authentication / path / query / body binding
        ↓
Replayability-aware retry policy
        ↓
Transport
        ↓
Response representation → parser → envelope/error policy
        ↓
Pagination when declared by metadata
        ↓
Typed result / raw text / binary stream
```

The dispatcher consumes normalized/generated metadata and bound values; it does not parse OpenAPI. Request and response representations select serializers and parsers. JSON Cloudflare results, raw text, binary, multipart, and no-content responses are runtime cases, not endpoint-specific generator branches. This shared runtime is the production runtime foundation for generated operations; it is not a release-ready public SDK by itself.

The generator emits declarative `GeneratedOperationMetadata` records from the
normalized operation projection. `GeneratedOperationMetadataAdapter` maps those
records into runtime contracts for method/path, path/query/header bindings,
request/response representations, multipart parts, and pagination fields. The
handwritten DNS client only selects generated operation IDs; it does not repeat
transport metadata or introduce an endpoint-specific dispatcher branch.

Transport owns the HTTP request/response and serialized `HttpContent` disposal boundaries. Caller-owned multipart input streams remain open and are not retryable unless a fresh-stream factory is supplied. A streaming response must remain usable for its documented lifetime, while a buffered parser owns the resulting memory. Cancellation is passed from the public invocation through dispatch, retry delays, transport, parsing, and page iteration.

Retry is separate from idempotency. A request may be retryable only when its body is replayable and the retry policy permits the status/exception; a mutation is not automatically retry-safe. Authentication is supplied through an `AuthenticationContext`, and secrets never enter generated metadata.

## P3.3 Coverage Direction

P3.3 adds a discovery/reporting boundary before public expansion:

```text
Full pinned OpenAPI
        ↓
Normalizer → API correction trace
        ↓
Projection diagnostics → runtime capability diagnostics
        ↓
Deterministic operation classification/report
        ↓
Bounded canonical public projection
        ↓
Generated PSCmdlet → shared runtime
```

Normalization success, projection construction, and generated C# are separate
stage results. An operation is not `Supported` until public eligibility and the
same request/output/error/safety evidence used by P3.2 are present. Operations
that are not admitted to the current bounded public policy remain explicitly
classified rather than silently omitted. The discovery baseline and schema are
defined in [P3.3 plan](./P3.3-plan.md) and emitted by
`tools/Invoke-P33CoverageDiscovery.ps1`.

The D1 `d1/database` bounded slice is complete. D2 `healthchecks` adds six
zone-scoped operations through the same chain, including typed nested models,
known map values, page-array pagination, and a generic PowerShell parameter-set
discriminator for identical PUT/PATCH public bindings. Its evidence remains
separate from real-account, device/manual, packaging, publishing, and release
evidence.

## P3.3 projection-reduction boundary

Global discovery now records projection conflicts as semantic blocker
categories rather than treating every duplicate parameter-set name as the
same problem. The shared `ProjectionModelBuilder` has two opt-in,
capability-driven disambiguation rules:

- a normalized scope-binding key can suffix a parameter set when the colliding
  operations have distinct scope signatures;
- a normalized HTTP method can suffix a parameter set when the remaining
  operations have distinct methods.

These rules use no resource or operation identifiers and never rename an
explicitly declared policy parameter set. Operations that remain identical on
scope and method stay projection blockers. A resolved projection identity is
not public admission: the explicit policy in
`overrides/public-admission-policy.json` still requires typed model, runtime,
compatibility, safety, parity, and policy evidence.

The current formal public surface is the five-cmdlet P3.2
`artifacts/p3.2/CmdletModel.json` surface: `Get-CfZone`, `Get-CfDnsRecord`,
`New-CfDnsRecord`, `Remove-CfDnsRecord`, and `Set-CfDnsRecord`. The D1/D2
artifacts and generated bounded slices remain available through a direct binary
test surface, but are not formal module exports. The admission parity gate
`tools/Invoke-P33AdmissionParity.ps1` reconciles the canonical model, coverage,
P2.4 compatibility surface, generated public source, manifest, module runtime,
and generated help by canonical cmdlet identity; an extra or missing identity
fails acceptance.

Scope disambiguation is accepted only after the candidate has been transformed
through the shared final PowerShell name canonicalizer and the resulting
cmdlet-plus-parameter-set identities are unique. Raw scope keys that converge
after PowerShell naming remain unresolved. A composite scope-plus-method
discriminator is a future architectural opportunity, not part of this phase.

The before/after global reports and deterministic blocker taxonomy are under
`artifacts/coverage`. The current reduction changes projection-stage counts,
but keeps the eight-operation public surface and all low-confidence semantic
rows outside automatic admission.

## P3.4 CI and package-candidate direction

P3.4 composes the existing evidence boundaries rather than adding a second
generator or runtime path:

```text
Pinned schema manifest + verified external checkout
        ↓
Existing P1–P3.3 read-only/golden/regression gates
        ↓
P2.4 compatibility policy + P3.3 coverage policy
        ↓
Release build → exact module staging → candidate-only package smoke
        ↓
Non-published release-candidate artifact
```

The pinned schema manifest records the upstream Git revision, normalized source
revision, source path, and SHA-256. The checkout is ignored external evidence;
CI does not treat an unpinned latest schema as deterministic input. CI jobs use
the Windows PowerShell 7.6+ / .NET 10 baseline and require no real Cloudflare
token for normal acceptance.

`Directory.Build.props:VersionPrefix` is the version source of truth. The
module manifest must match it, and the package builder checks the resulting
assembly version and `net10.0` output. Candidate module import consumes only
the staged manifest, module script, help XML, and assembly; reports and build
metadata are adjacent evidence, not runtime dependencies. Candidate smoke is
run in a clean child PowerShell process with local mock HTTP.

Compatibility decisions remain typed API/SDK/PowerShell impact decisions from
P2.4. Coverage decisions remain operation-row and semantic-transition checks
from P3.3; no final coverage count is hardcoded as a release criterion.

## Deferred Boundaries

Mutation idempotency policy, legacy authentication, full PowerShell binary UX,
full generated public-cmdlet migration, module publishing, real-account
integration, and the final handwritten-vs-generated-cmdlet decision remain
unresolved. P3.2 is limited to its five validated representative cmdlets until
broader parity evidence supports expansion. The P3.1 runtime has deterministic mock coverage
for multipart, binary streams, and all six recognized pagination strategies;
HTTP 2xx with `success=false` remains intentionally unresolved.
