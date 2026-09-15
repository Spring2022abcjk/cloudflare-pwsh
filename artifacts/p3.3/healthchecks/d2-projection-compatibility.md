# P3.3-projection Compatibility Report

- Old source revision: `P3.2-public-surface`
- New source revision: `P3.3-d2-healthchecks`
- Changes: `4`
- Fully compatible: `False`

## Impact summary

| Dimension | Impact | Count |
| --- | --- | ---: |
| Api | Behavioral | 0 |
| Api | Breaking | 0 |
| Api | NonBreaking | 0 |
| Api | None | 4 |
| Api | PotentiallyBreaking | 0 |
| Api | Unknown | 0 |
| PowerShell | Behavioral | 0 |
| PowerShell | Breaking | 0 |
| PowerShell | NonBreaking | 4 |
| PowerShell | None | 0 |
| PowerShell | PotentiallyBreaking | 0 |
| PowerShell | Unknown | 0 |
| Sdk | Behavioral | 0 |
| Sdk | Breaking | 0 |
| Sdk | NonBreaking | 0 |
| Sdk | None | 4 |
| Sdk | PotentiallyBreaking | 0 |
| Sdk | Unknown | 0 |

## Changes

| Kind | Resource | Operation | Schema | Path | API | SDK | PowerShell | Old | New | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CmdletAdded |  | Get-CfHealthCheck |  | cmdlets[Get-CfHealthCheck] | None | None | NonBreaking | missing | present | projection cmdlet added |
| CmdletAdded |  | New-CfHealthCheck |  | cmdlets[New-CfHealthCheck] | None | None | NonBreaking | missing | present | projection cmdlet added |
| CmdletAdded |  | Remove-CfHealthCheck |  | cmdlets[Remove-CfHealthCheck] | None | None | NonBreaking | missing | present | projection cmdlet added |
| CmdletAdded |  | Set-CfHealthCheck |  | cmdlets[Set-CfHealthCheck] | None | None | NonBreaking | missing | present | projection cmdlet added |
