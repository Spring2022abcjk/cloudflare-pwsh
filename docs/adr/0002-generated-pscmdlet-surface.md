# ADR 0002: Generated PSCmdlet Surface Boundary

## Status

Accepted for the validated P3.2 representative slice; not a full module
migration or release decision.

## Context

P3.1 established a shared metadata-driven runtime. P3.2 had to determine
whether public generated PowerShell commands could preserve the handwritten
behavior without copying transport policy into generated code.

## Decision

Use generated `PSCmdlet` classes as binding and output adapters for the
validated Zone/DNS operations. Generated code must obtain operation metadata
and call `CloudflareCmdletBase`, which adapts metadata through
`GeneratedOperationMetadataAdapter` and the shared dispatcher. The checked-in
source is reproduced from the deterministic P3.2 template.

Keep handwritten functions during transition as module-internal behavioral
references, but route the public names only to generated cmdlets. Expand
generated coverage only when the same request, output, error, parameter, and
safety evidence is available for the operation.

Treat `artifacts/p3.2/CmdletModel.json` as the canonical public projection.
`tools/Project-P32Projection.ps1` owns projection from normalized inputs;
`tools/Generate-P32Source.ps1` consumes that artifact and fails on stale
inputs, semantic-digest drift, missing or unconsumed parameters, unknown
operations, and complete request/response/pagination runtime metadata drift.
The renderer is capability-driven by the artifact's execution,
parameter-set, operation-binding, body, output, and ShouldProcess fields; the
five-command P3.2 scope is policy data, not renderer control flow.
`DnsRecordId` is primary and `RecordId` is a compatibility alias for the three
DNS id commands.

## Evidence and consequences

Deterministic mock tests demonstrated parity for all five representative
commands, including `Set-CfDnsRecord` `PUT`/`PATCH`. Tests cover headers, body,
response/output, ErrorRecord, paging, WhatIf, requiredness, applicability,
and full runtime metadata. Generated-source checks prevent endpoint-specific
transport, serialization, parsing, retry, pagination, cancellation, and error
mapping. Negative tests prove that changing an artifact semantic field while
leaving input hashes unchanged, or changing runtime request/response/paging
metadata, fails validation.

The generated surface is easier to reproduce and review, while the handwritten
reference remains useful during migration without being a public route. This
ADR does not close legacy auth,
automatic idempotency, complete mutation retry safety, `2xx + success=false`,
binary UX, real-account behavior, publishing, or release readiness.
