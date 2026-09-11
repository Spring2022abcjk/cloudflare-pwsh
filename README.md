# Cloudflare PowerShell SDK Prototype

This Windows-first prototype normalizes the pinned Cloudflare OpenAPI schema, applies API corrections, projects PowerShell metadata, and exercises a shared runtime with deterministic fixtures and mock HTTP.

## Support baseline

- PowerShell 7.6+
- .NET 10 (`TargetFramework=net10.0`)
- Windows-first development environment

The production projects and tests target .NET 10 to match the current PowerShell 7.6 `System.Management.Automation` host. The pinned `ref/` directory contains ignored external evidence and is not modified.

Run the current regression chain with:

```powershell
pwsh -NoLogo -NoProfile -File .\tools\Invoke-P24Tests.ps1
```

P2.4 compatibility work is under `src/Cloudflare.Normalization/Compatibility` and is driven by normalized-model fixtures, not raw OpenAPI text or generated source diffs. The real API and projection reports are written under `artifacts/compatibility`.
