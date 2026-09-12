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

Status: active. The goal is to move from architecture validation to a runnable, extensible, and controllably releasable generated SDK. P3.1 is the current priority; broad public cmdlet expansion waits for the shared runtime to stabilize.

### P3.1 — Production Runtime

Implement and validate a transport-independent runtime abstraction covering request/response representations, serializers, parsers, content lifetimes, generic operation dispatch from generated metadata, raw text, binary, multipart, streaming, shared pagination, replayability-aware retry, separately modeled idempotency, authentication context, cancellation, and stable error mapping.

The first delivery slices are runtime abstraction, generic dispatch, raw text, binary, and multipart. Pagination, retry, authentication, and error consolidation follow as independently tested slices. HTTP `2xx` with `success=false` remains unresolved until official or live evidence supports a decision.

### P3.2 — Generated Public Surface

After runtime stabilization, evaluate broader PowerShell projection, generated `PSCmdlet` dispatch, help generation, argument completion, pipeline behavior, `ShouldProcess`, and output typing. The handwritten module remains the authoritative runtime reference until generated dispatch has equivalent mock coverage.

### P3.3 — API Coverage Expansion

Expand coverage through the normalized pipeline rather than hand-adding endpoint-specific cmdlets. Produce coverage, unsupported-operation, unknown-normalization, and projection-conflict reports.

### P3.4 — Packaging, CI, and Update Workflow

Add module packaging, CI, schema-update detection, compatibility gates, deterministic generated diffs, release artifacts, versioning, and publishing workflow. P2.4 deterministic compatibility JSON/Markdown is the input to the schema-update gate.

### P3.5 — Real Integration Validation

Only after mock contract coverage is sufficient, validate authentication, CRUD, pagination, retry/rate limits, multipart, binary, streaming, and error behavior against a constrained real Cloudflare account. Real-account tests supplement, and do not replace, mock tests.

## P4 — Production Quality

Complete help and examples, module manifest and semantic versioning, release notes and publishing, support matrix, performance review, telemetry policy (if any), security review, secret handling, and user documentation.

## P5 — Long-term Maintenance

Automate schema updates, compatibility reports, regeneration CI, breaking-change gates, API drift monitoring, override-debt tracking, deprecated-operation handling, and release automation.

## Deferred items

The following are not complete merely because P2 is complete: HTTP `2xx` with `success=false` semantics, production retry/idempotency policy details, legacy authentication, multipart runtime, binary/streaming runtime, complete pagination strategies, generated help, public generated `PSCmdlet` migration, real-account behavior, publishing, and release/security policy.

The formal support baseline remains PowerShell 7.6+ and .NET 10 on the Windows-first host. See [ADR 0001](./adr/0001-net10-powershell76-baseline.md).
