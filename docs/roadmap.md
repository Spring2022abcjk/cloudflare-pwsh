# Roadmap

This roadmap records the staged path from a validated normalization prototype to a usable, maintainable, and publishable PowerShell SDK. Completion claims are based on repository evidence; deferred items remain explicitly unresolved.

## Completed

### P1 — DNS vertical slice and OpenAPI normalization

Completed:

- DNS CRUD vertical slice with typed union inputs, presence semantics, runtime, mock HTTP, module smoke, and golden tests.
- General correction/projection pipeline, deterministic symbol naming, multi-operation projection, `Optional<T>`, and representative typed DNS variants.
- OpenAPI loader, local `$ref` resolver, parameter/request/response normalization, composition preservation, discriminator detection, resource/scope inference, pagination recognition, API corrections, and semantic structural comparison.
- The historical P1.2 verification reported six normalized DNS operations and 387 schemas; the current rerun reports 399 schemas after preserving indexed inline composition branches.

See [architecture](./architecture.md) for the durable boundaries and [development principles](./development-principles.md) for the rules carried forward from P1.

## P2 — Cross-resource generalization and model stress testing

### P2.1 Cross-resource normalization

Status: completed in this workspace; see [P2.1 summary](./P2.1-summary.md).

1. Zones: ordinary collection/resource CRUD through normalize → correction → projection.
2. D1 database: account-scoped resource with `account_id` as a normal parent binding.
3. AI Search namespace/instance/jobs: deep nested resource with multiple parent/nested/primary bindings.
4. Capture normalized fixtures, semantic snapshots, projection snapshots, and generated metadata goldens.
5. Add tests for cross-resource normalization, scope bindings, projection generalization, and regression of the DNS semantic diff.
6. Record every new model capability, correction, projection rule, exception, and unresolved issue in `docs/P2.1-summary.md`.

P2.1 is complete only when all three resources pass the intended pipeline, no endpoint-specific emitter hardcode is added, existing DNS and P1 tests remain green, and the summary records confirmed/inferred/decision/prototype/deferred results.

### P2.2 Special transport

Status: completed in this workspace; see [P2.2 summary](./P2.2-summary.md).

Normalized DNS export/import and AI Search upload/download. Confirmed that request/response representations, content types, envelope policy, and parsing mode express the selected contracts; production streaming and multipart runtime behavior remain deferred.

### P2.3 PowerShell projection and binary-cmdlet experiment

Status: completed in this workspace; see [P2.3 summary](./P2.3-summary.md). The projection surface is generalized in a separate P2.3 overlay, and the generated `Get-CfZone` experiment is isolated from the public handwritten module. Runtime dispatch and migration remain deferred.

The experiment compares metadata, parameter sets, pipeline, help loading, host-local lookup timing, source size, runtime coverage, and testability. It does not treat a metadata-only command body as production runtime evidence.

### P2.4 Schema evolution and compatibility

Status: completed in this workspace; see [P2.4 summary](./P2.4-summary.md). The net10/PowerShell 7.6 baseline migration is recorded in [ADR 0001](./adr/0001-net10-powershell76-baseline.md).

The engine compares old/new normalized revisions semantically and classifies endpoint/path, requiredness, enum, property type, response, pagination, scope, semantic, and PowerShell projection changes as API, SDK/model, PowerShell, or non-breaking impacts. Source text diff is not sufficient.

## Later

## P3 — Productionization

Status: active. P3.1, P3.2, and the bounded P3.3 coverage phase are complete in
this workspace. The remaining P3 work is packaging/CI/update workflow and
real-account validation; broader public admission and release readiness remain
separate decisions.

### P3.1 — Production Runtime

Status: completed in this workspace; see [P3.1 summary](./P3.1-summary.md) and [P3.1 progress](./P3.1-progress.md).

Implement and validate a transport-independent runtime abstraction covering request/response representations, serializers, parsers, content lifetimes, generic operation dispatch from generated metadata, raw text, binary, multipart, streaming, shared pagination, replayability-aware retry, separately modeled idempotency, authentication context, cancellation, and stable error mapping.

