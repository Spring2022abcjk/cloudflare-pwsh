# P3 Plan — Productionization

## Objective

Turn the validated P1/P2 architecture into a runtime that can execute generated operation metadata reliably and can later support a broader generated public surface. The plan is runtime-first: public cmdlet coverage is not the success metric until transport behavior is stable.

## Fixed boundaries

- Raw OpenAPI is loaded and normalized before any correction or projection.
- The runtime consumes corrected/generated metadata and bound parameters; it never parses OpenAPI.
- API corrections describe contract interpretation. PowerShell projection overrides describe UX. Neither owns HTTP transport policy.
- Request/response representations drive serialization and parsing.
- Retry is distinct from idempotency and requires a replayable request body.
- Mock HTTP contracts are primary evidence. Real-account validation is later and cannot replace deterministic mocks.
- PowerShell 7.6+ and .NET 10 are the supported Windows-first baseline.

## P3.1 slices

### P3.1a — Runtime transport abstraction

Establish explicit contracts for `CloudflareRequest`, `CloudflareResponse`, transport, serializer, response parser, retry policy, pagination, and authentication context. The abstraction must answer:

1. How a request representation selects a serializer.
2. How a response representation selects a parser.
3. How `CloudflareResult`, raw text/binary, and error envelopes are handled.
4. Which component owns `HttpContent`, response disposal, and response streams.
5. How `CancellationToken` flows through the entire invocation.

### P3.1b — Generic dispatcher and raw text

Provide the conceptual entry point:

```csharp
ExecuteAsync(OperationMetadata metadata,
            BoundParameters parameters,
            CancellationToken cancellationToken)
```

Dispatch path, query, headers, and body from metadata, send through the shared transport, select the parser by response representation, and expose a mock `text/plain` operation such as DNS export. Preserve the existing JSON Cloudflare-result path.

### P3.1c — Binary

Support `application/octet-stream` as a streaming-capable raw response. Decide the boundary between runtime `Stream` ownership and later PowerShell UX such as `-OutFile`, `-PassThru`, or buffered `byte[]`; do not assume every binary body belongs in memory.

### P3.1d — Multipart

Construct `multipart/form-data` from normalized representation metadata and schema format, including required/optional text and binary parts, content disposition, and content type. Cover DNS import and AI Search upload fixtures. Do not infer a file part from a parameter name: the pinned schema explicitly differs between these two operations.

### P3.1e — Pagination

Implement shared strategies for `V4PagePaginationArray`, `V4PagePagination`, `CursorPagination`, `CursorPaginationAfter`, `CursorLimitPagination`, and `SinglePage`, or record each unsupported strategy with evidence. Test empty pages, absent/repeated cursors, cancellation, and later-page server errors.

### P3.1f/g — Retry and idempotency

Add deterministic policy tests for default maximum retries of two, connection/timeout failures, 408/409/429/5xx, `x-should-retry`, `Retry-After`, `retry-after-ms`, exponential backoff, jitter, and replayability. Model idempotency support, key/header behavior, generated keys, and user overrides separately; where evidence is insufficient, do not claim mutation retry safety.

### P3.1h/i — Authentication and errors

Make API Token authentication available through a reusable authentication context. Keep legacy authentication deferred. Consolidate non-success HTTP, Cloudflare errors, transport failures, timeout, retry exhaustion, stream failure, and multipart construction errors into stable `CloudflareApiException` and PowerShell `ErrorRecord` behavior, retaining status, error code/message, safe raw body, headers/request ID, inner exception, and retry count.

## Test matrix

Add focused mock-contract coverage for:

`RawTextRuntimeTests`, `BinaryRuntimeTests`, `MultipartRuntimeTests`, `PaginationStrategyTests`, `RetryPolicyTests`, `ReplayabilityTests`, `AuthenticationContextTests`, `ErrorRuntimeTests`, and `GenericDispatcherTests`.

Every slice must also run the full P1, P2.1, P2.2, P2.3, and P2.4 regression chain. Static model tests do not close runtime behavior, and mock tests do not close real-account acceptance.

## P3.1 acceptance gate

P3.1 is complete only when all of the following are evidenced:

