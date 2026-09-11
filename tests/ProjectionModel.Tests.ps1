[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("cf-p1-projection-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot 'fixtures/dns-records'), (Join-Path $tempRoot 'overrides') | Out-Null

function Write-JsonFixture {
    param([string]$Name, [string]$OperationId, [string]$Method, [string]$Path, [object[]]$Parameters)
    $fixture = [ordered]@{
        version = 1; operationId = $OperationId; method = $Method; pathTemplate = $Path; resourcePath = @('synthetic', 'things')
        operationSemantic = [ordered]@{ kind = if ($Method -eq 'PUT') { 'Update' } else { 'Edit' }; source = 'Override'; confidence = 'High' }
        parameters = $Parameters
        responses = @([ordered]@{ statusSelector = [ordered]@{ kind = 'Exact'; value = '200' }; representations = @([ordered]@{ contentType = 'application/json'; schema = 'Thing'; envelopePolicy = 'CloudflareResult'; parsingMode = 'Json' }) })
    }
    $fixture | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $tempRoot "fixtures/dns-records/$Name.json") -Encoding utf8NoBOM
}

$common = [ordered]@{ name = 'zone_id'; location = 'path'; required = $true; allowsNull = $false; nullPolicy = 'reject-null'; schema = 'Identifier' }
$replaceOnly = [ordered]@{ name = 'replace_only'; location = 'query'; required = $true; allowsNull = $false; nullPolicy = 'reject-null'; schema = 'string' }
$editOnly = [ordered]@{ name = 'edit_only'; location = 'query'; required = $true; allowsNull = $false; nullPolicy = 'reject-null'; schema = 'string' }
Write-JsonFixture 'replace' 'synthetic-replace' 'PUT' '/things/{zone_id}' @($common, $replaceOnly)
Write-JsonFixture 'edit' 'synthetic-edit' 'PATCH' '/things/{zone_id}' @($common, $editOnly)

@{ version = 1; rules = @() } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $tempRoot 'overrides/api-corrections.json') -Encoding utf8NoBOM
@{
    version = 1
    operations = [ordered]@{
        'synthetic-replace' = [ordered]@{ verb = 'Set'; noun = 'CfThing'; parameterSet = 'Replace'; supportsShouldProcess = $true; confirmImpact = 'Low' }
        'synthetic-edit' = [ordered]@{ verb = 'Set'; noun = 'CfThing'; parameterSet = 'Edit'; supportsShouldProcess = $true; confirmImpact = 'High' }
    }
} | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $tempRoot 'overrides/powershell-projection.json') -Encoding utf8NoBOM

try {
    & pwsh -NoLogo -NoProfile -File (Join-Path $ProjectRoot 'tools/Generate-DnsSource.ps1') -ProjectRoot $tempRoot -ExpectedOperationCount 2 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Synthetic generator run failed.' }
    $model = @(Get-Content -Raw -LiteralPath (Join-Path $tempRoot 'artifacts/projection/CmdletModel.json') | ConvertFrom-Json)
    $cmdlet = $model | Where-Object CmdletName -eq 'Set-CfThing'
    if ($null -eq $cmdlet) { throw 'Merged cmdlet missing.' }
    $parameterA = $cmdlet.Parameters | Where-Object Name -eq 'replace_only'
    $parameterB = $cmdlet.Parameters | Where-Object Name -eq 'edit_only'
    $commonParameter = $cmdlet.Parameters | Where-Object Name -eq 'zone_id'
    if ((@($parameterA.AppliesTo) -join ',') -ne 'synthetic-replace') { throw 'Replace-only applicability leaked.' }
    if ((@($parameterB.AppliesTo) -join ',') -ne 'synthetic-edit') { throw 'Edit-only applicability leaked.' }
    if (@($commonParameter.AppliesTo).Count -ne 2) { throw 'Common parameter did not merge.' }
    if ($cmdlet.ConfirmImpact -ne 'High') { throw 'ConfirmImpact rank merge failed.' }
    $replaceSet = $cmdlet.ParameterSets | Where-Object Name -eq 'Replace'
    $editSet = $cmdlet.ParameterSets | Where-Object Name -eq 'Edit'
    if ($replaceSet.OperationBinding.HttpMethod -ne 'PUT' -or $editSet.OperationBinding.HttpMethod -ne 'PATCH') { throw 'Operation binding method mismatch.' }
    if (@($replaceSet.RequiredParameters) -notcontains 'replace_only') { throw 'Replace requiredness missing.' }
    if (@($editSet.RequiredParameters) -notcontains 'edit_only') { throw 'Edit requiredness missing.' }
    Write-Output 'PASS multi-operation projection, parameter applicability, and impact rank'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
