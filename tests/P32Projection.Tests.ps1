[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$artifactPath = Join-Path $ProjectRoot 'artifacts/p3.2/CmdletModel.json'
$artifact = Get-Content -Raw -LiteralPath $artifactPath | ConvertFrom-Json
$projectionLibrary = Join-Path $ProjectRoot 'tools/Project-P32Projection.ps1'
. $projectionLibrary -ProjectRoot $ProjectRoot -Library
Assert-True ($artifact.version -eq 3) 'P3.2 canonical artifact version drifted.'
Assert-True ($artifact.sourcePolicy -eq 'normalized-model-plus-projection-policy') 'P3.2 canonical artifact source policy is not canonical.'
Assert-True ($artifact.semanticAlgorithm -eq 'SHA256-CanonicalJson-v1' -and $artifact.canonicalDigest.Length -eq 64) 'P3.2 canonical artifact semantic digest is missing.'
$expectedCmdlets = @('Get-CfZone', 'Get-CfDnsRecord', 'New-CfDnsRecord', 'Remove-CfDnsRecord', 'Set-CfDnsRecord')
$actualCmdlets = @($artifact.cmdlets | ForEach-Object cmdletName)
Assert-True (($actualCmdlets -join '|') -eq ($expectedCmdlets -join '|')) 'P3.2 canonical artifact public cmdlet set drifted.'

$dns = $artifact.cmdlets | Where-Object cmdletName -eq 'Get-CfDnsRecord'
$set = $artifact.cmdlets | Where-Object cmdletName -eq 'Set-CfDnsRecord'
$dnsTagAbsent = $dns.parameters | Where-Object name -eq 'TagAbsent'
$setShadow = $set.parameters | Where-Object name -eq 'IncludeShadowMetadata'
$dnsId = $dns.parameters | Where-Object name -eq 'DnsRecordId'
$setId = $set.parameters | Where-Object name -eq 'DnsRecordId'
Assert-True ($null -ne $dnsTagAbsent -and $dnsTagAbsent.apiBindings.name -contains 'tag.absent') 'Canonical Get-CfDnsRecord TagAbsent projection is incomplete.'
Assert-True ($null -ne $setShadow -and $setShadow.apiBindings.name -contains 'include_shadow_metadata' -and @($setShadow.appliesTo).Count -eq 2) 'Canonical Set-CfDnsRecord IncludeShadowMetadata projection is incomplete.'
Assert-True ($dnsId.aliases -contains 'RecordId' -and $setId.aliases -contains 'RecordId') 'Canonical RecordId aliases are incomplete.'
Write-Output 'PASS P3.2 canonical artifact contract'

$generator = Join-Path $ProjectRoot 'tools/Generate-P32Source.ps1'
$projector = Join-Path $ProjectRoot 'tools/Project-P32Projection.ps1'
$template = Join-Path $ProjectRoot 'tools/templates/P32RepresentativeCmdlets.cs.tmpl'
$generatorText = Get-Content -Raw -LiteralPath $generator
$projectorText = Get-Content -Raw -LiteralPath $projector
Assert-True ($generatorText -notmatch '\$cmdletModels|renderKind|dns-records-for-a-zone|zones-0-get') 'P3.2 generator still contains fixed command-shape or operation-id logic.'
Assert-True ($projectorText -notmatch 'Where-Object cmdletName -eq|operationId -like') 'P3.2 projector still selects a command by name instead of policy capability.'
Assert-True ($generatorText -match '\$Cmdlet\.parameterSets' -and $generatorText -match '\$ParameterSet\.operationBinding' -and $generatorText -match '\$Cmdlet\.execution') 'P3.2 generator is not driven by canonical capability metadata.'
Assert-True (@($artifact.cmdlets | Where-Object { $_.PSObject.Properties.Name -contains 'renderKind' }).Count -eq 0) 'P3.2 artifact retains renderer-shape metadata.'
Write-Output 'PASS P3.2 capability-driven renderer boundary'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('p32-projection-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

function Invoke-GeneratorFailureCase {
    param(
        [Parameter(Mandatory)][object]$MutatedArtifact,
        [Parameter(Mandatory)][string]$Label
    )
    $caseArtifact = Join-Path $tempRoot ($Label + '.json')
    $caseSource = Join-Path $tempRoot ($Label + '.cs')
    $MutatedArtifact | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $caseArtifact -Encoding utf8
    & pwsh -NoLogo -NoProfile -File $generator -ProjectRoot $ProjectRoot -ArtifactPath $caseArtifact -SourcePath $caseSource -TemplatePath $template 2>&1 | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) "Generator accepted invalid canonical artifact case '$Label'."
    Write-Output "PASS generator rejects $Label"
}

function Invoke-RuntimeFailureCase {
    param([Parameter(Mandatory)][string]$Mutation, [Parameter(Mandatory)][string]$Label)
    $runtimeSource = Join-Path $tempRoot ($Label + '.cs')
    $runtimeText = Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Metadata/CfDnsRecordRuntimeMetadata.cs')
    $runtimeText = $runtimeText.Replace($Mutation.Split('|')[0], $Mutation.Split('|')[1])
    Set-Content -LiteralPath $runtimeSource -Value $runtimeText -Encoding utf8
    & pwsh -NoLogo -NoProfile -File $generator -ProjectRoot $ProjectRoot -ArtifactPath $artifactPath -SourcePath (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Cmdlets/P32RepresentativeCmdlets.cs') -TemplatePath $template -RuntimeSourcePath $runtimeSource -ValidateOnly 2>&1 | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) "Generator accepted invalid runtime metadata case '$Label'."
    Write-Output "PASS generator rejects $Label"
}

function Invoke-SourceFailureCase {
    param([Parameter(Mandatory)][string]$Mutation, [Parameter(Mandatory)][string]$Label)
    $sourcePath = Join-Path $tempRoot ($Label + '.cs')
    $sourceText = Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Cmdlets/P32RepresentativeCmdlets.cs')
    $parts = $Mutation.Split('|', 2)
    $mutated = $sourceText.Replace($parts[0], $parts[1])
    Assert-True ($mutated -ne $sourceText) "Source mutation did not change the fixture for '$Label'."
    Set-Content -LiteralPath $sourcePath -Value $mutated -Encoding utf8
    & pwsh -NoLogo -NoProfile -File $generator -ProjectRoot $ProjectRoot -ArtifactPath $artifactPath -SourcePath $sourcePath -TemplatePath $template -RuntimeSourcePath (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Metadata/CfDnsRecordRuntimeMetadata.cs') -ZoneRuntimeSourcePath (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Metadata/CfZoneRuntimeMetadata.cs') -ValidateOnly 2>&1 | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) "Generator accepted renderer drift case '$Label'."
    Write-Output "PASS generator rejects $Label"
}

function Invoke-MissingSourceFailureCase {
    param([Parameter(Mandatory)][string]$Label)
    $missingSourcePath = Join-Path $tempRoot ($Label + '.cs')
    & pwsh -NoLogo -NoProfile -File $generator -ProjectRoot $ProjectRoot -ArtifactPath $artifactPath -SourcePath $missingSourcePath -TemplatePath $template -RuntimeSourcePath (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Metadata/CfDnsRecordRuntimeMetadata.cs') -ZoneRuntimeSourcePath (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Metadata/CfZoneRuntimeMetadata.cs') -ValidateOnly 2>&1 | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) "Generator accepted missing ValidateOnly source case '$Label'."
    Write-Output "PASS generator rejects $Label"
}

