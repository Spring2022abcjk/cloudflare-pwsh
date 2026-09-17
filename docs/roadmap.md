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
this workspace. P3.3 Projection Scalability / Admission and P3.4 CI /
Packaging Foundation are complete. The remaining P3 work is real-account
validation; broader public admission and release readiness remain separate
decisions.

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

#### P3.4 integration closure

Status: complete for the local/static release-engineering foundation. The P3.3
projection-reduction and explicit-admission result is merged with the P3.4
Windows-first CI, compatibility/coverage gates, deterministic candidate
packaging, and candidate smoke contract. The formal module surface remains the
five admitted P3.2 cmdlets; D1/D2 are bounded test-only slices and are not
package exports. See [P3.4 integration summary](./P3.4-integration-summary.md).

This closure does not claim remote GitHub Actions execution, real-account or
device/manual acceptance, publishing, or release readiness. Those evidence
boundaries move to P3.5, P4.1, P4.2, and P4.3 below.

### P3.5 — Real Integration Validation

Status: planned. P3.5 validates real Cloudflare account behavior after mock
contract coverage is sufficient. Real-account tests supplement, and do not
replace, mock tests.

#### P3.5a — Read-only live validation

Validate authentication, account/zone selection, read-only commands,
pagination, response/error mapping, and the operational safety boundary using a
constrained real account. Record the account, permissions, data scope, command
inputs, and cleanup assumptions without turning live data into a replacement
for fixtures or mock contracts.

#### P3.5b — Constrained CRUD validation

Validate the admitted DNS CRUD behavior against explicitly scoped disposable or
reversible resources. Cover create, read, update/edit, and delete behavior,
presence/null semantics, `ShouldProcess`/confirmation expectations, and cleanup
or rollback evidence. The exact account and resource protocol remain a later
execution decision.

#### P3.5c — Transport / rate-limit / error validation

Use constrained live scenarios to validate transport failures, rate limits,
authentication failures, pagination boundaries, mutation errors, and the
documented retry/idempotency behavior. Preserve the distinction between
observed live behavior, mock-only behavior, and unresolved semantics.

## P4 — Production Quality

Status: planned. P4 prepares and accepts the first release candidate using the
current five-cmdlet public baseline. Broader explicit public admission is not a
precondition for this first release candidate.

### P4.1 — Manual PowerShell UX & Help

Review the five formal public cmdlets — `Get-CfZone`, `Get-CfDnsRecord`,
`New-CfDnsRecord`, `Remove-CfDnsRecord`, and `Set-CfDnsRecord` — as a
PowerShell user. The review covers parameters, parameter sets, pipeline
binding, `ShouldProcess`, confirmation and error experience, `Get-Help`,
examples, discoverability, and consistency. This is manual UX/help evidence;
local builds, generated metadata, and mock tests do not replace it.

### P4.2 — Release & Security Hardening

Establish the release evidence and controls needed before final acceptance:
remote GitHub Actions execution evidence, security and supply-chain review,
secret handling, release policy, version/tag/release notes, and a PowerShell
Gallery publish dry-run. This phase may start while P3.5 and P4.1 are in
progress, but its groundwork is not final release acceptance.

### P4.3 — Final Release Candidate Acceptance

Wait for the conclusions of P3.5 and P4.1 and the applicable P4.2 groundwork.
Reconcile the evidence, unresolved risks, public-surface identity, package
provenance, and release policy into a final release-candidate acceptance and
publish/no-publish decision. A candidate is not accepted merely because local
CI, package smoke, or generated-source checks pass.

The execution relationship is:

```text
P3.5 ─────────┐
              ├→ P4.3 Final RC Acceptance
P4.1 ─────────┤
              │
P4.2 groundwork ─┘
```

P3.5 and P4.1 may proceed in parallel. P4.2 groundwork may also begin early,
but P4.3 must wait for P3.5 and P4.1 conclusions.

## P5 — Long-term Maintenance

Status: planned. Continue schema update workflows, compatibility reports,
regeneration CI, breaking-change gates, API drift monitoring, override-debt
tracking, deprecated-operation handling, and release automation. P5 maintains
the system after the first release decision; it does not expand the first
release candidate's public surface by implication.

## Deferred items

The following remain open until their dedicated evidence closes them:
real-account acceptance, device/manual UX, remote GitHub Actions execution,
Gallery publishing, legacy authentication, automatic idempotency, complete
mutation retry policy, full binary PowerShell UX, and HTTP `2xx` with
`success=false` semantics. Broader explicit public admission is intentionally
not bound to first-release readiness; the first release candidate remains
based on the current five formal public cmdlets.

The formal support baseline remains PowerShell 7.6+ and .NET 10 on the Windows-first host. See [ADR 0001](./adr/0001-net10-powershell76-baseline.md).
