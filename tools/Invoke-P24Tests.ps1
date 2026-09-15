[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$SchemaRoot = (Join-Path $ProjectRoot 'ref/api-schemas'),
    [string]$ArtifactRoot = (Join-Path $ProjectRoot 'artifacts/compatibility'),
    [string]$SchemaRevisionManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Push-Location $ProjectRoot
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p24-' + [guid]::NewGuid().ToString('N'))

function Write-PortablePreviousSchema {
    param(
        [Parameter(Mandatory)][string]$CurrentSchemaPath,
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$OutputPath
    )
    $manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
    if ([int]$manifest.version -ne 1 -or [string]::IsNullOrWhiteSpace([string]$manifest.previousRevision) -or [string]::IsNullOrWhiteSpace([string]$manifest.currentRevision)) {
        throw 'Portable P2.4 schema revision manifest is invalid.'
    }
    function Get-PortableJsonChild {
        param([Parameter(Mandatory)][Text.Json.Nodes.JsonNode]$Node, [Parameter(Mandatory)][string]$Token)
        $child = $null
        if ($Node -is [Text.Json.Nodes.JsonArray]) {
            $child = ([Collections.Generic.IList[Text.Json.Nodes.JsonNode]]$Node)[[int]$Token]
        }
        else {
            $child = ([Collections.Generic.IDictionary[string, Text.Json.Nodes.JsonNode]]$Node).get_Item($Token)
        }
        Write-Output -NoEnumerate $child
    }
    $document = [Text.Json.Nodes.JsonNode]::Parse([IO.File]::ReadAllText($CurrentSchemaPath))
    foreach ($operation in @($manifest.operations)) {
        if ([string]$operation.op -notin @('replace', 'remove')) { throw "Portable P2.4 schema revision operation is unsupported: $($operation.op)" }
        $tokens = @(([string]$operation.path).TrimStart('/') -split '/' | ForEach-Object { $_.Replace('~1', '/').Replace('~0', '~') })
        if ($tokens.Count -eq 0 -or [string]::IsNullOrWhiteSpace($tokens[0])) { throw 'Portable P2.4 schema revision JSON pointer is invalid.' }
        $parent = $document
        for ($index = 0; $index -lt $tokens.Count - 1; $index++) {
            $token = $tokens[$index]
            $parent = Get-PortableJsonChild -Node $parent -Token $token
            if ($null -eq $parent) { throw "Portable P2.4 schema revision path does not exist: $($operation.path)" }
        }
        $last = $tokens[$tokens.Count - 1]
        if ([string]$operation.op -eq 'remove') {
            if (-not ($parent -is [Text.Json.Nodes.JsonArray])) { throw "Portable P2.4 schema revision remove requires an array path: $($operation.path)" }
            ([Collections.Generic.IList[Text.Json.Nodes.JsonNode]]$parent).RemoveAt([int]$last)
        }
        else {
            $replacement = if ($null -eq $operation.value) { [Text.Json.Nodes.JsonValue]::Create($null) } else { [Text.Json.Nodes.JsonValue]::Create([string]$operation.value) }
            if ($parent -is [Text.Json.Nodes.JsonArray]) {
                ([Collections.Generic.IList[Text.Json.Nodes.JsonNode]]$parent)[[int]$last] = $replacement
            }
            else {
                ([Collections.Generic.IDictionary[string, Text.Json.Nodes.JsonNode]]$parent)[$last] = $replacement
            }
        }
    }
    $options = [Text.Json.JsonSerializerOptions]::new()
    $options.WriteIndented = $false
    [IO.File]::WriteAllText($OutputPath, $document.ToJsonString($options), [Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{ OldRevision = [string]$manifest.previousRevision; NewRevision = [string]$manifest.currentRevision }
}

try {
    $null = New-Item -ItemType Directory -Path $temporaryRoot -Force
    $newSchemaPath = Join-Path $SchemaRoot 'openapi.json'
    if (-not (Test-Path -LiteralPath $newSchemaPath -PathType Leaf)) { throw "Current P2.4 schema is missing: $newSchemaPath" }
    if (-not [string]::IsNullOrWhiteSpace($SchemaRevisionManifestPath)) {
        if (-not (Test-Path -LiteralPath $SchemaRevisionManifestPath -PathType Leaf)) { throw "Portable P2.4 schema revision manifest is missing: $SchemaRevisionManifestPath" }
        $manifestResult = Write-PortablePreviousSchema -CurrentSchemaPath $newSchemaPath -ManifestPath $SchemaRevisionManifestPath -OutputPath (Join-Path $temporaryRoot 'portable-previous-openapi.json')
        $oldRevision = $manifestResult.OldRevision
        $newRevision = $manifestResult.NewRevision
        $oldPath = Join-Path $temporaryRoot 'portable-previous-openapi.json'
        $newPath = Join-Path $temporaryRoot ($newRevision + '-openapi.json')
        Copy-Item -LiteralPath $newSchemaPath -Destination $newPath -Force
        Write-Output "P2.4 portable revision inputs: $oldRevision -> $newRevision (no schema Git metadata required)"
    }
    else {
        $revisions = @(& git -C $SchemaRoot rev-list --max-count=2 HEAD -- openapi.json)
        if ($LASTEXITCODE -ne 0 -or $revisions.Count -ne 2) { throw 'Could not resolve two schema revisions for the P2.4 real diff.' }
        $newRevision = [string]$revisions[0]
        $oldRevision = [string]$revisions[1]
        $oldPath = Join-Path $temporaryRoot ($oldRevision + '-openapi.json')
        $newPath = Join-Path $temporaryRoot ($newRevision + '-openapi.json')
        & git -C $SchemaRoot show "$oldRevision`:openapi.json" | Set-Content -LiteralPath $oldPath -Encoding utf8 -NoNewline
        if ($LASTEXITCODE -ne 0) { throw "Could not materialize old schema revision $oldRevision." }
        Copy-Item -LiteralPath $newSchemaPath -Destination $newPath -Force
    }

    dotnet restore .\Cloudflare.P1.sln | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'dotnet restore failed.' }
    dotnet clean .\Cloudflare.P1.sln --configuration Release | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'dotnet clean failed.' }
    dotnet restore .\Cloudflare.P1.sln | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'dotnet restore after clean failed.' }
    dotnet build .\Cloudflare.P1.sln --configuration Release --no-restore | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'dotnet build failed.' }

    dotnet run --project .\tests\Cloudflare.P24.Tests\Cloudflare.P24.Tests.csproj --configuration Release --no-build | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'P2.4 synthetic compatibility suite failed.' }
    & pwsh -NoLogo -NoProfile -File .\tools\Invoke-P23Tests.ps1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'P2.3 and earlier regression suites failed.' }

    $null = New-Item -ItemType Directory -Path $ArtifactRoot -Force
    $projectionPolicyPath = Join-Path $ProjectRoot 'overrides/powershell-p23-projection.json'
    $projectionArtifactRoot = Join-Path $ArtifactRoot 'projection'
    dotnet run --project .\tests\Cloudflare.P24.Tests\Cloudflare.P24.Tests.csproj --configuration Release --no-build -- $oldPath $newPath $ArtifactRoot $oldRevision $newRevision $projectionPolicyPath $projectionArtifactRoot | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'P2.4 real schema revision diff failed.' }
    Write-Output "PASS P2.4 including net10 baseline, P2.3 and earlier regression suites"
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
    Pop-Location
}
