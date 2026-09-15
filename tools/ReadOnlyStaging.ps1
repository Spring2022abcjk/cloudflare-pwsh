[CmdletBinding()]
param([switch]$Library)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ReadOnlyStagingVcsDirectoryNames = @('.git', '.svn', '.hg', '.bzr')
$script:ReadOnlyStagingForbiddenDirectoryNames = @(
    '.git', '.svn', '.hg', '.bzr',
    'bin', 'obj',
    'cache', 'caches',
    'log', 'logs',
    'temp', 'tmp'
)

function ConvertTo-ReadOnlyStagingRelativePath {
    param([Parameter(Mandatory)][string]$Path)
    if ([IO.Path]::IsPathRooted($Path)) { throw "Staging allowlist path must be relative: $Path" }
    $normalized = $Path.Replace('\', '/')
    $parts = @($normalized -split '/')
    if ($parts.Count -eq 0 -or @($parts | Where-Object { [string]::IsNullOrWhiteSpace($_) -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
        throw "Staging allowlist path is invalid: $Path"
    }
    if (@($parts | Where-Object { $script:ReadOnlyStagingVcsDirectoryNames -contains $_ }).Count -gt 0) {
        throw "Staging allowlist cannot contain VCS metadata: $Path"
    }
    return $normalized
}

function Copy-ReadOnlyStagingFiles {
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$DestinationRoot,
        [Parameter(Mandatory)][string[]]$RelativePaths
    )
    $sourceRootFull = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $SourceRoot).Path)
    $null = New-Item -ItemType Directory -Path $DestinationRoot -Force
    foreach ($relativePath in @($RelativePaths | ForEach-Object { ConvertTo-ReadOnlyStagingRelativePath $_ } | Sort-Object -Unique)) {
        $sourcePath = Join-Path $sourceRootFull $relativePath
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Required staging input is missing: $sourcePath" }
        $destinationPath = Join-Path $DestinationRoot $relativePath
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPath) -Force
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    }
}

function Get-ReadOnlyStagingInventory {
    param([Parameter(Mandatory)][string]$Root)
    $rootFull = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Root).Path)
    foreach ($file in @(Get-ChildItem -LiteralPath $rootFull -File -Recurse -Force -ErrorAction Stop)) {
        [pscustomobject]@{
            RelativePath = ([IO.Path]::GetRelativePath($rootFull, $file.FullName)).Replace('\', '/')
            Length = [int64]$file.Length
        }
    }
}

function Get-ReadOnlyStagingDiagnostics {
    param([Parameter(Mandatory)][string]$Root)
    $inventory = @(Get-ReadOnlyStagingInventory -Root $Root)
    [pscustomobject]@{
        FileCount = $inventory.Count
        TotalBytes = [int64](($inventory | Measure-Object -Property Length -Sum).Sum)
        Files = $inventory
    }
}

function Assert-ReadOnlyStagingInputContract {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$ExpectedRelativePaths
    )
    $expected = @($ExpectedRelativePaths | ForEach-Object { ConvertTo-ReadOnlyStagingRelativePath $_ } | Sort-Object -Unique)
    $inventory = @(Get-ReadOnlyStagingInventory -Root $Root)
    $actual = @($inventory | ForEach-Object RelativePath | Sort-Object -Unique)
    $forbidden = @($actual | Where-Object {
        $parts = $_ -split '/'
        @($parts | Where-Object { $script:ReadOnlyStagingForbiddenDirectoryNames -contains $_ }).Count -gt 0
    })
    if ($forbidden.Count -gt 0) { throw "Read-only staging contains forbidden VCS/build/cache/log/temp input: $($forbidden -join ', ')" }

    $expectedSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $actualSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $expected) { [void]$expectedSet.Add($path) }
    foreach ($path in $actual) { [void]$actualSet.Add($path) }
    $missing = @($expected | Where-Object { -not $actualSet.Contains($_) })
    $unexpected = @($actual | Where-Object { -not $expectedSet.Contains($_) })
    if ($missing.Count -gt 0 -or $unexpected.Count -gt 0) {
        throw "Read-only staging input contract drifted. Missing: $($missing -join ', '); unexpected: $($unexpected -join ', ')."
    }
    return $inventory
}
