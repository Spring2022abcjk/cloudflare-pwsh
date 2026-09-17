[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$VerifyOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
$pinPath = Join-Path $root 'build/pinned-schema.json'
if (-not (Test-Path -LiteralPath $pinPath -PathType Leaf)) { throw "P3.4 pinned schema manifest is missing: $pinPath" }
$pin = Get-Content -Raw -LiteralPath $pinPath | ConvertFrom-Json
if ([int]$pin.version -ne 1 -or [string]::IsNullOrWhiteSpace([string]$pin.repository) -or
    [string]::IsNullOrWhiteSpace([string]$pin.revision) -or [string]$pin.revision -notmatch '^[0-9a-fA-F]{40}$' -or
    [string]::IsNullOrWhiteSpace([string]$pin.sourcePath) -or [string]::IsNullOrWhiteSpace([string]$pin.sha256)) {
    throw 'P3.4 pinned schema manifest is invalid.'
}

$schemaRoot = Join-Path $root 'ref/api-schemas'
$schemaPath = Join-Path $schemaRoot ([string]$pin.sourcePath)

function Invoke-P34Git {
    param([Parameter(Mandatory)][string]$WorkingDirectory, [Parameter(Mandatory)][string[]]$Arguments)
    & git -C $WorkingDirectory @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed in '$WorkingDirectory'." }
}

function Assert-P34PinnedSchema {
    if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) { throw "Pinned schema file is missing: $schemaPath" }
    $actualHash = ((Get-FileHash -Algorithm SHA256 -LiteralPath $schemaPath).Hash).ToLowerInvariant()
    if ($actualHash -cne ([string]$pin.sha256).ToLowerInvariant()) {
        throw "Pinned schema SHA-256 mismatch. Expected '$($pin.sha256)', actual '$actualHash'."
    }
    try { $document = Get-Content -Raw -LiteralPath $schemaPath | ConvertFrom-Json } catch { throw "Pinned schema is not valid JSON: $schemaPath" }
    if ([string]$document.info.version -cne [string]$pin.sourceRevision) {
        throw "Pinned schema info.version mismatch. Expected '$($pin.sourceRevision)', actual '$($document.info.version)'."
    }
    $head = (& git -C $schemaRoot rev-parse HEAD 2>$null | Select-Object -First 1)
    if ([string]$head -notmatch '^[0-9a-fA-F]{40}$') {
        throw "Pinned schema checkout has no readable Git revision: $schemaRoot"
    }
    if ([string]$head -cne [string]$pin.revision) {
        throw "Pinned schema revision mismatch. Expected '$($pin.revision)', actual '$head'."
    }
}

if (Test-Path -LiteralPath $schemaPath -PathType Leaf) {
    Assert-P34PinnedSchema
    Write-Output "PASS P3.4 pinned schema revision=$($pin.revision) sourceRevision=$($pin.sourceRevision) sha256=$($pin.sha256)"
    return
}

if ($VerifyOnly) { throw "Pinned schema is not present in VerifyOnly mode: $schemaPath" }
if ((Test-Path -LiteralPath $schemaRoot -PathType Container) -and @(Get-ChildItem -LiteralPath $schemaRoot -Force).Count -gt 0) {
    throw "Schema destination is non-empty but does not contain the pinned schema: $schemaRoot"
}
New-Item -ItemType Directory -Force -Path $schemaRoot | Out-Null
Invoke-P34Git $schemaRoot @('init')
Invoke-P34Git $schemaRoot @('remote', 'add', 'origin', [string]$pin.repository)
Invoke-P34Git $schemaRoot @('fetch', '--depth', '1', 'origin', [string]$pin.revision)
Invoke-P34Git $schemaRoot @('checkout', '--detach', [string]$pin.revision)
Assert-P34PinnedSchema
Write-Output "PASS P3.4 fetched pinned schema revision=$($pin.revision) sourceRevision=$($pin.sourceRevision) sha256=$($pin.sha256)"
