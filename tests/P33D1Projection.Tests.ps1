[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

$fixture = Get-Content -Raw (Join-Path $ProjectRoot 'fixtures/p3.3/d1-database/document.json') | ConvertFrom-Json
$artifact = Get-Content -Raw (Join-Path $ProjectRoot 'artifacts/p3.3/CmdletModel.json') | ConvertFrom-Json
$expectedIds = @('d1-create-database','d1-delete-database','d1-get-database','d1-list-databases','d1-update-database','d1-update-partial-database')
$operations = @($fixture.operations)
Assert-True ($operations.Count -eq 6) 'D1 normalized fixture does not contain six operations.'
Assert-True ((@($operations | ForEach-Object operationId | Sort-Object) -join '|') -eq (@($expectedIds | Sort-Object) -join '|')) 'D1 normalized fixture operation ids drifted.'
Assert-True (@($operations | Where-Object { @($_.scopeBindings | Where-Object { $_.scopeType -eq 'Account' -and $_.role -eq 'Parent' }).Count -ne 1 }).Count -eq 0) 'D1 account parent scope is not preserved for every operation.'
Assert-True (@($operations | Where-Object { $_.operationId -in @('d1-get-database','d1-delete-database','d1-update-database','d1-update-partial-database') -and @($_.scopeBindings | Where-Object { $_.scopeType -eq 'Database' -and $_.role -eq 'Primary' }).Count -ne 1 }).Count -eq 0) 'D1 database primary scope is not preserved for item operations.'
$list = @($operations | Where-Object operationId -eq 'd1-list-databases')[0]
Assert-True ([string]$list.pagination.strategy -eq 'V4PagePaginationArray' -and (@($list.pagination.requestFields) -join '|') -eq 'page|per_page') 'D1 list pagination facts drifted.'
Assert-True ([string]$fixture.schemas.Inline_11EDC94E7705.items -eq 'd1_database-response') 'D1 list array item schema is not traceable.'

$bodyIds = @('d1-create-database','d1-update-database','d1-update-partial-database')
foreach ($operation in $operations) {
    $body = if ($null -eq $operation.PSObject.Properties['requestBody']) { $null } else { $operation.requestBody }
    $hasBody = $null -ne $body
    Assert-True (($bodyIds -contains [string]$operation.operationId) -eq $hasBody) "D1 operation '$($operation.operationId)' body presence drifted."
    if ($hasBody) { Assert-True ([string]$body.presence -eq 'required' -and [string]$body.representations[0].contentType -eq 'application/json') "D1 operation '$($operation.operationId)' JSON body contract drifted." }
    $success = @($operation.responses | Where-Object { $_.statusSelector.value -eq '200' } | ForEach-Object representations)[0]
    $failure = @($operation.responses | Where-Object { $_.statusSelector.value -eq '4XX' } | ForEach-Object representations)[0]
    Assert-True ([string]$success.contentType -eq 'application/json' -and [string]$success.envelopePolicy -eq 'CloudflareResult' -and [string]$success.parsingMode -eq 'Json') "D1 operation '$($operation.operationId)' success response contract drifted."
    Assert-True ([string]$failure.envelopePolicy -eq 'ErrorEnvelope' -and [string]$failure.parsingMode -eq 'Json') "D1 operation '$($operation.operationId)' error response contract drifted."
}
Write-Output 'PASS P3.3 D1 normalized facts, body, response, scope, and pagination contract'

$artifactOperationIds = @($artifact.cmdlets | ForEach-Object operations | ForEach-Object operationId)
Assert-True ($artifactOperationIds.Count -eq 6 -and (@($artifactOperationIds | Sort-Object) -join '|') -eq (@($expectedIds | Sort-Object) -join '|')) 'D1 canonical artifact operation admission drifted.'
Assert-True (@($artifact.cmdlets).Count -eq 4) 'D1 canonical artifact cmdlet count drifted.'
$set = @($artifact.cmdlets | Where-Object cmdletName -eq 'Set-CfD1Database')[0]
Assert-True (@($set.parameterSets | ForEach-Object name) -contains 'Update' -and @($set.parameterSets | ForEach-Object name) -contains 'PartialUpdate') 'D1 PUT/PATCH parameter sets are ambiguous.'
Assert-True ([string](@($set.operations | Where-Object operationId -eq 'd1-update-partial-database')[0].method) -eq 'PATCH') 'D1 partial update method drifted in canonical artifact.'
Assert-True (@($artifact.cmdlets | ForEach-Object parameters | Where-Object { $_.type -in @('object','System.Object') }).Count -eq 0) 'D1 projection degraded an input type to object.'
foreach ($model in @($artifact.models)) { Assert-True (@($model.properties).Count -gt 0) "D1 generated model '$($model.className)' is empty." }
Write-Output 'PASS P3.3 D1 canonical artifact projection contract'

$compatibility = Get-Content -Raw (Join-Path $ProjectRoot 'artifacts/p3.3/d1-projection-compatibility.json') | ConvertFrom-Json
Assert-True ([string]$compatibility.stage -eq 'P3.3-projection' -and [int]$compatibility.severitySummary.Changes -gt 0) 'D1 projection compatibility report is missing or empty.'
Assert-True (@($compatibility.changes | Where-Object { $_.kind -eq 'PowerShellParameterSetChanged' -and $_.newValue -match 'PartialUpdate' }).Count -gt 0) 'D1 projection compatibility did not expose the PartialUpdate public change.'
Write-Output 'PASS P3.3 D1 projection compatibility visibility'

$generatedSource = Get-Content -Raw (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Cmdlets/P33D1DatabaseCmdlets.cs')
Assert-True ($generatedSource -notmatch 'HttpClient|HttpRequestMessage|CloudflareRuntimeDispatcher|/accounts/') 'D1 generated source contains transport or endpoint-specific code.'
Assert-True ($generatedSource -match 'BindParametersWithBody' -and $generatedSource -match 'WritePaged<Cloudflare.PowerShell.CfD1Database>' -and $generatedSource -match 'InvokeSingle<Cloudflare.PowerShell.CfD1Database>') 'D1 generated source does not use shared runtime capability calls.'
$generatorSource = Get-Content -Raw (Join-Path $ProjectRoot 'tools/Generate-P33D1Source.ps1')
Assert-True ($generatorSource -notmatch 'd1-(create|delete|get|list|update)-database|CfD1Database') 'P3.3 generator contains fixed operation-id or resource-specific renderer branches.'
Write-Output 'PASS P3.3 generated-source capability boundary and independent static review'

function Assert-CommandFails {
    param([Parameter(Mandatory)][string[]]$Arguments, [Parameter(Mandatory)][string]$Message)
    & pwsh -NoLogo -NoProfile -File @Arguments 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { throw $Message }
}

$negativeRoot = Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p33-model-negative-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path $negativeRoot | Out-Null
    $projectorPath = Join-Path $ProjectRoot 'tools/Project-P33D1Projection.ps1'
    $policyPath = Join-Path $ProjectRoot 'overrides/powershell-p33-d1-projection.json'
    foreach ($mutation in @('object', 'wrong-type', 'wrong-json-name')) {
        $policy = Get-Content -Raw -LiteralPath $policyPath | ConvertFrom-Json
        $property = @($policy.commands[0].model.properties)[0]
        switch ($mutation) {
            'object' { $property.type = 'object' }
            'wrong-type' { $property.type = 'int' }
            'wrong-json-name' { $property.jsonName = 'created_at_typo' }
        }
        $mutatedPolicyPath = Join-Path $negativeRoot "$mutation-policy.json"
        $mutatedArtifactPath = Join-Path $negativeRoot "$mutation-artifact.json"
        [IO.File]::WriteAllText($mutatedPolicyPath, ($policy | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        Assert-CommandFails @('-File', $projectorPath, '-ProjectRoot', $ProjectRoot, '-PolicyPath', $mutatedPolicyPath, '-ArtifactPath', $mutatedArtifactPath) "P3.3 projector accepted model parity mutation '$mutation'."
    }

    $artifact = Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'artifacts/p3.3/CmdletModel.json') | ConvertFrom-Json
    $artifact.models[0].properties[0].type = 'object'
    $mutatedArtifact = Join-Path $negativeRoot 'generator-artifact.json'
    [IO.File]::WriteAllText($mutatedArtifact, ($artifact | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
    Assert-CommandFails @('-File', (Join-Path $ProjectRoot 'tools/Generate-P33D1Source.ps1'), '-ProjectRoot', $ProjectRoot, '-ArtifactPath', $mutatedArtifact, '-ValidateOnly') 'P3.3 generator accepted an artifact model object fallback.'

    $modelGeneratedRoot = Join-Path $negativeRoot 'Generated'
    $modelPath = Join-Path $modelGeneratedRoot 'Models/CfD1Database.cs'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $modelPath) | Out-Null
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Models/CfD1Database.cs') -Destination $modelPath -Force
    $modelText = Get-Content -Raw -LiteralPath $modelPath -Encoding UTF8
    $mutatedModelText = $modelText.Replace('public string? Name { get; set; }', 'public object? Name { get; set; }')
    if ($mutatedModelText -ceq $modelText) { throw 'P3.3 model freshness negative test did not mutate the generated model.' }
    [IO.File]::WriteAllText($modelPath, $mutatedModelText, [Text.UTF8Encoding]::new($false))
    Assert-CommandFails @('-File', (Join-Path $ProjectRoot 'tools/Generate-P33D1Source.ps1'), '-ProjectRoot', $ProjectRoot, '-GeneratedRoot', $modelGeneratedRoot, '-ValidateOnly') 'P3.3 generator accepted generated model source drift.'
    Write-Output 'PASS P3.3 negative typed-model schema parity and generated-model freshness mutations'
}
finally {
    if (Test-Path -LiteralPath $negativeRoot) { Remove-Item -LiteralPath $negativeRoot -Recurse -Force }
}
