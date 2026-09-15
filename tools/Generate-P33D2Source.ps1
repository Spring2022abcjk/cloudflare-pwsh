[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ArtifactPath = (Join-Path $ProjectRoot 'artifacts/p3.3/healthchecks/CmdletModel.json'),
    [string]$NormalizedPath = (Join-Path $ProjectRoot 'fixtures/p3.3/healthchecks/document.json'),
    [string]$TemplatePath = (Join-Path $ProjectRoot 'tools/templates/P32RepresentativeCmdlets.cs.tmpl'),
    [string]$SourcePath = (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Cmdlets/P33D2HealthchecksCmdlets.cs'),
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

. (Join-Path $PSScriptRoot 'Generate-P32Source.ps1') -ProjectRoot $p33ProjectRoot -Library
. (Join-Path $PSScriptRoot 'P33ModelSchemaParity.ps1')

function Assert-P33D2ArtifactFresh {
    param([Parameter(Mandatory)][object]$Artifact)
    if ([int]$Artifact.version -ne 1 -or [string]$Artifact.stage -ne 'P3.3' -or [string]$Artifact.slice -ne 'healthchecks' -or [string]$Artifact.sourcePolicy -ne 'normalized-model-plus-projection-policy' -or [string]$Artifact.semanticAlgorithm -ne 'SHA256-CanonicalJson-v1') { throw 'D2 canonical artifact is not a supported normalized/projection output.' }
    foreach ($source in @($Artifact.sourceFiles)) {
        $path = Join-Path $p33ProjectRoot ([string]$source.path)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "D2 canonical artifact source is missing: $path" }
        $actual = Get-P32PortableFileHash -Path $path
        if ($actual -ne [string]$source.sha256) { throw "D2 canonical artifact is stale for '$($source.path)'. Run Project-P33D2Projection.ps1 first." }
    }
    $digest = Get-P32CanonicalDigest $Artifact
    if ([string]$Artifact.canonicalDigest -ne $digest) { throw "D2 canonical artifact semantic digest is invalid." }
}

function Assert-P33D2ModelParity {
    param([Parameter(Mandatory)][object]$Artifact, [Parameter(Mandatory)][object]$Normalized)
    $schemas = @{}
    foreach ($property in $Normalized.schemas.PSObject.Properties) { $schemas[$property.Name] = $property.Value }
    $models = @($Artifact.models)
    if ($models.Count -ne 4) { throw "D2 canonical artifact must contain four typed models, found $($models.Count)." }
    foreach ($model in $models) { [void](ConvertTo-P33ModelProjection $model $schemas $models ([IO.Path]::GetRelativePath($p33ProjectRoot,$p33NormalizedPath).Replace('\','/')) $null) }
}

function Assert-P33D2GeneratedModelsFresh {
    param([Parameter(Mandatory)][object]$Artifact)
    $stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p33-d2-model-validation-' + [guid]::NewGuid().ToString('N'))
    try {
        foreach ($model in @($Artifact.models)) {
            $existingPath = Join-Path (Join-Path $p33GeneratedRoot 'Models') ([IO.Path]::GetFileName([string]$model.path))
            if (-not (Test-Path -LiteralPath $existingPath -PathType Leaf)) { throw "D2 generated model is missing: $existingPath" }
            $expectedPath = Join-Path $stagingRoot ([string]$model.path)
            Write-GeneratedModel $model $expectedPath
            $expected = Normalize-GeneratedSource (Get-Content -Raw -LiteralPath $expectedPath -Encoding UTF8)
            $actual = Normalize-GeneratedSource (Get-Content -Raw -LiteralPath $existingPath -Encoding UTF8)
            if ($expected -cne $actual) { throw "D2 generated model drifted for '$existingPath'." }
        }
    } finally { if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue } }
}

if (-not (Test-Path -LiteralPath $p33ArtifactPath -PathType Leaf)) { throw "D2 canonical artifact is missing: $p33ArtifactPath" }
if (-not (Test-Path -LiteralPath $p33NormalizedPath -PathType Leaf)) { throw "D2 normalized fixture is missing: $p33NormalizedPath" }
if (-not (Test-Path -LiteralPath $p33TemplatePath -PathType Leaf)) { throw "D2 source template is missing: $p33TemplatePath" }
$artifact = Get-Content -Raw -LiteralPath $p33ArtifactPath | ConvertFrom-Json
$normalized = Get-Content -Raw -LiteralPath $p33NormalizedPath | ConvertFrom-Json
Assert-P33D2ArtifactFresh $artifact
Assert-P33D2ModelParity $artifact $normalized
if ($ValidateOnly) { Assert-P33D2GeneratedModelsFresh $artifact }
Assert-ArtifactContract $artifact
if (@($artifact.cmdlets | Where-Object { @($_.operations).Count -eq 0 }).Count -gt 0) { throw 'D2 artifact contains a cmdlet without operations.' }

$template = Get-Content -Raw -LiteralPath $p33TemplatePath -Encoding UTF8
if ($template -notmatch '\{\{P32_CMDLETS\}\}') { throw 'D2 source template is missing the shared renderer token.' }
$lines = [System.Collections.Generic.List[string]]::new()
foreach ($cmdlet in @($artifact.cmdlets)) { Add-GeneratedCmdlet -Lines ([ref]$lines) -Cmdlet $cmdlet }
$rendered = $template.Replace('{{P32_CMDLETS}}', (($lines -join "`n").TrimEnd([char[]]"`r`n")))
if ($rendered -match '\{\{[^}]+\}\}') { throw 'D2 generated source contains unresolved template tokens.' }
$sourceExists = Test-Path -LiteralPath $p33SourcePath -PathType Leaf
if ($ValidateOnly -and -not $sourceExists) { throw "D2 ValidateOnly source is missing: $p33SourcePath" }
$sourceForValidation = if ($ValidateOnly -and $sourceExists) { Get-Content -Raw -LiteralPath $p33SourcePath -Encoding UTF8 } else { $rendered }
foreach ($cmdlet in @($artifact.cmdlets)) {
    if ($sourceForValidation -notmatch "public sealed class $([regex]::Escape([string]$cmdlet.className))\s*:") { throw "D2 generated source is missing '$($cmdlet.className)'." }
    foreach ($parameter in @($cmdlet.parameters)) {
        if ($sourceForValidation -notmatch "public $([regex]::Escape([string]$parameter.type)) $([regex]::Escape([string]$parameter.name))\s*\{") { throw "D2 generated source does not consume '$($parameter.name)' as '$($parameter.type)'." }
    }
}
foreach ($runtimeMetadataType in @($artifact.cmdlets | ForEach-Object runtimeMetadataType | Sort-Object -Unique)) {
    $runtime = @($artifact.cmdlets | Where-Object runtimeMetadataType -eq $runtimeMetadataType | ForEach-Object { $_.generated.runtimeMetadataPath } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First 1)
    if ($runtime.Count -ne 1) { throw "D2 runtime metadata '$runtimeMetadataType' has no generated path." }
    $runtimePath = Join-Path $p33ProjectRoot ([string]$runtime[0])
    if ($ValidateOnly) { if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) { throw "D2 runtime metadata is missing: $runtimePath" }; Assert-RuntimeMetadataSourceContract $artifact (Get-Content -Raw -LiteralPath $runtimePath -Encoding UTF8) $runtimeMetadataType }
}
$renderedNormalized = Normalize-GeneratedSource $rendered
if ($ValidateOnly) {
    $existingNormalized = Normalize-GeneratedSource $sourceForValidation
    if ($renderedNormalized -cne $existingNormalized) { throw "D2 generated source renderer drifted for '$p33SourcePath'." }
} else {
    Write-Utf8CrLf $p33SourcePath $rendered
    foreach ($model in @($artifact.models)) { Write-GeneratedModel $model (Join-Path (Join-Path $p33GeneratedRoot 'Models') ([IO.Path]::GetFileName([string]$model.path))) }
    foreach ($group in @($artifact.cmdlets | Group-Object runtimeMetadataType | Sort-Object Name)) {
        $generated = @($group.Group | ForEach-Object generated | Where-Object { $null -ne $_ } | Select-Object -First 1)
        if ($generated.Count -ne 1) { throw "D2 runtime metadata '$($group.Name)' has no generated metadata paths." }
        $combined = [pscustomobject]@{ operations = @($group.Group | ForEach-Object operations) }
        if (-not [string]::IsNullOrWhiteSpace([string]$generated[0].operationMetadataPath)) { Write-OperationMetadata $combined ([string]$generated[0].operationMetadataType) (Join-Path $p33ProjectRoot ([string]$generated[0].operationMetadataPath)) }
        if (-not [string]::IsNullOrWhiteSpace([string]$generated[0].runtimeMetadataPath)) { Write-RuntimeMetadata $combined ([string]$group.Name) (Join-Path $p33ProjectRoot ([string]$generated[0].runtimeMetadataPath)) }
    }
}

[pscustomobject]@{
    Stage = 'P3.3'
    Slice = 'healthchecks'
    Cmdlets = @($artifact.cmdlets | ForEach-Object cmdletName)
    Operations = @($artifact.cmdlets | ForEach-Object operations | ForEach-Object operationId)
    ProjectionArtifact = [IO.Path]::GetRelativePath($p33ProjectRoot,$p33ArtifactPath).Replace('\','/')
    GeneratedSource = [IO.Path]::GetRelativePath($p33ProjectRoot,$p33SourcePath).Replace('\','/')
} | ConvertTo-Json -Depth 10
Write-Output 'PASS P3.3 D2 canonical-artifact source generation and typed model/runtime drift checks'
