[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ArtifactPath = (Join-Path $ProjectRoot 'artifacts/p3.3/CmdletModel.json'),
    [string]$NormalizedPath = (Join-Path $ProjectRoot 'fixtures/p3.3/d1-database/document.json'),
    [string]$TemplatePath = (Join-Path $ProjectRoot 'tools/templates/P32RepresentativeCmdlets.cs.tmpl'),
    [string]$SourcePath = (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Cmdlets/P33D1DatabaseCmdlets.cs'),
    [string]$GeneratedRoot = (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated'),
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$p33ProjectRoot = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
$p33ArtifactPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ArtifactPath).Path)
$p33NormalizedPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $NormalizedPath).Path)
$p33TemplatePath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $TemplatePath).Path)
$p33SourcePath = if ([IO.Path]::IsPathRooted($SourcePath)) { [IO.Path]::GetFullPath($SourcePath) } else { Join-Path $p33ProjectRoot $SourcePath }
$p33GeneratedRoot = if ([IO.Path]::IsPathRooted($GeneratedRoot)) { [IO.Path]::GetFullPath($GeneratedRoot) } else { Join-Path $p33ProjectRoot $GeneratedRoot }

# Reuse the P3.2 capability-driven renderer as a library. The P3.3 artifact
# supplies the operation metadata; this script does not identify operations or
# resources in renderer conditionals.
. (Join-Path $PSScriptRoot 'Generate-P32Source.ps1') -ProjectRoot $p33ProjectRoot -Library
. (Join-Path $PSScriptRoot 'P33ModelSchemaParity.ps1')

function Assert-P33ArtifactFresh {
    param([Parameter(Mandatory)][object]$Artifact)
    if ([int]$Artifact.version -ne 1 -or [string]$Artifact.stage -ne 'P3.3' -or [string]$Artifact.sourcePolicy -ne 'normalized-model-plus-projection-policy' -or [string]$Artifact.semanticAlgorithm -ne 'SHA256-CanonicalJson-v1') {
        throw 'P3.3 canonical artifact is not a supported normalized/projection output.'
    }
    foreach ($source in @($Artifact.sourceFiles)) {
        $path = Join-Path $p33ProjectRoot ([string]$source.path)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "P3.3 canonical artifact source is missing: $path" }
        $actual = Get-P32PortableFileHash -Path $path
        if ($actual -ne [string]$source.sha256) { throw "P3.3 canonical artifact is stale for '$($source.path)'. Run Project-P33D1Projection.ps1 first." }
    }
    $digest = Get-P32CanonicalDigest $Artifact
    if ([string]$Artifact.canonicalDigest -ne $digest) { throw "P3.3 canonical artifact semantic digest is invalid. Expected '$digest', actual '$($Artifact.canonicalDigest)'." }
}

function Assert-P33ArtifactContract {
    param([Parameter(Mandatory)][object]$Artifact)
    $actualOperationIds = @($Artifact.cmdlets | ForEach-Object operations | ForEach-Object operationId)
    if ($actualOperationIds.Count -eq 0 -or (@($actualOperationIds | Sort-Object -Unique).Count -ne $actualOperationIds.Count)) { throw 'P3.3 artifact operation ids must be present and unique.' }
    foreach ($cmdlet in @($Artifact.cmdlets)) {
        foreach ($parameter in @($cmdlet.parameters)) {
            if ([string]$parameter.type -eq 'object' -or [string]$parameter.type -eq 'System.Object') { throw "P3.3 parameter '$($parameter.name)' was degraded to object." }
        }
    }
    Assert-ArtifactContract $Artifact
}

