# Cloudflare PowerShell SDK Prototype

This Windows-first project normalizes the pinned Cloudflare OpenAPI schema, applies API corrections, projects PowerShell metadata, and exercises a shared runtime with deterministic fixtures and mock HTTP. P1 and P2 established the normalized-model, correction, projection, compatibility, and generation boundaries; P3 now hardens the runtime for productionization.

## Support baseline

- PowerShell 7.6+
- .NET 10 (`TargetFramework=net10.0`)
- Windows-first development environment

The production projects and tests target .NET 10. `System.Management.Automation` is a build-only NuGet reference; the module does not package the PowerShell engine, and `pwsh` supplies SMA at runtime. The pinned `ref/` directory contains ignored external evidence and is not modified.

The supported build entry point is ordinary `dotnet build`; it does not require a `PowerShellHome` MSBuild property.

Run the current regression chain with:

```powershell
pwsh -NoLogo -NoProfile -File .\tools\Invoke-P24Tests.ps1
```

P2.4 compatibility work is under `src/Cloudflare.Normalization/Compatibility` and is driven by normalized-model fixtures, not raw OpenAPI text or generated source diffs. The real API and projection reports are written under `artifacts/compatibility`.

## Project direction

- [Roadmap](./docs/roadmap.md): P1/P2 evidence and the P3–P5 production path.
- [Architecture](./docs/architecture.md): normalized API, corrections, PowerShell projection, generation, and shared runtime boundaries.
- [P3 plan](./docs/P3-plan.md): the current runtime-first implementation slices and acceptance criteria.
- [P3.3 plan](./docs/P3.3-plan.md): deterministic coverage discovery and the bounded D1 extension slice.
- [P3.3 projection-reduction plan](./docs/P3.3-projection-reduction-plan.md): blocker taxonomy, generic projection disambiguation, and public admission gates.
- [P3.3 projection-reduction summary](./docs/P3.3-projection-reduction-summary.md): admission/export parity repair and final PowerShell identity guard.
- [P3.3 public admission policy](./docs/P3.3-public-admission-policy.md): explicit gates separating technical readiness from public cmdlet admission.
- [P3.4 CI/package plan](./docs/P3.4-ci-packaging-plan.md): Windows-first validation, candidate packaging, and schema-update gates.
- [P3.4 CI/package plan](./docs/P3.4-ci-packaging-plan.md): Windows-first validation, candidate packaging, and schema-update gates.
- [Development principles](./docs/development-principles.md): durable rules for model, generator, runtime, and evidence work.

The current authoritative PowerShell surface is handwritten. Generated metadata must remain transport-neutral, and unresolved behavior—such as HTTP `2xx` with `success=false`—is not silently defined by the runtime.

The P3.4 CI foundation is available through `.github/workflows/p34-ci.yml`.
It produces a non-published module candidate after the existing deterministic,
regression, compatibility, and coverage gates pass. For local validation after
the Release build, run:

```powershell
pwsh -NoLogo -NoProfile -File .\tests\P34CiGates.Tests.ps1
```

The external pinned schema is bootstrapped and verified with:

```powershell
pwsh -NoLogo -NoProfile -File .\tools\Initialize-P34Schema.ps1
```
