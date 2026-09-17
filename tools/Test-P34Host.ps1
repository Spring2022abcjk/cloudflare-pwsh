[CmdletBinding()]
param(
    [version]$MinimumPowerShellVersion = [version]'7.6.0',
    [int]$RequiredDotNetMajor = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) { throw 'P3.4 CI requires the formal Windows-first host baseline.' }
if ($PSVersionTable.PSVersion -lt $MinimumPowerShellVersion) {
    throw "PowerShell $MinimumPowerShellVersion or newer is required; current host is $($PSVersionTable.PSVersion)."
}
$dotnetText = (& dotnet --version | Select-Object -First 1).Trim()
if ([string]::IsNullOrWhiteSpace($dotnetText)) { throw 'Could not resolve the dotnet SDK version.' }
try { $dotnetVersion = [version]$dotnetText } catch { throw "dotnet returned an invalid SDK version: $dotnetText" }
if ($dotnetVersion.Major -ne $RequiredDotNetMajor) {
    throw ".NET $RequiredDotNetMajor is required; current SDK is $dotnetVersion."
}
Write-Output "PASS P3.4 Windows host PowerShell=$($PSVersionTable.PSVersion) dotnet=$dotnetVersion requiredDotnetMajor=$RequiredDotNetMajor"
