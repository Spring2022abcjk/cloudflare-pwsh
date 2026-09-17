# Development Principles

1. Raw OpenAPI never enters the PowerShell emitter.
2. The normalized model describes API contracts, not PowerShell UX.
3. API corrections and PowerShell projection overrides remain separate.
4. General API capability belongs in the model; Cloudflare-specific behavior belongs in corrections; PowerShell ergonomics belong in projection.
5. Do not accumulate endpoint-specific `if` branches in the generator.
6. Preserve typed unions; do not degrade them to `object` without evidence.
7. Preserve omitted, explicit-null, and specified-value states.
8. Do not force request and response models to share a type when the contract distinguishes them.
9. Represent scope as bindings; do not assume only `ZoneId` and `AccountId` exist.
10. Record semantic inference with provenance and confidence.
11. Generated source must be deterministic.
12. Generated source must not be manually edited.
13. Golden source diff does not replace semantic diff.
14. Treat each new resource as a model pressure test, not a cmdlet-count target.
15. Mark evidence gaps as unresolved; do not guess.
16. Prove that the model can express an operation before adding runtime convenience.
17. Do not copy Stainless; faithfully represent Cloudflare contracts and provide a PowerShell-native projection.
18. Update project documentation at the end of every phase, not only the chat summary.
19. Prefer pinned schemas, local fixtures, mock HTTP, and deterministic snapshots; real-account tests are separate evidence.
20. Keep host, package, runtime, device, and manual evidence distinct in reports.
21. The supported repository baseline is PowerShell 7.6+ and .NET 10; do not add compatibility shims for older hosts without explicit evidence.
22. Schema evolution is evaluated from normalized semantic models and projection artifacts; raw text or generated source diffs alone cannot close a compatibility decision.
23. Compatibility reports must preserve separate API, SDK, and PowerShell impacts and retain deterministic evidence paths and values.
24. Runtime behavior is driven by request/response representations and shared metadata, not endpoint-specific generator branches.
25. Keep serialization, parsing, pagination, retry, authentication, cancellation, and error mapping in shared runtime components.
26. Retry and idempotency are separate decisions; require replayable request bodies before retrying a request with content.
27. Make stream and `HttpContent` ownership explicit; cancellation must flow through transport, parsing, retry, and pagination.
28. Prefer mock HTTP contract tests for runtime behavior; real-account tests are a later, separate validation layer.
29. Do not mark an unresolved semantic—especially HTTP `2xx` with `success=false`—as decided without authoritative evidence.
30. Complete and update the relevant roadmap/progress document at each runtime slice, including implemented, validated, deferred, and next work.
31. Every P3.3 discovery operation must receive exactly one explicit final coverage classification; normalization or projection failure must not silently remove it.
32. Keep coverage stage counts separate: normalized, corrected, projected, runtime-ready, public-eligible, and fully evidenced are not interchangeable.
33. Coverage reports and derived family summaries must be deterministic; do not include wall-clock timestamps in semantic artifacts.
34. Use corrections for API-contract evidence, projection overrides for PowerShell UX policy, and shared model/runtime changes for general capability gaps; do not use overrides to conceal a structural IR deficiency.
35. A coverage percentage or generated-cmdlet count is not an acceptance gate without typed output, runtime, safety, parity, compatibility, and regression evidence.
36. Classify projection blockers by normalized semantics and stable evidence; do not group them only by emitted error text.
37. Generic projection disambiguation may use normalized scope and HTTP method facts, but it must not rename explicit policy or auto-admit a public cmdlet.
38. Keep unresolved same-scope/same-method parameter-set collisions and low-confidence semantic inference as manual/product decisions; do not manufacture UX from coverage pressure.
39. Public admission is an explicit gate independent of normalization success, projection construction, runtime readiness, or generated-source availability.
40. An admission policy is an enforceable production contract only when the
    generation or acceptance path consumes it; documentation and tests alone
    are insufficient.
41. Reconcile admitted canonical commands against generated source, module
    manifest/runtime exports, generated help, coverage, and compatibility by
    canonical identity. Extra or missing public identities fail the gate.
42. A generic discriminator is safe only after final PowerShell canonicalization
    and uniqueness validation in the public cmdlet/parameter-set namespace.
