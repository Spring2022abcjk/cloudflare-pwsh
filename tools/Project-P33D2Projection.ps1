[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$NormalizedPath = (Join-Path $ProjectRoot 'fixtures/p3.3/healthchecks/document.json'),
    [string]$BaseProjectionPath = (Join-Path $ProjectRoot 'overrides/powershell-projection.json'),
    [string]$PolicyPath = (Join-Path $ProjectRoot 'overrides/powershell-p33-d2-healthchecks-projection.json'),
    [string]$FixtureScriptPath = (Join-Path $ProjectRoot 'tools/Generate-P33D2HealthchecksFixture.ps1'),
    [string]$GeneratorPath = (Join-Path $ProjectRoot 'tools/Generate-P33D2Source.ps1'),
    [string]$TemplatePath = (Join-Path $ProjectRoot 'tools/templates/P32RepresentativeCmdlets.cs.tmpl'),
    [string]$ArtifactPath = (Join-Path $ProjectRoot 'artifacts/p3.3/healthchecks/CmdletModel.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$p33ProjectRoot = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
$p33NormalizedPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $NormalizedPath).Path)
$p33BaseProjectionPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $BaseProjectionPath).Path)
$p33PolicyPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $PolicyPath).Path)
$p33FixtureScriptPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $FixtureScriptPath).Path)
$p33GeneratorPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $GeneratorPath).Path)
$p33TemplatePath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $TemplatePath).Path)
$p33ArtifactPath = if ([IO.Path]::IsPathRooted($ArtifactPath)) { [IO.Path]::GetFullPath($ArtifactPath) } else { Join-Path $p33ProjectRoot $ArtifactPath }

$projectionLibrary = Join-Path $PSScriptRoot 'Project-P32Projection.ps1'
$rendererLibrary = Join-Path $PSScriptRoot 'Generate-P32Source.ps1'
$modelParityLibrary = Join-Path $PSScriptRoot 'P33ModelSchemaParity.ps1'
foreach ($input in @($projectionLibrary,$rendererLibrary,$modelParityLibrary)) { if (-not (Test-Path -LiteralPath $input -PathType Leaf)) { throw "Shared P3.3 projection input is missing: $input" } }
. $projectionLibrary -ProjectRoot $p33ProjectRoot -Library
. $modelParityLibrary

function Merge-ProjectionOperations {
    param([Parameter(Mandatory)][object[]]$Documents)
    $result = @{}
    foreach ($document in $Documents) {
        $operations = Get-P32PolicyValue $document 'operations'
        if ($null -eq $operations) { continue }
        foreach ($property in $operations.PSObject.Properties) {
            if (-not $result.ContainsKey($property.Name)) { $result[$property.Name] = [ordered]@{} }
            foreach ($child in $property.Value.PSObject.Properties) { $result[$property.Name][$child.Name] = $child.Value }
        }
    }
    return $result
}

