[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $ProjectRoot 'tools/ReadOnlyStaging.ps1') -Library

$root = Join-Path ([IO.Path]::GetTempPath()) ('p32-staging-contract-' + [guid]::NewGuid().ToString('N'))
try {
    $inputRoot = Join-Path $root 'input'
    $stagingRoot = Join-Path $root 'staging'
    New-Item -ItemType Directory -Path (Join-Path $inputRoot '.git/objects/pack'), (Join-Path $inputRoot 'unrelated') -Force | Out-Null
    'required' | Set-Content -LiteralPath (Join-Path $inputRoot 'required-schema.json') -Encoding utf8NoBOM
    'fake-pack' | Set-Content -LiteralPath (Join-Path $inputRoot '.git/objects/pack/fake-pack') -Encoding utf8NoBOM
    ('x' * 1024) | Set-Content -LiteralPath (Join-Path $inputRoot 'unrelated/large-file.bin') -Encoding utf8NoBOM

    $expected = @('required-schema.json')
    Copy-ReadOnlyStagingFiles -SourceRoot $inputRoot -DestinationRoot $stagingRoot -RelativePaths $expected
    $inventory = @(Assert-ReadOnlyStagingInputContract -Root $stagingRoot -ExpectedRelativePaths $expected)
    if ($inventory.Count -ne 1 -or -not (Test-Path -LiteralPath (Join-Path $stagingRoot 'required-schema.json') -PathType Leaf)) { throw 'Required schema was not staged.' }
    if (Test-Path -LiteralPath (Join-Path $stagingRoot '.git') -PathType Any) { throw 'VCS metadata entered read-only staging.' }
    if (Test-Path -LiteralPath (Join-Path $stagingRoot 'unrelated') -PathType Any) { throw 'Unrelated input entered read-only staging.' }
    Write-Output 'PASS P3.2 staging negative contract excludes .git/** and unrelated files'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
