[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Assert-True { param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Message); if (-not $Condition) { throw $Message } }
$root=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
$fixture=Get-Content -Raw (Join-Path $root 'fixtures/p3.3/healthchecks/document.json')|ConvertFrom-Json
$artifact=Get-Content -Raw (Join-Path $root 'artifacts/p3.3/healthchecks/CmdletModel.json')|ConvertFrom-Json
$ids=@('health-checks-create-health-check','health-checks-delete-health-check','health-checks-health-check-details','health-checks-list-health-checks','health-checks-patch-health-check','health-checks-update-health-check')
$operations=@($fixture.operations)
Assert-True ($operations.Count -eq 6 -and (@($operations|ForEach-Object operationId|Sort-Object)-join '|') -eq (@($ids|Sort-Object)-join '|')) 'D2 fixture does not contain the six exact operations.'
foreach($op in $operations){
    Assert-True ([string]$op.pathTemplate -in @('/zones/{zone_id}/healthchecks','/zones/{zone_id}/healthchecks/{healthcheck_id}')) "D2 path drifted for $($op.operationId)."
    $path=@($op.parameters|Where-Object location -eq 'path'|ForEach-Object name|Sort-Object)
    $expected=if([string]$op.operationId -in @('health-checks-create-health-check','health-checks-list-health-checks')){@('zone_id')}else{@('healthcheck_id','zone_id')}
    Assert-True (($path-join '|')-eq($expected-join '|')) "D2 path parameters drifted for $($op.operationId)."
    Assert-True (@($op.scopeBindings|Where-Object{$_.scopeType -eq 'Zone' -and $_.role -eq 'Parent'}).Count -eq 1) "D2 zone scope drifted for $($op.operationId)."
    $body=if($null -eq $op.PSObject.Properties['requestBody']){$null}else{$op.requestBody}
    if($op.operationId -in @('health-checks-create-health-check','health-checks-patch-health-check','health-checks-update-health-check')){Assert-True($null-ne$body -and $body.presence -eq 'required' -and $body.representations[0].contentType -eq 'application/json' -and $body.representations[0].schema -eq 'healthchecks_query_healthcheck') "D2 JSON body drifted for $($op.operationId)."}
    elseif($op.operationId -eq 'health-checks-delete-health-check'){Assert-True($body.presence -eq 'declared-but-observed-absent' -and $body.effectivePresence -eq 'absent' -and $body.observedCorrection -eq 'official-wrappers-send-no-body') 'D2 DELETE correction is absent.'}
    else{Assert-True($null-eq$body) "D2 read operation $($op.operationId) unexpectedly has a body."}
    $success=@($op.responses|Where-Object{$_.statusSelector.value -eq '200'}|ForEach-Object representations)[0]; $failure=@($op.responses|Where-Object{$_.statusSelector.value -eq '4XX'}|ForEach-Object representations)[0]
    Assert-True($success.contentType -eq 'application/json' -and $success.envelopePolicy -eq 'CloudflareResult' -and $success.parsingMode -eq 'Json' -and $failure.envelopePolicy -eq 'ErrorEnvelope') "D2 response/envelope facts drifted for $($op.operationId)."
}
$list=@($operations|Where-Object operationId -eq 'health-checks-list-health-checks')[0]
Assert-True($list.pagination.strategy -eq 'V4PagePaginationArray' -and (@($list.pagination.requestFields)-join '|') -eq 'page|per_page') 'D2 list paging facts drifted.'
$delete=@($operations|Where-Object operationId -eq 'health-checks-delete-health-check')[0]
Assert-True($delete.requestBody.declaredContract -eq $true -and $delete.requestBody.required -eq $true -and $delete.requestBody.presence -eq 'declared-but-observed-absent' -and $delete.requestBody.effectivePresence -eq 'absent' -and $delete.requestBody.observedCorrection -eq 'official-wrappers-send-no-body') 'D2 DELETE correction facts are incomplete.'
$deleteTrace=@($delete.correctionTrace); Assert-True($deleteTrace.Count -eq 1 -and ([string]$deleteTrace[0].match|ConvertFrom-Json).operationId -eq 'health-checks-delete-health-check') 'D2 DELETE correction trace does not point to the exact operationId.'
$http=$fixture.schemas.healthchecks_http_config; $headerSchema=$fixture.schemas.($http.properties.header.schema); Assert-True($null-ne$headerSchema -and $headerSchema.additionalPropertiesSchema -and $headerSchema.kind -eq 'object') 'D2 header additional-properties schema was lost.'
Write-Output 'PASS P3.3 D2 normalized method/path/scope/body/response/pagination/type facts'

