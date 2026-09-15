# ADR 0001: .NET 10 and PowerShell 7.6 Baseline

## Context

P2.3 proved that the current PowerShell 7.6 host loads `System.Management.Automation` built against .NET 10. The isolated binary-cmdlet experiment could not be referenced from the production net8 projects: the host assembly produced `CS1705` because it required a newer `System.Runtime`.

The production module is a PowerShell module with a .NET runtime assembly, and the repository's normalization and test projects are part of the same build and verification chain. Keeping production at net8 while the experiment targets net10 creates a misleading dual baseline and leaves hard-coded net8 output paths.

## Decision

All production, normalization, test, and binary-cmdlet experiment projects target `net10.0`. The supported PowerShell baseline is PowerShell 7.6+ on the Windows-first development host. Build/test scripts derive output paths from project target-framework metadata instead of hard-coding a framework moniker.

The production assembly and the isolated binary-cmdlet experiment use `System.Management.Automation` 7.6.0 as a private, build-only NuGet reference with runtime assets excluded. The module does not carry SMA or the PowerShell engine; a supported `pwsh` host supplies SMA when the module is imported. `PowerShellHome`/`HintPath` is not part of the build contract.

## Alternatives considered

- Keep production at net8 and experiment at net10: rejected because it preserves the observed `CS1705` mismatch and a dual target baseline.
- Add a net8 compatibility workaround or downgrade the PowerShell host reference: rejected because it hides the actual supported host dependency.
- Multi-target net8/net10: deferred/rejected for this Windows-first prototype because no requirement currently establishes net8 compatibility and it would expand build/test complexity.

## Consequences

- The full project and test chain now uses the same .NET target as the PowerShell host.
- Existing users on older PowerShell/.NET combinations are no longer implicitly claimed as compatible.
- The production module remains a binary-cmdlet module with a script-module manifest; P2.3 runtime migration remains a separate decision.
- Existing `CS1705` evidence is retained as the historical reason for migration.

## Compatibility impact

This is a deliberate support-baseline change. PowerShell 7.6+ and .NET 10 are required for the repository's build and binary-cmdlet experiment. The ignored upstream evidence under `ref/` remains outside this target-framework migration.