1. Generic dispatch executes normalized/generated metadata.
2. Existing JSON Cloudflare-result behavior remains green.
3. Raw text and binary mock operations execute.
4. Multipart requests construct and send correctly.
5. All recognized pagination strategies are implemented or explicitly tracked.
6. Retry and replayability have deterministic tests.
7. API Token authentication context works.
8. Error records are stable and preserve required diagnostics.
9. Generated metadata contains no transport-specific endpoint special case.
10. P1/P2 regression is green and documentation is updated.

HTTP `2xx` with `success=false`, full legacy authentication, generated public `PSCmdlet` migration, publishing, and real-account behavior remain deferred unless authoritative evidence changes their status.

## P3.2 Generated Public PowerShell Surface

P3.1 is complete against its runtime gate. P3.2 is completed in this workspace
for the validated five-cmdlet representative slice. It validates that generated
`PSCmdlet` classes can form a public PowerShell surface while preserving the
handwritten module's behavior; it does not close the deferred release,
real-account, device/manual, or unresolved runtime-semantic boundaries.

The first representative commands are deliberately limited to four:

- `Get-CfZone`: list/get parameter sets, scope and primary-id binding,
  pipeline-by-property-name, typed output, pagination, and shared dispatch.
- `Get-CfDnsRecord`: zone scope, record primary id, list/get, pagination, typed
  union response, and item output.
- `New-CfDnsRecord`: typed union input, JSON body, presence/null semantics,
  `ShouldProcess`, and `CloudflareResult` output.
- `Remove-CfDnsRecord`: `ShouldProcess`, confirmation impact, DELETE binding,
  no request body after the normalized DNS correction, and shared error mapping.

Generated commands are binding and output adapters only. They must construct
runtime bound arguments and call `GeneratedOperationMetadataAdapter` plus the
generic dispatcher. They must not create `HttpRequestMessage` instances or
duplicate query/body serialization, parsing, retry, pagination, cancellation,
or error conversion. A thin shared `PSCmdlet` base/helper may own runtime
resolution, authentication context, cancellation, common error conversion,
`ShouldProcess` plumbing, and output helpers; operation-specific parameters
remain in generated commands.

P3.2 must prove projection-driven parameter sets, requiredness and applicability,
pipeline binding, `[OutputType(...)]` and actual typed output, shared-runtime
pagination, `ShouldProcess`/`-WhatIf`, omitted versus explicit-null
`Optional<T>` semantics, stable generated/handwritten `ErrorRecord` parity, and
captured handwritten-versus-generated HTTP/output/error behavioral parity.
Help metadata and examples must be consumable, but complete external-help
rendering and full binary UX (`-OutFile`/`-PassThru`) remain deferred.

The phase adds focused metadata, dispatch, pipeline, `ShouldProcess`, error,
paging, presence, and parity tests plus `tools/Invoke-P32Tests.ps1`. Every
slice also runs the complete P1/P2/P3.1 regression chain. `Set-CfDnsRecord`
PUT/PATCH multi-operation parity is added only after the four representative
commands pass all prior gates.

P3.2 is not an API-coverage expansion, publishing effort, legacy-auth effort,
full real-account mutation validation, normalized-model redesign, P3.1
runtime rewrite, or a decision to guess HTTP `2xx` with `success=false`.

## P3.2 acceptance gate

P3.2 is complete in this workspace: the five representative generated cmdlets
dispatch through the shared runtime; their projection metadata and runtime
output are consistent; pipeline, typed output, pagination, `ShouldProcess`,
presence/null, and error behavior are evidenced; DNS DELETE correction remains
effective; generated code has no endpoint-specific transport logic;
handwritten-versus-generated parity tests are green; all P1/P2/P3.1
regressions are green; and `docs/adr/0002-generated-pscmdlet-surface.md`
records the migration decision from evidence. Broader public migration remains
outside this bounded acceptance.

## Progress reporting

Maintain `docs/P3.2-progress.md` throughout implementation with four explicit sections: `Implemented`, `Validated`, `Still Deferred`, and `Next`. A passing static test or build must not be reported as runtime, host, package, or real-account acceptance.
