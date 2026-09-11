# Roadmap

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

### P3

Broader Cloudflare API generation and runtime hardening.

### P4

Production quality: help, packaging, publishing, CI, schema-update workflow, and release compatibility reporting.

No P3/P4 dates or coverage counts are fixed in this roadmap.