The first delivery slices are runtime abstraction, generic dispatch, raw text, binary, and multipart. Pagination, retry, authentication, and error consolidation follow as independently tested slices. HTTP `2xx` with `success=false` remains unresolved until official or live evidence supports a decision.

### P3.2 — Generated Public Surface

Status: completed in this workspace; see [P3.2 progress](./P3.2-progress.md)
and [P3.2 summary](./P3.2-summary.md).

The validated representative surface is `Get-CfZone`, `Get-CfDnsRecord`,
`New-CfDnsRecord`, `Remove-CfDnsRecord`, and `Set-CfDnsRecord` (PUT/PATCH).
Generated commands bind PowerShell parameters and delegate execution through
generated operation metadata and the shared runtime. The slice proves
parameter-set metadata, pipeline binding, typed output, shared pagination,
`ShouldProcess`, presence/null semantics, stable errors, and
handwritten-versus-generated behavioral parity. Broader generated public
migration remains deferred.

### P3.3 — API Coverage Expansion

Status: completed in this workspace for the bounded discovery/D1/D2 scope; see
[P3.3 plan](./P3.3-plan.md), [P3.3 progress](./P3.3-progress.md), and
[P3.3 summary](./P3.3-summary.md). The six-operation `d1/database` and
`healthchecks` extensions passed their slice gates. Global public admission is
unchanged: every scanned operation remains classified, and the six D2
operations remain `ExcludedByPolicy`.

The projection-reduction follow-on is also evidenced in this workspace. Its
taxonomy and before/after reports are under `artifacts/coverage`; generic
scope-key and HTTP-method rules reduce projection conflicts while leaving
same-scope/same-method ambiguity and low-confidence semantics unresolved.
Public admission remains explicit-only under
`overrides/public-admission-policy.json`; no newly projection-ready row is
automatically exported. The formal module surface remains the five admitted
P3.2 cmdlets; D1/D2 generated binaries are test-only bounded surfaces and are
not module exports. The admission parity gate reconciles canonical artifact,
coverage, compatibility, generated source, manifest/runtime, and help by
identity.

### P3.4 — Packaging, CI, and Update Workflow

Status: completed in this workspace for the non-publishing release-engineering foundation; see [P3.4 plan](./P3.4-ci-packaging-plan.md) and [P3.4 summary](./P3.4-ci-packaging-summary.md).

The Windows-first CI workflow now separates build, deterministic generation,
unit/runtime, P1–P2.4 regression, compatibility, coverage, package assembly,
and package smoke jobs. It verifies an exact pinned schema, uses explicit P2.4
and P3.3 semantic policies, aligns assembly/manifest/package versioning from
`Directory.Build.props`, and uploads a non-published candidate containing the
module, reports, summary, and deterministic ZIP. Schema updates are validated
through a manual workflow-dispatch entry in an isolated temporary checkout.
PowerShell Gallery publication, real-account validation, and broader public
admission remain later decisions.

### P3.5 — Real Integration Validation

Only after mock contract coverage is sufficient, validate authentication, CRUD, pagination, retry/rate limits, multipart, binary, streaming, and error behavior against a constrained real Cloudflare account. Real-account tests supplement, and do not replace, mock tests.

## P4 — Production Quality

Complete help and examples, module manifest and semantic versioning, release notes and publishing, support matrix, performance review, telemetry policy (if any), security review, secret handling, and user documentation.

## P5 — Long-term Maintenance

Automate schema updates, compatibility reports, regeneration CI, breaking-change gates, API drift monitoring, override-debt tracking, deprecated-operation handling, and release automation.

## Deferred items

The following remain outside the completed P3.1 boundary or unresolved in P3.2: HTTP `2xx` with `success=false` semantics, production retry/idempotency policy details, legacy authentication, full PowerShell binary UX, final public generated `PSCmdlet` migration decision, complete real-account behavior, publishing, and release/security policy.

The formal support baseline remains PowerShell 7.6+ and .NET 10 on the Windows-first host. See [ADR 0001](./adr/0001-net10-powershell76-baseline.md).
