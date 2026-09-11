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