$artifactIds=@($artifact.cmdlets|ForEach-Object operations|ForEach-Object operationId)
Assert-True($artifactIds.Count -eq 6 -and (@($artifactIds|Sort-Object)-join '|')-eq(@($ids|Sort-Object)-join '|') -and @($artifact.cmdlets).Count -eq 4) 'D2 canonical operation/cmdlet counts drifted.'
$names=@($artifact.cmdlets|ForEach-Object cmdletName); Assert-True(((@('Get-CfHealthCheck','New-CfHealthCheck','Remove-CfHealthCheck','Set-CfHealthCheck')|Sort-Object)-join '|')-eq(($names|Sort-Object)-join '|')) 'D2 public cmdlet names drifted.'
$get=@($artifact.cmdlets|Where-Object cmdletName -eq 'Get-CfHealthCheck')[0]; $set=@($artifact.cmdlets|Where-Object cmdletName -eq 'Set-CfHealthCheck')[0]; $remove=@($artifact.cmdlets|Where-Object cmdletName -eq 'Remove-CfHealthCheck')[0]
Assert-True(@($get.parameterSets|ForEach-Object name)-contains 'Get' -and @($get.parameterSets|ForEach-Object name)-contains 'List') 'D2 Get parameter sets are incomplete.'
Assert-True(@($set.parameterSets|ForEach-Object name)-contains 'Edit' -and @($set.parameterSets|ForEach-Object name)-contains 'Update' -and @($set.parameters|Where-Object name -eq 'Patch'|ForEach-Object type) -eq 'SwitchParameter') 'D2 PATCH/PUT parameter-set discriminator is missing.'
$patchParameter=@($set.parameters|Where-Object name -eq 'Patch')[0]; $patchSet=@($set.parameterSets|Where-Object name -eq 'Edit')[0]; $updateSet=@($set.parameterSets|Where-Object name -eq 'Update')[0]; $patchOperation=@($set.operations|Where-Object operationId -eq 'health-checks-patch-health-check')[0]; $updateOperation=@($set.operations|Where-Object operationId -eq 'health-checks-update-health-check')[0]
Assert-True($patchParameter.binding -eq 'parameter-set-selector' -and @($patchParameter.appliesTo).Count -eq 1 -and [string]$patchParameter.appliesTo[0] -eq 'Edit' -and [string]$patchParameter.operationId -eq 'health-checks-patch-health-check' -and @($patchParameter.apiBindings).Count -eq 0 -and $null -eq $patchParameter.sourceName -and @($set.operations|ForEach-Object runtime|ForEach-Object parameters|Where-Object name -eq 'patch').Count -eq 0) 'D2 discriminator entered API/runtime metadata or lost its Edit contract.'
Assert-True($null -ne $patchSet -and $patchSet.operationId -eq 'health-checks-patch-health-check' -and $patchSet.operationBinding.method -eq 'PATCH' -and $null -ne $updateSet -and $updateSet.operationId -eq 'health-checks-update-health-check' -and $updateSet.operationBinding.method -eq 'PUT' -and $patchOperation.parameterSet -eq 'Edit' -and $updateOperation.parameterSet -eq 'Update') 'D2 Edit/PATCH or Update/PUT parameter-set mapping drifted.'
Assert-True($remove.outputPolicy -eq 'none' -and @($artifact.cmdlets|ForEach-Object parameters|Where-Object type -in @('object','System.Object')).Count -eq 0) 'D2 no-output or typed-parameter contract drifted.'
Assert-True(@($artifact.models|Where-Object{$_.className -in @('CfHealthCheck','CfHealthCheckRequest','CfHealthCheckHttpConfig','CfHealthCheckTcpConfig')}).Count -eq 4) 'D2 typed model set is incomplete.'
Assert-True(@($artifact.models|ForEach-Object properties|Where-Object type -match 'Dictionary<string, string\[\]>').Count -eq 1) 'D2 dictionary type was not preserved.'
Write-Output 'PASS P3.3 D2 canonical public projection, parameter sets, no-output, and typed models'

