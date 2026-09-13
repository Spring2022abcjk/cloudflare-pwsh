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

Keep handwritten functions during transition as behavioral references and
retain the existing command-resolution behavior. Expand generated coverage
only when the same request, output, error, parameter, and safety evidence is
available for the operation.

## Evidence and consequences

Deterministic mock tests demonstrated parity for the four representative
commands and then for `Set-CfDnsRecord` `PUT`/`PATCH`. Tests cover headers,
body, response/output, ErrorRecord, paging, WhatIf, requiredness, and
applicability. Generated-source checks prevent endpoint-specific transport,
serialization, parsing, retry, pagination, cancellation, and error mapping.

The generated surface is easier to reproduce and review, while the handwritten
reference remains useful during migration. This ADR does not close legacy auth,
automatic idempotency, complete mutation retry safety, `2xx + success=false`,
binary UX, real-account behavior, publishing, or release readiness.