function Assert-P33ArtifactModelParity {
    param([Parameter(Mandatory)][object]$Artifact, [Parameter(Mandatory)][object]$Normalized)
    $schemas = @{}
    foreach ($property in $Normalized.schemas.PSObject.Properties) { $schemas[$property.Name] = $property.Value }
    $models = @($Artifact.models)
    if ($models.Count -eq 0) { throw 'P3.3 canonical artifact has no typed models.' }
    foreach ($model in $models) {
        [void](ConvertTo-P33ModelProjection $model $schemas $models ([IO.Path]::GetRelativePath($p33ProjectRoot, $p33NormalizedPath).Replace('\', '/')) $null)
    }
}

function Assert-P33GeneratedModelsFresh {
    param([Parameter(Mandatory)][object]$Artifact)

    $stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p33-model-validation-' + [guid]::NewGuid().ToString('N'))
    try {
        foreach ($model in @($Artifact.models)) {
            $relativePath = [string]$model.path
            if ([string]::IsNullOrWhiteSpace($relativePath)) { throw "P3.3 model '$($model.className)' has no generated path." }
            $existingPath = Join-Path (Join-Path $p33GeneratedRoot 'Models') ([IO.Path]::GetFileName($relativePath))
            if (-not (Test-Path -LiteralPath $existingPath -PathType Leaf)) { throw "P3.3 ValidateOnly generated model is missing: $existingPath" }

            $expectedPath = Join-Path $stagingRoot $relativePath
            Write-GeneratedModel $model $expectedPath
            $expected = Normalize-GeneratedSource (Get-Content -Raw -LiteralPath $expectedPath -Encoding UTF8)
            $actual = Normalize-GeneratedSource (Get-Content -Raw -LiteralPath $existingPath -Encoding UTF8)
            $expectedHash = ([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($expected)) | ForEach-Object ToString x2) -join ''
            $actualHash = ([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($actual)) | ForEach-Object ToString x2) -join ''
            if ($expectedHash -ne $actualHash -or $expected -cne $actual) {
                throw "P3.3 generated model drifted for '$existingPath'. Expected SHA256 '$expectedHash', actual '$actualHash'."
            }
        }
    }
    finally {
        if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

if (-not (Test-Path -LiteralPath $p33ArtifactPath -PathType Leaf)) { throw "P3.3 canonical artifact is missing: $p33ArtifactPath" }
if (-not (Test-Path -LiteralPath $p33NormalizedPath -PathType Leaf)) { throw "P3.3 normalized fixture is missing: $p33NormalizedPath" }
if (-not (Test-Path -LiteralPath $p33TemplatePath -PathType Leaf)) { throw "P3.3 source template is missing: $p33TemplatePath" }
$artifact = Get-Content -Raw -LiteralPath $p33ArtifactPath | ConvertFrom-Json
$normalized = Get-Content -Raw -LiteralPath $p33NormalizedPath | ConvertFrom-Json
Assert-P33ArtifactModelParity $artifact $normalized
Assert-P33ArtifactFresh $artifact
if ($ValidateOnly) { Assert-P33GeneratedModelsFresh $artifact }
Assert-P33ArtifactContract $artifact
$template = Get-Content -Raw -LiteralPath $p33TemplatePath -Encoding UTF8
if ($template -notmatch '\{\{P32_CMDLETS\}\}') { throw 'P3.3 source template is missing the shared renderer token.' }

$lines = [System.Collections.Generic.List[string]]::new()
foreach ($cmdlet in @($artifact.cmdlets)) { Add-GeneratedCmdlet -Lines ([ref]$lines) -Cmdlet $cmdlet }
$rendered = $template.Replace('{{P32_CMDLETS}}', (($lines -join "`n").TrimEnd([char[]]"`r`n")))
if ($rendered -match '\{\{[^}]+\}\}') { throw 'P3.3 generated source contains unresolved template tokens.' }

$sourceExists = Test-Path -LiteralPath $p33SourcePath -PathType Leaf
if ($ValidateOnly -and -not $sourceExists) { throw "P3.3 ValidateOnly source is missing: $p33SourcePath" }
$sourceForValidation = if ($ValidateOnly -and $sourceExists) { Get-Content -Raw -LiteralPath $p33SourcePath -Encoding UTF8 } else { $rendered }
foreach ($cmdlet in @($artifact.cmdlets)) {
    if ($sourceForValidation -notmatch "public sealed class $([regex]::Escape([string]$cmdlet.className))\s*:") { throw "Generated P3.3 source is missing '$($cmdlet.className)'." }
    foreach ($parameter in @($cmdlet.parameters)) {
        $declaration = "public $([regex]::Escape([string]$parameter.type)) $([regex]::Escape([string]$parameter.name))\s*\{"
        if ($sourceForValidation -notmatch $declaration) { throw "Generated P3.3 source does not consume parameter '$($parameter.name)' with type '$($parameter.type)'." }
    }
}

foreach ($runtimeMetadataType in @($artifact.cmdlets | ForEach-Object runtimeMetadataType | Sort-Object -Unique)) {
    $generatedRuntime = @($artifact.cmdlets | Where-Object runtimeMetadataType -eq $runtimeMetadataType | ForEach-Object { $_.generated.runtimeMetadataPath } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First 1)
    if ($generatedRuntime.Count -ne 1) { throw "P3.3 runtime metadata '$runtimeMetadataType' has no source path." }
    $runtimePath = Join-Path $p33ProjectRoot ([string]$generatedRuntime[0])
    if ($ValidateOnly -and (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
        Assert-RuntimeMetadataSourceContract $artifact (Get-Content -Raw -LiteralPath $runtimePath -Encoding UTF8) $runtimeMetadataType
    } elseif ($ValidateOnly) {
        throw "P3.3 runtime metadata '$runtimeMetadataType' is missing: $runtimePath"
    }
}

$renderedNormalized = Normalize-GeneratedSource $rendered
if ($ValidateOnly) {
    $existingNormalized = Normalize-GeneratedSource $sourceForValidation
    $expectedHash = ([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($renderedNormalized)) | ForEach-Object ToString x2) -join ''
    $actualHash = ([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($existingNormalized)) | ForEach-Object ToString x2) -join ''
    if ($expectedHash -ne $actualHash -or $renderedNormalized -cne $existingNormalized) { throw "P3.3 generated source renderer drifted for '$p33SourcePath'. Expected SHA256 '$expectedHash', actual '$actualHash'." }
} else {
    Write-Utf8CrLf $p33SourcePath $rendered
    foreach ($model in @($artifact.models)) {
        if ([string]::IsNullOrWhiteSpace([string]$model.path)) { throw "P3.3 model '$($model.className)' has no generated path." }
        Write-GeneratedModel $model (Join-Path (Join-Path $p33GeneratedRoot 'Models') ([IO.Path]::GetFileName([string]$model.path)))
    }
    foreach ($group in @($artifact.cmdlets | Group-Object runtimeMetadataType | Sort-Object Name)) {
        $generated = @($group.Group | ForEach-Object generated | Where-Object { $null -ne $_ } | Select-Object -First 1)
        if ($generated.Count -ne 1) { throw "P3.3 runtime metadata '$($group.Name)' has no generated path metadata." }
        $combined = [pscustomobject]@{ operations = @($group.Group | ForEach-Object operations) }
        $operationMetadataPath = [string]$generated[0].operationMetadataPath
        if (-not [string]::IsNullOrWhiteSpace($operationMetadataPath)) { Write-OperationMetadata $combined ([string]$generated[0].operationMetadataType) (Join-Path $p33ProjectRoot $operationMetadataPath) }
        $runtimeMetadataPath = [string]$generated[0].runtimeMetadataPath
        if (-not [string]::IsNullOrWhiteSpace($runtimeMetadataPath)) { Write-RuntimeMetadata $combined ([string]$group.Name) (Join-Path $p33ProjectRoot $runtimeMetadataPath) }
    }
}

[pscustomobject]@{
    Stage = 'P3.3'
    Slice = 'd1/database'
    Cmdlets = @($artifact.cmdlets | ForEach-Object cmdletName)
    Operations = @($artifact.cmdlets | ForEach-Object operations | ForEach-Object operationId)
    ProjectionArtifact = [IO.Path]::GetRelativePath($p33ProjectRoot, $p33ArtifactPath).Replace('\', '/')
    GeneratedSource = [IO.Path]::GetRelativePath($p33ProjectRoot, $p33SourcePath).Replace('\', '/')
} | ConvertTo-Json -Depth 10
Write-Output 'PASS P3.3 canonical-artifact source generation and runtime drift checks'