$compat=Get-Content -Raw (Join-Path $root 'artifacts/p3.3/healthchecks/d2-projection-compatibility.json')|ConvertFrom-Json
Assert-True($compat.stage -eq 'P3.3-projection' -and @($compat.changes|Where-Object kind -eq 'CmdletAdded').Count -eq 4) 'D2 compatibility report does not show four public cmdlet additions.'
Write-Output 'PASS P3.3 D2 compatibility visibility'
$source=Get-Content -Raw (Join-Path $root 'src/Cloudflare.PowerShell/Generated/Cmdlets/P33D2HealthchecksCmdlets.cs'); Assert-True($source -notmatch 'HttpClient|HttpRequestMessage|CloudflareRuntimeDispatcher|/zones/') 'D2 generated source contains transport or endpoint-specific code.'; Assert-True($source -match 'BindParametersWithBody' -and $source -match 'WritePaged<Cloudflare.PowerShell.CfHealthCheck>' -and $source -match 'InvokeSingle<Cloudflare.PowerShell.CfHealthCheck>') 'D2 generated source does not use shared runtime capability calls.'
$generator=Get-Content -Raw (Join-Path $root 'tools/Generate-P33D2Source.ps1'); Assert-True($generator -notmatch 'health-checks-(create|delete|health-check-details|list|patch|update)-health-check|CfHealthCheck') 'D2 generator contains a healthcheck-specific renderer branch.'
Write-Output 'PASS P3.3 D2 generated-source and renderer capability boundary'