function Invoke-ZoneRuntimeFailureCase {
    param([Parameter(Mandatory)][string]$Mutation, [Parameter(Mandatory)][string]$Label)
    $runtimeSource = Join-Path $tempRoot ($Label + '.cs')
    $runtimeText = Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Metadata/CfZoneRuntimeMetadata.cs')
    $parts = $Mutation.Split('|', 2)
    $mutated = $runtimeText.Replace($parts[0], $parts[1])
    Assert-True ($mutated -ne $runtimeText) "Zone runtime mutation did not change the fixture for '$Label'."
    Set-Content -LiteralPath $runtimeSource -Value $mutated -Encoding utf8
    & pwsh -NoLogo -NoProfile -File $generator -ProjectRoot $ProjectRoot -ArtifactPath $artifactPath -SourcePath (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Cmdlets/P32RepresentativeCmdlets.cs') -TemplatePath $template -RuntimeSourcePath (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Metadata/CfDnsRecordRuntimeMetadata.cs') -ZoneRuntimeSourcePath $runtimeSource -ValidateOnly 2>&1 | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) "Generator accepted invalid zone runtime metadata case '$Label'."
    Write-Output "PASS generator rejects $Label"
}

try {
    $stale = $artifact | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $stale.sourceFiles[0].sha256 = ('0' * 64)
    Invoke-GeneratorFailureCase $stale 'stale-input-hash'

    $missingParameter = $artifact | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $missingCmdlet = $missingParameter.cmdlets | Where-Object cmdletName -eq 'Get-CfDnsRecord'
    $missingCmdlet.parameters = @($missingCmdlet.parameters | Where-Object name -ne 'TagContains')
    Invoke-GeneratorFailureCase $missingParameter 'missing-parameter'

    $wrongType = $artifact | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    ($wrongType.cmdlets | Where-Object cmdletName -eq 'Get-CfDnsRecord').parameters | Where-Object name -eq 'TagAbsent' | ForEach-Object { $_.type = 'bool' }
    Invoke-GeneratorFailureCase $wrongType 'semantic-type-drift'

    $wrongTypeWithValidDigest = $artifact | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    ($wrongTypeWithValidDigest.cmdlets | Where-Object cmdletName -eq 'Get-CfDnsRecord').parameters | Where-Object name -eq 'TagAbsent' | ForEach-Object { $_.type = 'bool' }
    $wrongTypeWithValidDigest.canonicalDigest = Get-P32CanonicalDigest $wrongTypeWithValidDigest
    Invoke-GeneratorFailureCase $wrongTypeWithValidDigest 'semantic-type-drift-valid-digest'

    $wrongEnvelope = $artifact | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    ($wrongEnvelope.cmdlets | ForEach-Object operations | Where-Object operationId -eq 'dns-records-for-a-zone-list-dns-records').runtime.responseRepresentations[0].envelopePolicy = 'WrongEnvelope'
    Invoke-GeneratorFailureCase $wrongEnvelope 'semantic-runtime-envelope-drift'

    $wrongPagination = $artifact | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    ($wrongPagination.cmdlets | ForEach-Object operations | Where-Object operationId -eq 'dns-records-for-a-zone-list-dns-records').runtime.pagination.stopRule = 'never'
    Invoke-GeneratorFailureCase $wrongPagination 'semantic-pagination-drift'

    Invoke-RuntimeFailureCase 'EnvelopePolicy = "CloudflareResult"|EnvelopePolicy = "WrongEnvelope"' 'runtime-envelope-source-drift'
    Invoke-RuntimeFailureCase 'ContentType = "application/json", BodyParameterName = "body"|ContentType = "application/xml", BodyParameterName = "body"' 'runtime-request-source-drift'
    Invoke-RuntimeFailureCase 'ParsingMode = "Json"|ParsingMode = "Xml"' 'runtime-response-source-drift'
    Invoke-RuntimeFailureCase 'CurrentPagePath = ("result_info" + ".page")|CurrentPagePath = ("result_info" + ".current")' 'runtime-pagination-path-source-drift'
    Invoke-RuntimeFailureCase 'StopRule = "empty result page"|StopRule = "never"' 'runtime-pagination-source-drift'

    Invoke-SourceFailureCase '"tag.absent")|"tag.changed")' 'renderer-api-binding-drift'
    Invoke-SourceFailureCase 'dns-records-for-a-zone-dns-record-details")|dns-records-for-a-zone-dns-record-changed")' 'renderer-operation-id-drift'
    Invoke-SourceFailureCase 'BindParametersWithBody(Record.ToJson(),|BindParametersWithBody(Record.ToString(),' 'renderer-body-binding-drift'
    Invoke-SourceFailureCase '"Create DNS record"|"Changed DNS record"' 'renderer-should-process-drift'
    Invoke-MissingSourceFailureCase 'renderer-source-missing'

    Invoke-ZoneRuntimeFailureCase 'Method = "GET"|Method = "POST"' 'zone-runtime-method-drift'
    Invoke-ZoneRuntimeFailureCase 'PathTemplate = "/zones/{zone_id}"|PathTemplate = "/zones/{zone}"' 'zone-runtime-path-drift'
    Invoke-ZoneRuntimeFailureCase 'EnvelopePolicy = "CloudflareResult"|EnvelopePolicy = "WrongEnvelope"' 'zone-runtime-envelope-drift'
    Invoke-ZoneRuntimeFailureCase 'ParsingMode = "Json"|ParsingMode = "Xml"' 'zone-runtime-parsing-drift'
    Invoke-ZoneRuntimeFailureCase 'CurrentPagePath = ("result_info" + ".page")|CurrentPagePath = ("result_info" + ".current")' 'zone-runtime-pagination-path-drift'
    Invoke-ZoneRuntimeFailureCase 'StopRule = "empty result page"|StopRule = "never"' 'zone-runtime-stop-rule-drift'

    $unconsumedBody = $artifact | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $createSet = $unconsumedBody.cmdlets | Where-Object cmdletName -eq 'New-CfDnsRecord' | ForEach-Object { $_.parameterSets | Where-Object name -eq 'Create' }
    $createSet.operationBinding.bodyParameter = $null
    Invoke-GeneratorFailureCase $unconsumedBody 'unconsumed-body-parameter'

    $unknownOperation = $artifact | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $unknownCmdlet = $unknownOperation.cmdlets | Where-Object cmdletName -eq 'Get-CfDnsRecord'
    $unknownCmdlet.parameterSets | Where-Object name -eq 'Get' | ForEach-Object { $_.operationId = 'p32-unknown-operation' }
    $unknownCmdlet.operations = @($unknownCmdlet.operations | ForEach-Object {
        if ($_.operationId -eq 'dns-records-for-a-zone-dns-record-details') { $_.operationId = 'p32-unknown-operation' }
        $_
    })
    Invoke-GeneratorFailureCase $unknownOperation 'unknown-operation-id'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Output 'PASS P3.2 generator negative contract checks'
