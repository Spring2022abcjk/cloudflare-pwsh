# Support Matrix

## Declared baseline

| Dimension | Declared boundary | Evidence |
| --- | --- | --- |
| Operating-system family | Windows-first | Project and CI baseline are Windows-oriented; no non-Windows support is declared. |
| PowerShell | PowerShell 7.6 or newer | Module manifest and P3.4 host check. |
| .NET | .NET 10 / `net10.0` | Project files, `global.json`, and P3.4 host check. |

## Environment claims

- Windows 10 is locally evidenced by the current host validation environment;
  this is not a complete release matrix.
- Windows 11 and Windows Server are not declared as formally supported until a
  reproducible host/package acceptance run records those environments.
- Linux and macOS are not declared supported. The project may contain portable
  .NET code, but portability is not an acceptance claim.
- GitHub-hosted `windows-2025` is the intended remote CI environment, but this
  P4.2 branch has no remote workflow run evidence yet.

## Release-note requirement

Every future release note must state the tested OS/PowerShell/.NET combination
and must not turn an untested platform into a support claim.