function Assert-Fails { param([string[]]$Args,[string]$Message); & pwsh -NoLogo -NoProfile -File @Args 2>&1|Out-Null; if($LASTEXITCODE -eq 0){throw $Message} }
$negative=Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p33-d2-negative-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Force -Path $negative|Out-Null
    $policyPath=Join-Path $root 'overrides/powershell-p33-d2-healthchecks-projection.json'; $projector=Join-Path $root 'tools/Project-P33D2Projection.ps1'; $fixtureGenerator=Join-Path $root 'tools/Generate-P33D2HealthchecksFixture.ps1'
    function Invoke-PolicyFailure {
        param([Parameter(Mandatory)][string]$Label,[Parameter(Mandatory)][scriptblock]$Mutation)
        $p=Get-Content -Raw $policyPath|ConvertFrom-Json; $setPolicy=@($p.commands|Where-Object cmdletName -eq 'Set-CfHealthCheck')[0]; & $Mutation $setPolicy
        $mp=Join-Path $negative "$Label-policy.json"; $ma=Join-Path $negative "$Label-artifact.json"; [IO.File]::WriteAllText($mp,($p|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false)); Assert-Fails @('-File',$projector,'-ProjectRoot',$root,'-PolicyPath',$mp,'-ArtifactPath',$ma) "D2 projector accepted discriminator mutation '$Label'."
    }
    Invoke-PolicyFailure 'missing-discriminator' { param($p) $p.parameterSetDiscriminators=@() }
    Invoke-PolicyFailure 'unknown-discriminator-set' { param($p) @($p.parameterSetDiscriminators)[0].parameterSet='Missing' }
    Invoke-PolicyFailure 'duplicate-discriminator' { param($p) $s=@($p.parameterSetDiscriminators)[0]; $p.parameterSetDiscriminators=@($s,$s) }
    Invoke-PolicyFailure 'discriminator-api-name-collision' { param($p) @($p.parameterSetDiscriminators)[0].name='HealthCheckId' }
    Invoke-PolicyFailure 'discriminator-api-binding' { param($p) @($p.parameterSetDiscriminators)[0]|Add-Member -NotePropertyName apiBindings -NotePropertyValue @([pscustomobject]@{operationId='unexpected';location='query';name='patch'}) -Force }
    Invoke-PolicyFailure 'discriminator-wrong-type' { param($p) @($p.parameterSetDiscriminators)[0].type='string' }
    Invoke-PolicyFailure 'discriminator-legal-update-escape' { param($p) @($p.parameterSetDiscriminators)[0].parameterSet='Update' }
    Invoke-PolicyFailure 'discriminator-legal-unrelated-set-escape' { param($p) @($p.parameterSetDiscriminators)[0].parameterSet='Create' }
    Invoke-PolicyFailure 'edit-operation-id-drift' { param($p) $set=$p; $old=$set.operations.PSObject.Properties['health-checks-patch-health-check'].Value; $set.operations.PSObject.Properties.Remove('health-checks-patch-health-check'); $set.operations | Add-Member -NotePropertyName 'health-checks-update-health-check' -NotePropertyValue $old -Force }
    Invoke-PolicyFailure 'update-operation-id-drift' { param($p) $set=$p; $old=$set.operations.PSObject.Properties['health-checks-update-health-check'].Value; $set.operations.PSObject.Properties.Remove('health-checks-update-health-check'); $set.operations | Add-Member -NotePropertyName 'health-checks-patch-health-check' -NotePropertyValue $old -Force }

    function Invoke-ModelPolicyFailure {
        param([Parameter(Mandatory)][string]$Label,[Parameter(Mandatory)][scriptblock]$Mutation)
        $p=Get-Content -Raw $policyPath|ConvertFrom-Json; & $Mutation $p
        $mp=Join-Path $negative "$Label-policy.json"; $ma=Join-Path $negative "$Label-artifact.json"; [IO.File]::WriteAllText($mp,($p|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false)); Assert-Fails @('-File',$projector,'-ProjectRoot',$root,'-PolicyPath',$mp,'-ArtifactPath',$ma) "D2 projector accepted typed-model mutation '$Label'."
    }
    Invoke-ModelPolicyFailure 'dictionary-string-array-to-int-array' { param($p) $m=@($p.commands|Where-Object {$null -ne $_.PSObject.Properties['model']}|ForEach-Object {$_.model}|Where-Object className -eq 'CfHealthCheckHttpConfig')[0]; @($m.properties|Where-Object name -eq 'Header')[0].type='Dictionary<string, int[]>?' }
    Invoke-ModelPolicyFailure 'dictionary-string-array-to-string' { param($p) $m=@($p.commands|Where-Object {$null -ne $_.PSObject.Properties['model']}|ForEach-Object {$_.model}|Where-Object className -eq 'CfHealthCheckHttpConfig')[0]; @($m.properties|Where-Object name -eq 'Header')[0].type='Dictionary<string, string>?' }
    Invoke-ModelPolicyFailure 'array-to-string' { param($p) $m=@($p.commands|Where-Object {$null -ne $_.PSObject.Properties['model']}|ForEach-Object {$_.model}|Where-Object className -eq 'CfHealthCheckRequest')[0]; @($m.properties|Where-Object name -eq 'CheckRegions')[0].type='string?' }
    Invoke-ModelPolicyFailure 'array-to-int-array' { param($p) $m=@($p.commands|Where-Object {$null -ne $_.PSObject.Properties['model']}|ForEach-Object {$_.model}|Where-Object className -eq 'CfHealthCheckRequest')[0]; @($m.properties|Where-Object name -eq 'CheckRegions')[0].type='int[]?' }
    Invoke-ModelPolicyFailure 'nullable-drift' { param($p) $m=@($p.commands|Where-Object {$null -ne $_.PSObject.Properties['model']}|ForEach-Object {$_.model}|Where-Object className -eq 'CfHealthCheckRequest')[0]; @($m.properties|Where-Object name -eq 'Address')[0].nullable=$true }
    Invoke-ModelPolicyFailure 'presence-drift' { param($p) $m=@($p.commands|Where-Object {$null -ne $_.PSObject.Properties['model']}|ForEach-Object {$_.model}|Where-Object className -eq 'CfHealthCheckRequest')[0]; @($m.properties|Where-Object name -eq 'Address')[0].presence='optional' }
    Invoke-ModelPolicyFailure 'nested-model-binding-drift' { param($p) $m=@($p.commands|Where-Object {$null -ne $_.PSObject.Properties['model']}|ForEach-Object {$_.model}|Where-Object className -eq 'CfHealthCheckRequest')[0]; @($m.properties|Where-Object name -eq 'HttpConfig')[0].nestedModel='CfHealthCheckTcpConfig' }
    Invoke-ModelPolicyFailure 'json-name-drift' { param($p) $m=@($p.commands|Where-Object {$null -ne $_.PSObject.Properties['model']}|ForEach-Object {$_.model}|Where-Object className -eq 'CfHealthCheckRequest')[0]; @($m.properties|Where-Object name -eq 'Name')[0].jsonName='name_typo' }
    Invoke-ModelPolicyFailure 'object-fallback' { param($p) $m=@($p.commands|Where-Object {$null -ne $_.PSObject.Properties['model']}|ForEach-Object {$_.model}|Where-Object className -eq 'CfHealthCheckRequest')[0]; @($m.properties|Where-Object name -eq 'Address')[0].type='object' }

    function Invoke-NormalizedFailure {
        param([Parameter(Mandatory)][string]$Label,[Parameter(Mandatory)][scriptblock]$Mutation)
        $d=Get-Content -Raw (Join-Path $root 'fixtures/p3.3/healthchecks/document.json')|ConvertFrom-Json; & $Mutation $d
        $np=Join-Path $negative "$Label-fixture.json"; $na=Join-Path $negative "$Label-artifact.json"; [IO.File]::WriteAllText($np,($d|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false)); Assert-Fails @('-File',$projector,'-ProjectRoot',$root,'-NormalizedPath',$np,'-ArtifactPath',$na) "D2 projector accepted normalized mutation '$Label'."
    }
    Invoke-NormalizedFailure 'additional-properties-value-schema-drift' { param($d) $header=[string]$d.schemas.healthchecks_http_config.properties.header.schema; $d.schemas.($header).additionalPropertiesSchema='healthchecks_address' }
    Invoke-NormalizedFailure 'required-property-drift' { param($d) $d.schemas.healthchecks_query_healthcheck.properties.address.required=$false }

    function Invoke-CorrectionFailure {
        param([Parameter(Mandatory)][string]$Label,[Parameter(Mandatory)][scriptblock]$Mutation)
        $c=Get-Content -Raw (Join-Path $root 'overrides/api-corrections.json')|ConvertFrom-Json; $rule=@($c.rules|Where-Object {$_.match.operationId -eq 'health-checks-delete-health-check'})[0]; & $Mutation $rule
        $cp=Join-Path $negative "$Label-corrections.json"; $fp=Join-Path $negative "$Label-fixture.json"; [IO.File]::WriteAllText($cp,($c|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false)); Assert-Fails @('-File',$fixtureGenerator,'-ProjectRoot',$root,'-SchemaPath',(Join-Path $root 'ref/api-schemas/openapi.json'),'-CorrectionPath',$cp,'-OutputPath',$fp,'-SkipBuild') "D2 fixture generator accepted correction mutation '$Label'."
    }
    Invoke-CorrectionFailure 'delete-effective-presence-present' { param($r) $r.actions.requestBody.effectivePresence='present' }
    Invoke-CorrectionFailure 'delete-observed-correction-drift' { param($r) $r.actions.requestBody.observedCorrection='wrong-token' }
    Invoke-CorrectionFailure 'delete-correction-operation-id-drift' { param($r) $r.match.operationId='other-delete-operation' }
    Invoke-CorrectionFailure 'delete-correction-broad-method-path-match' { param($r) $r.match=[pscustomobject]@{method='DELETE';path='/zones/{zone_id}/healthchecks/{healthcheck_id}'} }

    Invoke-NormalizedFailure 'delete-json-body-injected' { param($d) $o=@($d.operations|Where-Object operationId -eq 'health-checks-delete-health-check')[0]; $o.requestBody.effectivePresence='present'; $o.requestBody.presence='required'; $o.requestBody.representations[0].schema='healthchecks_query_healthcheck' }
    Invoke-NormalizedFailure 'delete-content-type-drift' { param($d) $o=@($d.operations|Where-Object operationId -eq 'health-checks-delete-health-check')[0]; $o.requestBody.representations[0].contentType='application/xml' }

    $a=Get-Content -Raw (Join-Path $root 'artifacts/p3.3/healthchecks/CmdletModel.json')|ConvertFrom-Json; $setArtifact=@($a.cmdlets|Where-Object cmdletName -eq 'Set-CfHealthCheck')[0]; $selector=@($setArtifact.parameters|Where-Object {$null -ne $_.PSObject.Properties['isSelector'] -and [bool]$_.isSelector})[0]; $selector.apiBindings=@([pscustomobject]@{operationId='unexpected';location='query';name='patch'}); $ma=Join-Path $negative 'generator-discriminator-binding.json'; [IO.File]::WriteAllText($ma,($a|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false)); Assert-Fails @('-File',(Join-Path $root 'tools/Generate-P33D2Source.ps1'),'-ProjectRoot',$root,'-ArtifactPath',$ma,'-ValidateOnly') 'D2 generator accepted discriminator API-binding drift.'

    foreach($mutation in @('object','wrong-type','wrong-json-name')){
        $p=Get-Content -Raw $policyPath|ConvertFrom-Json; $property=@($p.commands[0].model.properties)[0]; if($mutation -eq 'object'){$property.type='object'}elseif($mutation -eq 'wrong-type'){$property.type='int'}else{$property.jsonName='address_typo'}
        $mp=Join-Path $negative "$mutation-policy.json"; $ma=Join-Path $negative "$mutation-artifact.json"; [IO.File]::WriteAllText($mp,($p|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false)); Assert-Fails @('-File',$projector,'-ProjectRoot',$root,'-PolicyPath',$mp,'-ArtifactPath',$ma) "D2 projector accepted mutation '$mutation'."
    }
    $a=Get-Content -Raw (Join-Path $root 'artifacts/p3.3/healthchecks/CmdletModel.json')|ConvertFrom-Json; $a.models[0].properties[0].type='object'; $ma=Join-Path $negative 'generator-artifact.json'; [IO.File]::WriteAllText($ma,($a|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false)); Assert-Fails @('-File',(Join-Path $root 'tools/Generate-P33D2Source.ps1'),'-ProjectRoot',$root,'-ArtifactPath',$ma,'-ValidateOnly') 'D2 generator accepted object model mutation.'
    $generated=Join-Path $negative 'Generated'; $modelPath=Join-Path $generated 'Models/CfHealthCheck.cs'; New-Item -ItemType Directory -Force -Path (Split-Path -Parent $modelPath)|Out-Null; Copy-Item (Join-Path $root 'src/Cloudflare.PowerShell/Generated/Models/CfHealthCheck.cs') $modelPath -Force; $text=Get-Content -Raw $modelPath -Encoding UTF8; $mutated=$text.Replace('public string? Name { get; set; }','public object? Name { get; set; }'); Assert-True($mutated -cne $text) 'D2 generated-model negative mutation did not apply.'; [IO.File]::WriteAllText($modelPath,$mutated,[Text.UTF8Encoding]::new($false)); Assert-Fails @('-File',(Join-Path $root 'tools/Generate-P33D2Source.ps1'),'-ProjectRoot',$root,'-GeneratedRoot',$generated,'-ValidateOnly') 'D2 generator accepted generated model source drift.'
    Write-Output 'PASS P3.3 D2 negative schema parity, artifact type, and generated-model freshness mutations'
}finally{if(Test-Path -LiteralPath $negative){Remove-Item -LiteralPath $negative -Recurse -Force}}