function Assert-P33D2OperationFacts {
    param([Parameter(Mandatory)][object]$Operation)
    $operationId = [string]$Operation.OperationId
    if ($operationId -notin @('health-checks-create-health-check','health-checks-delete-health-check','health-checks-health-check-details','health-checks-list-health-checks','health-checks-patch-health-check','health-checks-update-health-check')) { throw "D2 operation '$operationId' is outside the bounded slice." }
    if ([string]$Operation.Method -notin @('GET','POST','PUT','PATCH','DELETE')) { throw "D2 operation '$operationId' has an unsupported method." }
    if ([string]$Operation.PathTemplate -notin @('/zones/{zone_id}/healthchecks','/zones/{zone_id}/healthchecks/{healthcheck_id}')) { throw "D2 operation '$operationId' escaped the fixed path scope." }
    if (@($Operation.ScopeBindings | Where-Object { [string]$_.ScopeType -eq 'Zone' -and [string]$_.Role -eq 'Parent' }).Count -ne 1) { throw "D2 operation '$operationId' lacks one zone parent scope." }
    $body = if ($null -eq $Operation.PSObject.Properties['RequestBody']) { $null } else { $Operation.RequestBody }
    $bodyIds = @('health-checks-create-health-check','health-checks-patch-health-check','health-checks-update-health-check')
    if ($bodyIds -contains $operationId) {
        if ($null -eq $body -or [string]$body.Presence -ne 'required' -or [string]$body.Representations[0].ContentType -ne 'application/json' -or [string]$body.Representations[0].Schema -ne 'healthchecks_query_healthcheck') { throw "D2 operation '$operationId' body facts are incomplete." }
    } elseif ($operationId -eq 'health-checks-delete-health-check') {
        if ($null -eq $body -or [bool]$body.DeclaredContract -ne $true -or [bool]$body.Required -ne $true -or [string]$body.Presence -ne 'declared-but-observed-absent' -or [string]$body.EffectivePresence -ne 'absent' -or [string]$body.ObservedCorrection -ne 'official-wrappers-send-no-body') { throw 'D2 DELETE must preserve the exact corrected absent-body contract.' }
        $representations = @($body.Representations)
        if (@($representations).Count -ne 1 -or [string]$representations[0].ContentType -cne 'application/json' -or -not [string]::IsNullOrWhiteSpace([string]$representations[0].Schema)) { throw 'D2 DELETE declared request representation drifted.' }
        $trace = @($Operation.CorrectionTrace)
        if (@($trace).Count -ne 1) { throw 'D2 DELETE must have exactly one correction trace entry.' }
        try { $traceMatch = [string]$trace[0].Match | ConvertFrom-Json } catch { throw 'D2 DELETE correction trace is not valid JSON.' }
        if (@($traceMatch.PSObject.Properties.Name).Count -ne 1 -or [string]$traceMatch.operationId -cne $operationId) { throw 'D2 DELETE correction trace must point to the exact operationId.' }
    } elseif ($null -ne $body) { throw "D2 read operation '$operationId' unexpectedly has a body." }
}

function Assert-P33D2ProjectionContract {
    param(
        [Parameter(Mandatory)][object]$Policy,
        [Parameter(Mandatory)][object[]]$FixtureOperations
    )
    $setPolicy = @($Policy.commands | Where-Object { [string]$_.cmdletName -ceq 'Set-CfHealthCheck' })
    if ($setPolicy.Count -ne 1) { throw 'D2 projection contract must declare exactly one Set-CfHealthCheck command.' }
    $operationPolicies = Get-P32PolicyValue $setPolicy[0] 'operations'
    $discriminators = Get-P32PolicyValue $setPolicy[0] 'parameterSetDiscriminators'
    if ($null -eq $operationPolicies -or $null -eq $discriminators) { throw 'D2 projection contract is missing Set operation or discriminator declarations.' }
    $patchSelector = @($discriminators | Where-Object { [string](Get-P32PolicyValue $_ 'name') -ceq 'Patch' })
    if ($patchSelector.Count -ne 1) { throw 'D2 projection contract must declare exactly one Patch discriminator.' }
    $patchOperationId = 'health-checks-patch-health-check'
    $updateOperationId = 'health-checks-update-health-check'
    $patchPolicy = Get-P32PolicyValue $operationPolicies $patchOperationId
    $updatePolicy = Get-P32PolicyValue $operationPolicies $updateOperationId
    if ($null -eq $patchPolicy -or $null -eq $updatePolicy) { throw 'D2 projection contract must declare both exact Edit and Update operations.' }
    if ([string](Get-P32PolicyValue $patchSelector[0] 'parameterSet') -cne 'Edit' -or [string](Get-P32PolicyValue $patchSelector[0] 'type') -cne 'SwitchParameter' -or [string](Get-P32PolicyValue $patchSelector[0] 'operationId') -cne $patchOperationId) { throw 'D2 Patch discriminator must declare the Edit/PATCH operation.' }
    if ([string](Get-P32PolicyValue $patchPolicy 'parameterSet') -cne 'Edit') { throw 'D2 PATCH operation must map to the Edit parameter set.' }
    if ([string](Get-P32PolicyValue $updatePolicy 'parameterSet') -cne 'Update') { throw 'D2 PUT operation must map to the Update parameter set.' }
    $patchOperation = @($FixtureOperations | Where-Object { [string]$_.operationId -ceq $patchOperationId })
    $updateOperation = @($FixtureOperations | Where-Object { [string]$_.operationId -ceq $updateOperationId })
    if ($patchOperation.Count -ne 1 -or [string]$patchOperation[0].method -cne 'PATCH' -or $patchOperation[0].pathTemplate -ne '/zones/{zone_id}/healthchecks/{healthcheck_id}') { throw 'D2 Edit must map to the exact PATCH health-check operation.' }
    if ($updateOperation.Count -ne 1 -or [string]$updateOperation[0].method -cne 'PUT' -or $updateOperation[0].pathTemplate -ne '/zones/{zone_id}/healthchecks/{healthcheck_id}') { throw 'D2 Update must map to the exact PUT health-check operation.' }
}

