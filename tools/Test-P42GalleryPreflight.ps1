[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ModulePath,
    [string]$OutputPath,
    [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$module = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ModulePath).Path)

function Get-P42Property {
    param([AllowNull()]$Object, [Parameter(Mandatory)][string]$Name)
    if ($Object -is [Collections.IDictionary] -and $Object.Contains($Name)) { return $Object[$Name] }
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) { return $null }
    return $Object.PSObject.Properties[$Name].Value
}
function Write-P42Json {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
}

try {
    $manifestPath = Join-Path $module 'Cloudflare.PowerShell.psd1'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Gallery preflight manifest is missing: $manifestPath" }
    $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
    $psData = Get-P42Property (Get-P42Property $manifest 'PrivateData') 'PSData'
    $missing = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace([string](Get-P42Property $manifest 'ModuleVersion'))) { $missing.Add('ModuleVersion') }
    if ([string]::IsNullOrWhiteSpace([string](Get-P42Property $manifest 'Description'))) { $missing.Add('Description') }
    if ([string]::IsNullOrWhiteSpace([string](Get-P42Property $manifest 'Author'))) { $missing.Add('Author') }
    $licenseUri = [string](Get-P42Property $psData 'LicenseUri')
    $licenseFile = Join-Path $module 'license.txt'
    if ([string]::IsNullOrWhiteSpace($licenseUri) -and -not (Test-Path -LiteralPath $licenseFile -PathType Leaf)) { $missing.Add('LicenseUri-or-license.txt') }
    if ([string]::IsNullOrWhiteSpace([string](Get-P42Property $psData 'ProjectUri'))) { $missing.Add('ProjectUri') }
    $tags = @(Get-P42Property $psData 'Tags')
    if ($tags.Count -eq 0 -or @($tags | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -eq 0) { $missing.Add('Tags') }
    if ([string]::IsNullOrWhiteSpace([string](Get-P42Property $psData 'ReleaseNotes'))) { $missing.Add('ReleaseNotes') }

    $manifestError = $null
    try { Test-ModuleManifest -Path $manifestPath -ErrorAction Stop | Out-Null } catch { $manifestError = $_.Exception.Message }
    if ($null -ne $manifestError) { $missing.Add('Test-ModuleManifest') }

    $status = if ($missing.Count -eq 0) { 'Ready' } else { 'NotReady' }
    $report = [ordered]@{
        schemaVersion = 1
        stage = 'P4.2'
        status = $status
        publishAttempted = $false
        repository = 'PSGallery'
        apiKeyAccessed = $false
        modulePath = $module
        moduleVersion = [string](Get-P42Property $manifest 'ModuleVersion')
        prerelease = [string](Get-P42Property $psData 'Prerelease')
        missingMetadata = @($missing)
        manifestValidationError = $manifestError
    }
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) { Write-P42Json ([IO.Path]::GetFullPath($OutputPath)) $report }
    Write-Output "P4.2 Gallery preflight status=$status missing=$($missing -join ',') publishAttempted=false"
    if ($Strict -and $status -ne 'Ready') { exit 1 }
}
catch {
    Write-Error "P4.2 Gallery preflight failed: $($_.Exception.Message)"
    exit 1
}
