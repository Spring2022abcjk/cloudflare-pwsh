[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$FixtureRoot = (Join-Path $ProjectRoot 'fixtures/p2.1'),
    [string]$ProjectionPath = (Join-Path $ProjectRoot 'overrides/powershell-projection.json'),
    [string]$ArtifactRoot = (Join-Path $ProjectRoot 'artifacts/p2.1/projection'),
    [string]$MetadataRoot = (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Metadata')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PropertyValue {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) { return $null }
    return $Object.PSObject.Properties[$Name].Value
}

function ConvertTo-Title {
    param([string]$Value)
    return (($Value -split '[-_]' | Where-Object { $_ }) | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }) -join ''
}

function ConvertTo-Identifier {
    param([string]$Value)
    $identifier = [regex]::Replace($Value, '[^A-Za-z0-9_]', '_')
    $identifier = [regex]::Replace($identifier, '_+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($identifier)) { return 'Resource' }
    if ($identifier[0] -match '[0-9]') { return "N_$identifier" }
    return $identifier
}

function Get-ProjectionOverride {
    param([object]$Document, [string]$OperationId)
    $property = $Document.operations.PSObject.Properties[$OperationId]
    if ($null -eq $property) { return [pscustomobject]@{} }
    return $property.Value
}

function Get-ProjectedVerb {
    param([object]$Operation, [object]$Override)
    $explicit = Get-PropertyValue $Override 'verb'
    if ($null -ne $explicit) { return [string]$explicit }
    switch ([string]$Operation.operationSemantic.kind) {
        'List' { return 'Get' }
        'Get' { return 'Get' }
        'Create' { return 'New' }
        'Update' { return 'Set' }
        'Edit' { return 'Set' }
        'Delete' { return 'Remove' }
        'Download' { return 'Get' }
        'Upload' { return 'New' }
        default { return 'Invoke' }
    }
}

function Get-ProjectedNoun {
    param([object]$Operation, [object]$Override)
    $explicit = Get-PropertyValue $Override 'noun'
    if ($null -ne $explicit) { return [string]$explicit }
    return ((@($Operation.resourcePath) | ForEach-Object { ConvertTo-Title ([string]$_) }) -join '')
}

function ConvertTo-Projection {
    param([object]$Operation, [object]$ProjectionDocument)
    $override = Get-ProjectionOverride $ProjectionDocument $Operation.operationId
    $requestBody = Get-PropertyValue $Operation 'requestBody'
    $pagination = Get-PropertyValue $Operation 'pagination'
    $parameterRenames = Get-PropertyValue $override 'parameterRenames'
    $parameters = @($Operation.parameters | Sort-Object location, name | ForEach-Object {
        $projectedName = $_.name
        if ($null -ne $parameterRenames -and $null -ne $parameterRenames.PSObject.Properties[$_.name]) { $projectedName = $parameterRenames.PSObject.Properties[$_.name].Value }
        [pscustomobject]@{
            name = $projectedName
            apiName = $_.name
            binding = $_.location
            required = [bool]$_.required
            nullPolicy = $_.nullPolicy
            schema = $_.schema
            defaultValue = Get-PropertyValue $_ 'defaultValue'
        }
    })
    [pscustomobject]@{
        operationId = $Operation.operationId
        cmdletName = "$(Get-ProjectedVerb $Operation $override)-$(Get-ProjectedNoun $Operation $override)"
        parameterSet = if ($null -ne (Get-PropertyValue $override 'parameterSet')) { $override.parameterSet } else { $Operation.operationSemantic.kind }
        semantic = $Operation.operationSemantic
        method = $Operation.method
        pathTemplate = $Operation.pathTemplate
        resourcePath = @($Operation.resourcePath)
        scopeBindings = @($Operation.scopeBindings | Sort-Object parameterName | ForEach-Object { [pscustomobject]@{ parameterName = $_.parameterName; scopeType = $_.scopeType; role = $_.role } })
        parameters = $parameters
        requestRepresentations = if ($null -ne $requestBody) { @($requestBody.representations | ForEach-Object { [pscustomobject]@{ contentType = $_.contentType; schema = $_.schema } }) } else { @() }
        responseCases = @($Operation.responses | Sort-Object { $_.statusSelector.value } | ForEach-Object { [pscustomobject]@{ status = $_.statusSelector.value; kind = $_.statusSelector.kind; representations = @($_.representations | ForEach-Object { [pscustomobject]@{ contentType = $_.contentType; schema = $_.schema; envelopePolicy = $_.envelopePolicy; parsingMode = $_.parsingMode } }) } })
        pagination = if ($null -ne $pagination) { [pscustomobject]@{ strategy = $pagination.strategy; outputPolicy = Get-PropertyValue $override 'outputPolicy'; behavior = Get-PropertyValue $override 'paging' } } else { $null }
        supportsShouldProcess = [bool](Get-PropertyValue $override 'supportsShouldProcess')
        confirmImpact = if ($null -ne (Get-PropertyValue $override 'confirmImpact')) { [string]$override.confirmImpact } else { 'None' }
    }
}

function Write-Utf8CrLf {
    param([string]$Path, [string]$Content)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $normalized = $Content.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
    [System.IO.File]::WriteAllText($Path, $normalized, [System.Text.UTF8Encoding]::new($false))
}

$projectionDocument = Get-Content -Raw -LiteralPath $ProjectionPath | ConvertFrom-Json
New-Item -ItemType Directory -Force -Path $ArtifactRoot, $MetadataRoot | Out-Null

foreach ($fixture in Get-ChildItem -LiteralPath $FixtureRoot -Directory | Sort-Object Name) {
    $document = Get-Content -Raw -LiteralPath (Join-Path $fixture.FullName 'document.json') | ConvertFrom-Json
    $operations = @($document.operations | Sort-Object operationId | ForEach-Object { ConvertTo-Projection $_ $projectionDocument })
    $cmdlets = @($operations | Group-Object cmdletName | Sort-Object Name | ForEach-Object {
        $impactValues = @($_.Group | Sort-Object confirmImpact | ForEach-Object confirmImpact)
        [pscustomobject]@{
            cmdletName = $_.Name
            operationIds = @($_.Group | Sort-Object operationId | ForEach-Object operationId)
            parameterSets = @($_.Group | Sort-Object parameterSet | ForEach-Object { [pscustomobject]@{ name = $_.parameterSet; required = @($_.parameters | Where-Object required | ForEach-Object name); operationId = $_.operationId } })
            scopeBindings = @($_.Group | ForEach-Object { @(Get-PropertyValue $_ 'scopeBindings') } | Sort-Object parameterName, role | ForEach-Object { "{0}:{1}:{2}" -f $_.parameterName, $_.scopeType, $_.role } | Select-Object -Unique)
            outputPolicies = @($_.Group.pagination | Where-Object { $null -ne $_ } | ForEach-Object outputPolicy | Select-Object -Unique)
            supportsShouldProcess = @($_.Group | Where-Object supportsShouldProcess).Count -gt 0
            confirmImpact = if ($impactValues.Count -gt 0) { $impactValues[-1] } else { 'None' }
        }
    })
    $result = [pscustomobject]@{ resource = $fixture.Name; operations = $operations; cmdlets = $cmdlets }
    Write-Utf8CrLf (Join-Path $ArtifactRoot "$($fixture.Name).json") ($result | ConvertTo-Json -Depth 100)

    $className = "P21_$(ConvertTo-Identifier $fixture.Name)Projection"
    $operationIds = @($operations | ForEach-Object operationId) -join ';'
    $cmdletNames = @($cmdlets | ForEach-Object cmdletName) -join ';'
    $scopeBindings = @($operations | ForEach-Object { @(Get-PropertyValue $_ 'scopeBindings') } | Sort-Object parameterName, role | ForEach-Object { "{0}:{1}:{2}" -f $_.parameterName, $_.scopeType, $_.role } | Select-Object -Unique) -join ';'
    $metadata = @"
// <auto-generated />
#nullable enable
namespace Cloudflare.PowerShell;

public static class $className
{
    public const string Resource = "$($fixture.Name)";
    public const string OperationIds = "$operationIds";
    public const string CmdletNames = "$cmdletNames";
    public const string ScopeBindings = "$scopeBindings";
}
"@
    Write-Utf8CrLf (Join-Path $MetadataRoot "$className.cs") $metadata
    Write-Output "Projected $($fixture.Name): operations=$($operations.Count), cmdlets=$($cmdlets.Count)"
}
