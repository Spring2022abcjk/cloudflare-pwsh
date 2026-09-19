[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory)][string]$CandidateRoot,
    [switch]$RequireCleanWorktree
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
$candidate = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $CandidateRoot).Path)

function Assert-P42Provenance {
    param([bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}
function Get-P42Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    return ((Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash).ToLowerInvariant()
}
function Get-P42Json {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Label)
    Assert-P42Provenance (Test-Path -LiteralPath $Path -PathType Leaf) "$Label is missing: $Path"
    try { return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json } catch { throw "$Label is not valid JSON: $Path" }
}

try {
    $manifest = Get-P42Json (Join-Path $candidate 'candidate-manifest.json') 'candidate manifest'
    $summary = Get-P42Json (Join-Path $candidate 'build-test-summary.json') 'candidate build summary'
    Assert-P42Provenance ([int]$manifest.schemaVersion -eq 1 -and [string]$manifest.stage -ceq 'P3.4' -and [string]$manifest.status -ceq 'Candidate') 'Candidate manifest has an unsupported identity or status.'
    Assert-P42Provenance ([string]$summary.stage -ceq 'P3.4' -and [string]$summary.status -ceq 'Passed') 'Candidate build summary is not a passed P3.4 summary.'
    $sourceRevision = ((& git -C $root rev-parse HEAD 2>$null) -join "`n").Trim()
    Assert-P42Provenance ($LASTEXITCODE -eq 0 -and [string]$manifest.sourceRevision -ceq $sourceRevision) 'Candidate source revision is not bound to the checked-out commit.'
    if ($RequireCleanWorktree) {
        $status = @(& git -C $root status --porcelain --untracked-files=all)
        Assert-P42Provenance ($status.Count -eq 0) "Release provenance requires a clean worktree; found $($status.Count) tracked/untracked change row(s)."
    }

    $props = [xml](Get-Content -Raw -LiteralPath (Join-Path $root 'Directory.Build.props'))
    $versionString = ([version][string]$props.Project.PropertyGroup.VersionPrefix).ToString(3)
    Assert-P42Provenance ([string]$manifest.packageVersion -ceq $versionString -and [string]$summary.packageVersion -ceq $versionString) 'Candidate and build-summary package versions do not match VersionPrefix.'
    Assert-P42Provenance ([string]$manifest.versionSource -ceq 'Directory.Build.props:VersionPrefix') 'Candidate version source is not canonical.'

    $pin = Get-P42Json (Join-Path $root 'build/pinned-schema.json') 'pinned schema manifest'
    foreach ($field in @('revision', 'sourceRevision', 'sourcePath', 'sha256')) {
        Assert-P42Provenance ([string]$manifest.schemaIdentity.$field -ceq [string]$pin.$field) "Candidate schema identity '$field' differs from the pinned manifest."
        Assert-P42Provenance ([string]$summary.schemaIdentity.$field -ceq [string]$pin.$field) "Build summary schema identity '$field' differs from the pinned manifest."
    }

    $archivePath = Join-Path $candidate ([string]$manifest.archivePath)
    Assert-P42Provenance (Test-Path -LiteralPath $archivePath -PathType Leaf) 'Candidate archive is missing.'
    Assert-P42Provenance ((Get-P42Sha256 $archivePath) -ceq [string]$manifest.archiveSha256) 'Candidate archive SHA-256 differs from candidate-manifest.json.'

    $moduleRoot = Join-Path $candidate ([string]$manifest.modulePath)
    $moduleFiles = @(Get-ChildItem -LiteralPath $moduleRoot -File | Sort-Object Name)
    $manifestFiles = @($manifest.moduleFiles | Sort-Object path)
    Assert-P42Provenance ($moduleFiles.Count -eq $manifestFiles.Count) 'Candidate module file count differs from provenance manifest.'
    foreach ($entry in $manifestFiles) {
        $relative = ([string]$entry.path).Replace('/', [IO.Path]::DirectorySeparatorChar)
        $path = Join-Path $candidate $relative
        Assert-P42Provenance (Test-Path -LiteralPath $path -PathType Leaf) "Candidate provenance file is missing: $($entry.path)"
        Assert-P42Provenance ((Get-P42Sha256 $path) -ceq [string]$entry.sha256) "Candidate file hash differs: $($entry.path)"
        Assert-P42Provenance ((Get-Item -LiteralPath $path).Length -eq [int64]$entry.length) "Candidate file length differs: $($entry.path)"
    }

    foreach ($entry in @($summary.reportFiles)) {
        $path = Join-Path $candidate ([string]$entry.path -replace '/', [IO.Path]::DirectorySeparatorChar)
        Assert-P42Provenance (Test-Path -LiteralPath $path -PathType Leaf) "Candidate report is missing: $($entry.path)"
        Assert-P42Provenance ((Get-P42Sha256 $path) -ceq [string]$entry.sha256) "Candidate report hash differs: $($entry.path)"
        Assert-P42Provenance ((Get-Item -LiteralPath $path).Length -eq [int64]$entry.length) "Candidate report length differs: $($entry.path)"
    }
    foreach ($gate in @(@{ Name = 'compatibility'; Receipt = 'compatibility-gate.json'; Input = 'compatibility-report.json' }, @{ Name = 'coverage'; Receipt = 'coverage-gate.json'; Input = 'coverage-report.json' })) {
        $receiptPath = Join-Path $candidate "reports/$($gate.Receipt)"
        $inputPath = Join-Path $candidate "reports/$($gate.Input)"
        $receipt = Get-P42Json $receiptPath "$($gate.Name) gate receipt"
        Assert-P42Provenance ([string]$receipt.status -ceq 'Passed') "$($gate.Name) gate receipt is not Passed."
        Assert-P42Provenance ((Get-P42Sha256 $receiptPath) -ceq [string]$manifest.gateReceipts.($gate.Name).sha256) "$($gate.Name) gate receipt hash is not bound."
        Assert-P42Provenance ((Get-P42Sha256 $inputPath) -ceq [string]$manifest.gateReceipts.($gate.Name).inputReportSha256) "$($gate.Name) input report hash is not bound."
    }

    $dll = Join-Path $moduleRoot 'Cloudflare.PowerShell.dll'
    $assemblyInfo = @([Reflection.Assembly]::LoadFile($dll).GetCustomAttributes($false) | Where-Object { $_ -is [Reflection.AssemblyInformationalVersionAttribute] })
    Assert-P42Provenance ($assemblyInfo.Count -eq 1 -and [string]$assemblyInfo[0].InformationalVersion -ceq [string]$manifest.assemblyInformationalVersion) 'Assembly informational version is not bound to candidate provenance.'

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $entries = @($zip.Entries | ForEach-Object FullName | Sort-Object)
        $expectedEntries = @($moduleFiles | ForEach-Object { "$($manifest.packageName)/$($_.Name)" } | Sort-Object)
        Assert-P42Provenance (($entries -join '|') -ceq ($expectedEntries -join '|')) 'Candidate ZIP entries do not match the exact module boundary.'
    }
    finally { $zip.Dispose() }

    $secretPattern = '(?i)(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{20,}|Bearer\s+[A-Za-z0-9._~-]{20,})'
    foreach ($file in @(Get-ChildItem -LiteralPath $candidate -Recurse -File | Where-Object Extension -in @('.json', '.md', '.psd1', '.psm1', '.xml'))) {
        $text = Get-Content -Raw -LiteralPath $file.FullName
        Assert-P42Provenance ($text -notmatch $secretPattern) "Candidate file appears to contain a secret-shaped value: $($file.FullName)"
    }
    Write-Output "PASS P4.2 candidate provenance archiveSha256=$($manifest.archiveSha256) sourceRevision=$sourceRevision"
}
catch {
    Write-Error "P4.2 package provenance validation failed: $($_.Exception.Message)"
    exit 1
}