foreach ($input in @($p33NormalizedPath,$p33BaseProjectionPath,$p33PolicyPath,$p33FixtureScriptPath,$p33GeneratorPath,$p33TemplatePath)) { if (-not (Test-Path -LiteralPath $input -PathType Leaf)) { throw "D2 projection input is missing: $input" } }
$normalized = Get-Content -Raw -LiteralPath $p33NormalizedPath | ConvertFrom-Json
$baseProjection = Get-Content -Raw -LiteralPath $p33BaseProjectionPath | ConvertFrom-Json
$policy = Get-Content -Raw -LiteralPath $p33PolicyPath | ConvertFrom-Json
if ([int]$policy.version -ne 1 -or [string]$policy.stage -ne 'P3.3' -or [string]$policy.slice -ne 'healthchecks') { throw 'D2 projection policy version, stage, or slice is unsupported.' }
$expectedOperationIds = @('health-checks-create-health-check','health-checks-delete-health-check','health-checks-health-check-details','health-checks-list-health-checks','health-checks-patch-health-check','health-checks-update-health-check')
$fixtureOperations = @($normalized.operations)
if ($fixtureOperations.Count -ne 6 -or (@($fixtureOperations | ForEach-Object OperationId | Sort-Object -Unique) -join '|') -ne (@($expectedOperationIds | Sort-Object) -join '|')) { throw 'D2 normalized fixture must contain exactly the six healthchecks operations.' }
foreach ($operation in $fixtureOperations) { Assert-P33D2OperationFacts $operation }
Assert-P33D2ProjectionContract $policy $fixtureOperations

$projectionOperations = Merge-ProjectionOperations @($baseProjection,$policy)
$schemas = @{}
foreach ($property in $normalized.schemas.PSObject.Properties) { $schemas[$property.Name] = $property.Value }
$cmdlets = [System.Collections.Generic.List[object]]::new()
$selected = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($commandPolicy in @($policy.commands)) {
    $commandOperations = [System.Collections.Generic.List[object]]::new()
    $operationPolicies = Get-P32PolicyValue $commandPolicy 'operations'
    if ($null -eq $operationPolicies) { throw "D2 command '$($commandPolicy.cmdletName)' has no operation policy." }
    foreach ($operationProperty in @($operationPolicies.PSObject.Properties | Sort-Object Name)) {
        $operation = @($fixtureOperations | Where-Object OperationId -eq $operationProperty.Name)
        if ($operation.Count -ne 1) { throw "D2 command '$($commandPolicy.cmdletName)' references '$($operationProperty.Name)' zero or multiple times." }
        if (-not $selected.Add([string]$operationProperty.Name)) { throw "D2 operation '$($operationProperty.Name)' is projected more than once." }
        $commandOperations.Add((ConvertTo-OperationProjection $operation[0] $projectionOperations $schemas 'healthchecks' $operationProperty.Value $commandPolicy))
    }
    if ($commandOperations.Count -eq 0) { throw "D2 command '$($commandPolicy.cmdletName)' has no operations." }
    $cmdlets.Add((ConvertTo-CmdletProjection $commandPolicy @($commandOperations) 'healthchecks'))
}
if ($selected.Count -ne 6 -or @($cmdlets).Count -ne 4) { throw "D2 projection must produce six operations and four cmdlets; got $($selected.Count) and $(@($cmdlets).Count)." }

