[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-P35Test {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw "P3.5a validation test failed: $Message"
    }
}

$projectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$scriptPath = Join-Path $projectRoot 'tools/Invoke-P35ReadOnlyValidation.ps1'
Assert-P35Test (Test-Path -LiteralPath $scriptPath -PathType Leaf) 'read-only validation script is missing'

$source = Get-Content -Raw -LiteralPath $scriptPath
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$parseErrors) | Out-Null
Assert-P35Test ($parseErrors.Count -eq 0) 'read-only validation script does not parse'

foreach ($name in @(
        'CLOUDFLARE_POWERSHELL_INTEGRATION_TOKEN',
        'CLOUDFLARE_POWERSHELL_INTEGRATION_ACCOUNT_ID',
        'CLOUDFLARE_POWERSHELL_INTEGRATION_ZONE_ID')) {
    Assert-P35Test ($source.Contains($name, [StringComparison]::Ordinal)) "required configuration name '$name' is absent"
}

Assert-P35Test ($source -notmatch '(?i)CF_API_TOKEN|CF_API_WACS_TOKEN') 'legacy credential environment names are referenced'
Assert-P35Test ($source -notmatch '(?i)Invoke-RestMethod|Invoke-WebRequest') 'unapproved PowerShell web transport is referenced'
Assert-P35Test ($source -notmatch '(?i)HttpMethod\]::(Post|Put|Patch|Delete)') 'non-GET HTTP method is referenced'
Assert-P35Test ($source -notmatch '(?i)\b(New|Set|Remove)-Cf(?:DnsRecord|Zone)\b') 'mutation cmdlet is referenced'
Assert-P35Test ($source.Contains('CandidateModulePath', [StringComparison]::Ordinal)) 'candidate module path input is absent'
Assert-P35Test ($source.Contains('candidate-manifest.json', [StringComparison]::Ordinal)) 'candidate manifest check is absent'
Assert-P35Test ($source.Contains('SourceRevisionMatchesHead', [StringComparison]::Ordinal)) 'candidate source revision check is absent'
Assert-P35Test ($source.Contains('Import-Module -Name $moduleManifestPath', [StringComparison]::Ordinal)) 'candidate import is absent'
Assert-P35Test ($source.Contains("Get-Help -Name 'Get-CfDnsRecord'", [StringComparison]::Ordinal)) 'candidate help discovery is absent'

$credentialNames = @(
    'CLOUDFLARE_POWERSHELL_INTEGRATION_TOKEN',
    'CLOUDFLARE_POWERSHELL_INTEGRATION_ACCOUNT_ID',
    'CLOUDFLARE_POWERSHELL_INTEGRATION_ZONE_ID')
$savedValues = @{}
try {
    foreach ($name in $credentialNames) {
        $savedValues[$name] = [Environment]::GetEnvironmentVariable($name)
        Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
    }

    $captured = (& pwsh -NoLogo -NoProfile -File $scriptPath 2>&1 | Out-String)
    $exitCode = $LASTEXITCODE
} finally {
    foreach ($name in $credentialNames) {
        if ($null -eq $savedValues[$name]) {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        } else {
            Set-Item -LiteralPath "Env:$name" -Value $savedValues[$name]
        }
    }
}

Assert-P35Test ($exitCode -eq 2) 'missing configuration did not fail closed with exit code 2'
$result = $captured | ConvertFrom-Json
Assert-P35Test ([string]$result.Status -eq 'Blocked') 'missing configuration did not report Blocked'
Assert-P35Test ([int]$result.LiveRequestCount -eq 0) 'missing configuration attempted a live request'
Assert-P35Test ([string]$result.Candidate.Status -eq 'Blocked') 'missing candidate was not reported as Blocked'
Assert-P35Test ($captured -notmatch '(?i)Authorization|Bearer') 'authorization material appeared in blocked output'
Assert-P35Test ($captured -notmatch '(?i)CF_API_TOKEN|CF_API_WACS_TOKEN') 'legacy environment names appeared in blocked output'

$savedValues = @{}
try {
    foreach ($name in $credentialNames) {
        $savedValues[$name] = [Environment]::GetEnvironmentVariable($name)
    }
    Set-Item -LiteralPath 'Env:CLOUDFLARE_POWERSHELL_INTEGRATION_TOKEN' -Value 'p35a-static-test-token'
    Set-Item -LiteralPath 'Env:CLOUDFLARE_POWERSHELL_INTEGRATION_ACCOUNT_ID' -Value 'account-scope-placeholder'
    Remove-Item -LiteralPath 'Env:CLOUDFLARE_POWERSHELL_INTEGRATION_ZONE_ID' -ErrorAction SilentlyContinue
    $missingScopeCaptured = (& pwsh -NoLogo -NoProfile -File $scriptPath 2>&1 | Out-String)
    $missingScopeExitCode = $LASTEXITCODE
} finally {
    foreach ($name in $credentialNames) {
        if ($null -eq $savedValues[$name]) {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        } else {
            Set-Item -LiteralPath "Env:$name" -Value $savedValues[$name]
        }
    }
}

Assert-P35Test ($missingScopeExitCode -eq 2) 'missing explicit scope did not fail closed with exit code 2'
$missingScopeResult = $missingScopeCaptured | ConvertFrom-Json
Assert-P35Test (@($missingScopeResult.MissingConfiguration) -contains 'CLOUDFLARE_POWERSHELL_INTEGRATION_ZONE_ID') 'missing explicit zone scope was not reported'
Assert-P35Test ([int]$missingScopeResult.LiveRequestCount -eq 0) 'missing explicit scope attempted a scoped request'
Assert-P35Test (-not $missingScopeCaptured.Contains('p35a-static-test-token', [StringComparison]::Ordinal)) 'test token appeared in missing-scope output'

foreach ($name in @('CF_API_TOKEN', 'CF_API_WACS_TOKEN')) {
    $legacyValue = [Environment]::GetEnvironmentVariable($name)
    if (-not [string]::IsNullOrEmpty($legacyValue)) {
        Assert-P35Test (-not $captured.Contains($legacyValue, [StringComparison]::Ordinal)) "legacy secret from $name appeared in blocked output"
    }
}

Write-Output 'PASS P3.5a read-only validation parser, GET-only boundary, candidate gate, and fail-closed behavior'