$rawModels = [System.Collections.Generic.List[object]]::new()
foreach ($commandPolicy in @($policy.commands)) { $model = Get-P32PolicyValue $commandPolicy 'model'; if ($null -ne $model) { $rawModels.Add($model) } }
foreach ($model in @($policy.additionalModels)) { $rawModels.Add($model) }
if (@($rawModels | ForEach-Object className | Sort-Object -Unique).Count -ne $rawModels.Count) { throw 'D2 projection contains duplicate generated model classes.' }
$models = [System.Collections.Generic.List[object]]::new()
$normalizedSourcePath = [IO.Path]::GetRelativePath($p33ProjectRoot,$p33NormalizedPath).Replace('\','/')
$objectAllowlist = Get-P32PolicyValue $policy 'objectTypeAllowlist'
foreach ($model in @($rawModels)) { $models.Add((ConvertTo-P33ModelProjection $model $schemas @($rawModels) $normalizedSourcePath $objectAllowlist)) }
if (@($models | Where-Object { @($_.properties).Count -eq 0 }).Count -gt 0) { throw 'D2 projection contains an empty typed model.' }

$sourcePaths = @(
    (Join-Path $p33ProjectRoot 'ref/api-schemas/openapi.json'),
    (Join-Path $p33ProjectRoot 'overrides/api-corrections.json'),
    $p33NormalizedPath,$p33BaseProjectionPath,$p33PolicyPath,$p33FixtureScriptPath,$projectionLibrary,$rendererLibrary,$modelParityLibrary,$p33GeneratorPath,$p33TemplatePath,
    (Join-Path $p33ProjectRoot 'module/Cloudflare.PowerShell/Cloudflare.PowerShell.psd1'),
    (Join-Path $p33ProjectRoot 'module/Cloudflare.PowerShell/Cloudflare.PowerShell.psm1')
)
$sourceFiles = Get-P32SourceFiles $p33ProjectRoot $sourcePaths
$artifact = [ordered]@{
    version = 1
    stage = 'P3.3'
    slice = 'healthchecks'
    sourcePolicy = 'normalized-model-plus-projection-policy'
    semanticAlgorithm = 'SHA256-CanonicalJson-v1'
    sourceFiles = $sourceFiles
    cmdlets = @($cmdlets)
    models = @($models)
    commonInfrastructureParameters = @('BaseUrl','Token','Handler')
}
$artifact.canonicalDigest = Get-P32CanonicalDigest $artifact
function Write-Utf8CrLf { param([string]$Path,[string]$Content); New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null; $n=$Content.Replace("`r`n","`n").Replace("`r","`n").Replace("`n","`r`n"); [IO.File]::WriteAllText($Path,$n,[Text.UTF8Encoding]::new($false)) }
Write-Utf8CrLf $p33ArtifactPath (($artifact | ConvertTo-Json -Depth 100) + "`n")
Write-Output "PASS P3.3 D2 canonical projection: cmdlets=$(@($artifact.cmdlets).Count), operations=$(@($artifact.cmdlets | ForEach-Object operations).Count), models=$(@($artifact.models).Count)"
Write-Output "P3.3 D2 canonical artifact: $p33ArtifactPath"
