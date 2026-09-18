[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $ProjectRoot 'module/Cloudflare.PowerShell'
$dllPath = Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/bin/Release/net10.0/Cloudflare.PowerShell.dll'
Copy-Item -LiteralPath $dllPath -Destination $modulePath -Force
$bundledRuntimeFiles = @(Get-ChildItem -LiteralPath $modulePath -Recurse -File | Where-Object {
    $_.Name -in @('System.Management.Automation.dll', 'Microsoft.PowerShell.SDK.dll') -or
    $_.Name -like 'Microsoft.PowerShell*.dll' -or
    $_.FullName -match '[\\/]runtimes[\\/]'
})
if ($bundledRuntimeFiles.Count -ne 0) {
    throw "Module staging contains bundled PowerShell runtime files: $($bundledRuntimeFiles.FullName -join ', ')"
}

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public sealed class P32MockHandler : HttpMessageHandler
{
    public static List<HttpRequestMessage> Requests { get; } = new();
    public static List<string> Bodies { get; } = new();
    public static string FailMode { get; set; } = "";
    public static void Reset() { Requests.Clear(); Bodies.Clear(); FailMode = ""; }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Requests.Add(request);
        Bodies.Add(request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellationToken));
        var path = request.RequestUri.AbsolutePath;
        var query = request.RequestUri.Query;
        if (FailMode == "bad" || query.Contains("name=fail", StringComparison.Ordinal))
        {
            var error = new HttpResponseMessage(HttpStatusCode.BadRequest)
            {
                Content = new StringContent("{\"success\":false,\"errors\":[{\"code\":1001,\"message\":\"bad request\"}]}", Encoding.UTF8, "application/json")
            };
            error.Headers.TryAddWithoutValidation("CF-Ray", "p32-ray-1");
            return error;
        }
        if (FailMode == "retry")
        {
            var error = new HttpResponseMessage(HttpStatusCode.ServiceUnavailable)
            {
                Content = new StringContent("{\"success\":false,\"errors\":[{\"code\":1002,\"message\":\"retry boundary\"}]}", Encoding.UTF8, "application/json")
            };
            error.Headers.TryAddWithoutValidation("CF-Ray", "p32-retry-ray");
            error.Headers.TryAddWithoutValidation("x-should-retry", "true");
            return error;
        }
        if (request.Method == HttpMethod.Delete)
            return Response("{\"success\":true,\"result\":{}}");
        if (request.Method == HttpMethod.Post)
            return Response("{\"success\":true,\"result\":{\"id\":\"created\",\"type\":\"A\"}}");
        if (request.Method == HttpMethod.Put || request.Method == HttpMethod.Patch)
            return Response("{\"success\":true,\"result\":{\"id\":\"record\",\"type\":\"A\",\"name\":\"example.com\"}}");
        if (path.EndsWith("/dns_records/record", StringComparison.Ordinal))
            return Response("{\"success\":true,\"result\":{\"id\":\"record\",\"type\":\"A\",\"name\":\"example.com\"}}");
        if (path.EndsWith("/dns_records", StringComparison.Ordinal))
        {
            var result = query.Contains("page=2", StringComparison.Ordinal)
                ? "[]"
                : "[{\"id\":\"r1\",\"name\":\"example.com\",\"type\":\"A\",\"content\":\"198.51.100.4\"}]";
            return Response("{\"success\":true,\"result\":" + result + ",\"result_info\":{\"page\":1,\"total_pages\":2}}");
        }
        if (path.EndsWith("/zones/zone", StringComparison.Ordinal))
            return Response("{\"success\":true,\"result\":{\"id\":\"zone\",\"name\":\"example.com\",\"status\":\"active\",\"type\":\"full\"}}");
        var zones = query.Contains("page=2", StringComparison.Ordinal)
            ? "[]"
            : "[{\"id\":\"zone\",\"name\":\"example.com\",\"status\":\"active\",\"type\":\"full\"}]";
        return Response("{\"success\":true,\"result\":" + zones + ",\"result_info\":{\"page\":1,\"total_pages\":2}}");
    }

    private static HttpResponseMessage Response(string body)
        => new(HttpStatusCode.OK) { Content = new StringContent(body, Encoding.UTF8, "application/json") };
}
'@

Import-Module (Join-Path $modulePath 'Cloudflare.PowerShell.psd1') -Force
$hostSmaPath = [System.Management.Automation.PSCmdlet].Assembly.Location
$expectedHostSmaPath = Join-Path $PSHOME 'System.Management.Automation.dll'
if ([IO.Path]::GetFullPath($hostSmaPath) -ne [IO.Path]::GetFullPath($expectedHostSmaPath)) {
    throw "PowerShell runtime SMA was not loaded from the current host: $hostSmaPath"
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-GeneratedCommand {
    param([Parameter(Mandatory)][string]$Name)
    $command = Get-Command $Name -ErrorAction Stop
    Assert-True ($command.CommandType -eq 'Cmdlet') "Public command '$Name' did not resolve to a generated cmdlet."
    $shadowingFunctions = @(Get-Command $Name -All -ErrorAction Stop | Where-Object CommandType -eq 'Function')
    Assert-True ($shadowingFunctions.Count -eq 0) "Public command '$Name' is still shadowed by an exported function."
    return $command
}

function Get-HelpEvidence {
    param([Parameter(Mandatory)][string]$Name)
    $help = Get-Help $Name -Full -ErrorAction Stop
    return [pscustomobject]@{
        Name = $Name
        Synopsis = [string]$help.Synopsis
        Description = [string]$help.Description.Text
    }
}

function Get-RequestFacts {
    param([Parameter(Mandatory)]$Request, [Parameter(Mandatory)][AllowEmptyString()][string]$Body)
    $authorization = if ($Request.Headers.Authorization) { $Request.Headers.Authorization.ToString() } else { '' }
    $contentType = if ($Request.Content -and $Request.Content.Headers.ContentType) { $Request.Content.Headers.ContentType.ToString() } else { '' }
    return [pscustomobject]@{
        Method = $Request.Method.Method
        Path = $Request.RequestUri.AbsolutePath
        Query = $Request.RequestUri.Query
        Authorization = $authorization
        ContentType = $contentType
        Body = $Body
    }
}

function Assert-RequestFactsEqual {
    param([Parameter(Mandatory)]$Expected, [Parameter(Mandatory)]$Actual, [Parameter(Mandatory)][string]$Label)
    $expectedBodyNode = $null
    $actualBodyNode = $null
    $bodyIsJson = $Expected.ContentType -like 'application/json*' -and $Actual.ContentType -like 'application/json*' -and $Expected.Body
    if ($bodyIsJson) {
        $expectedBodyNode = [System.Text.Json.Nodes.JsonNode]::Parse($Expected.Body)
        $actualBodyNode = [System.Text.Json.Nodes.JsonNode]::Parse($Actual.Body)
    }
    $expectedComparable = [ordered]@{ Method = $Expected.Method; Path = $Expected.Path; Query = $Expected.Query; Authorization = $Expected.Authorization; ContentType = $Expected.ContentType }
    $actualComparable = [ordered]@{ Method = $Actual.Method; Path = $Actual.Path; Query = $Actual.Query; Authorization = $Actual.Authorization; ContentType = $Actual.ContentType }
    $expectedJson = $expectedComparable | ConvertTo-Json -Compress -Depth 10
    $actualJson = $actualComparable | ConvertTo-Json -Compress -Depth 10
    Assert-True ($expectedJson -eq $actualJson) "$Label request parity failed. Expected $expectedJson, actual $actualJson."
    if ($bodyIsJson) { Assert-True ([System.Text.Json.Nodes.JsonNode]::DeepEquals($expectedBodyNode, $actualBodyNode)) "$Label JSON body parity failed." }
    else { Assert-True ($Expected.Body -eq $Actual.Body) "$Label request body parity failed." }
}

function Invoke-HandwrittenZone {
    param([Parameter(Mandatory)][hashtable]$Arguments)
    $module = Get-Module Cloudflare.PowerShell -ErrorAction Stop
    return @(& $module { param($bound) Invoke-CfZoneHandwritten @bound } $Arguments)
}

function Get-ErrorFacts {
    param([Parameter(Mandatory)][scriptblock]$Invocation)
    try {
        & $Invocation | Out-Null
        throw 'Expected a terminating Cloudflare error.'
    }
    catch {
        $exception = $_.Exception
        while ($exception -and $exception -isnot [Cloudflare.PowerShell.CloudflareApiException] -and $exception.InnerException) {
            $exception = $exception.InnerException
        }
        if ($exception -isnot [Cloudflare.PowerShell.CloudflareApiException]) {
            throw "Expected CloudflareApiException in ErrorRecord, got '$($_.Exception.GetType().FullName)': $($_.Exception.Message)"
        }
        return [pscustomobject]@{
            Id = $exception.FullyQualifiedErrorId
            Category = [string]$_.CategoryInfo.Category
            Target = [string]$_.TargetObject
            RequestId = [string]$exception.RequestId
            ErrorCode = [int]$exception.Errors[0].Code
            RawBody = [string]$exception.RawBody
            RetryCount = [int]$exception.RetryCount
        }
    }
}

function Assert-RuntimeOperationParity {
    param([Parameter(Mandatory)][object]$Expected, [Parameter(Mandatory)][object]$Actual)
    $label = [string]$Expected.operationId
    Assert-True ([string]$Actual.OperationId -eq $label) "Runtime operation id drifted for '$label'."
    Assert-True ([string]$Actual.Method -eq [string]$Expected.method) "Runtime method drifted for '$label'."
    Assert-True ([string]$Actual.PathTemplate -eq [string]$Expected.pathTemplate) "Runtime path drifted for '$label'."
    $expectedParameters = @($Expected.runtime.parameters | ForEach-Object { "$($_.name)|$($_.location)|$(([bool]$_.required).ToString().ToLowerInvariant())" } | Sort-Object)
    $actualParameters = @($Actual.Parameters | ForEach-Object { "$($_.Name)|$($_.Location)|$(([bool]$_.Required).ToString().ToLowerInvariant())" } | Sort-Object)
    Assert-True (($actualParameters -join '|') -eq ($expectedParameters -join '|')) "Runtime parameters drifted for '$label'."
    $expectedRequests = @($Expected.runtime.requestRepresentations | Where-Object { $null -ne $_ })
    $actualRequests = @($Actual.RequestRepresentations)
    Assert-True ($actualRequests.Count -eq $expectedRequests.Count) "Runtime request representation count drifted for '$label'."
    for ($index = 0; $index -lt $expectedRequests.Count; $index++) {
        Assert-True ([string]$actualRequests[$index].ContentType -eq [string]$expectedRequests[$index].contentType -and [string]$actualRequests[$index].BodyParameterName -eq [string]$expectedRequests[$index].bodyParameterName) "Runtime request representation drifted for '$label'."
        $expectedParts = @($expectedRequests[$index].parts)
        $actualParts = @($actualRequests[$index].Parts)
        Assert-True ($actualParts.Count -eq $expectedParts.Count) "Runtime request parts drifted for '$label'."
        for ($partIndex = 0; $partIndex -lt $expectedParts.Count; $partIndex++) {
            $expectedPart = $expectedParts[$partIndex]
            $actualPart = $actualParts[$partIndex]
            Assert-True ([string]$actualPart.ParameterName -eq [string]$expectedPart.parameterName -and [string]$actualPart.PartName -eq [string]$expectedPart.partName -and [string]$actualPart.ContentType -eq [string]$expectedPart.contentType -and [string]$actualPart.Format -eq [string]$expectedPart.format -and [bool]$actualPart.Required -eq [bool]$expectedPart.required) "Runtime request part metadata drifted for '$label'."
        }
    }
    $expectedResponses = @($Expected.runtime.responseRepresentations | Where-Object { $null -ne $_ })
    $actualResponses = @($Actual.ResponseRepresentations)
    Assert-True ($actualResponses.Count -eq $expectedResponses.Count) "Runtime response representation count drifted for '$label'."
    for ($index = 0; $index -lt $expectedResponses.Count; $index++) {
        $statusMatches = ($null -eq $expectedResponses[$index].statusCode -and $null -eq $actualResponses[$index].StatusCode) -or ([int]$actualResponses[$index].StatusCode -eq [int]$expectedResponses[$index].statusCode)
        Assert-True ($statusMatches -and [string]$actualResponses[$index].ContentType -eq [string]$expectedResponses[$index].contentType -and [string]$actualResponses[$index].EnvelopePolicy -eq [string]$expectedResponses[$index].envelopePolicy -and [string]$actualResponses[$index].ParsingMode -eq [string]$expectedResponses[$index].parsingMode) "Runtime response representation drifted for '$label'."
    }
    $expectedPaging = $Expected.runtime.pagination
    $actualPaging = $Actual.Pagination
    if ($null -eq $expectedPaging) {
        Assert-True ($null -eq $actualPaging) "Runtime pagination unexpectedly exists for '$label'."
        return
    }
    Assert-True ($null -ne $actualPaging) "Runtime pagination is missing for '$label'."
    foreach ($field in @('strategy','resultPath','pageInfoPath','currentPagePath','totalPagesPath','nextCursorPath','hasMorePath','nextPageRule','stopRule')) {
        $actualName = $field.Substring(0,1).ToUpperInvariant() + $field.Substring(1)
        Assert-True ([string]$actualPaging.$actualName -eq [string]$expectedPaging.$field) "Runtime pagination '$field' drifted for '$label'."
    }
    Assert-True ((@($actualPaging.RequestFields) -join '|') -eq (@($expectedPaging.requestFields) -join '|')) "Runtime pagination request fields drifted for '$label'."
    Assert-True ((@($actualPaging.ResponseFields) -join '|') -eq (@($expectedPaging.responseFields) -join '|')) "Runtime pagination response fields drifted for '$label'."
}

$zoneCommand = Get-GeneratedCommand 'Get-CfZone'
$dnsCommand = Get-GeneratedCommand 'Get-CfDnsRecord'
$newCommand = Get-GeneratedCommand 'New-CfDnsRecord'
$removeCommand = Get-GeneratedCommand 'Remove-CfDnsRecord'
$setCommand = Get-GeneratedCommand 'Set-CfDnsRecord'
Assert-True (@($zoneCommand.ParameterSets.Name) -contains 'List' -and @($zoneCommand.ParameterSets.Name) -contains 'Get') 'Get-CfZone parameter sets are incomplete.'
Assert-True (@($dnsCommand.ParameterSets.Name) -contains 'List' -and @($dnsCommand.ParameterSets.Name) -contains 'Get') 'Get-CfDnsRecord parameter sets are incomplete.'
Assert-True ($zoneCommand.OutputType.Type.FullName -contains 'Cloudflare.PowerShell.CfZone') 'Get-CfZone output metadata is not typed.'
Assert-True ($dnsCommand.OutputType.Type.FullName -contains 'Cloudflare.PowerShell.CfDnsRecord') 'Get-CfDnsRecord output metadata is not typed.'
Assert-True (@($removeCommand.OutputType).Count -eq 0) 'Remove-CfDnsRecord incorrectly reports an output type.'
$zoneAttribute = @($zoneCommand.Parameters['ZoneId'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })[0]
Assert-True $zoneAttribute.ValueFromPipelineByPropertyName 'Get-CfZone ZoneId pipeline binding is missing.'
$newMetadata = [System.Management.Automation.CommandMetadata]::new($newCommand)
$removeMetadata = [System.Management.Automation.CommandMetadata]::new($removeCommand)
Assert-True $newMetadata.SupportsShouldProcess 'New-CfDnsRecord ShouldProcess metadata is missing.'
Assert-True $removeMetadata.SupportsShouldProcess 'Remove-CfDnsRecord ShouldProcess metadata is missing.'
$setMetadata = [System.Management.Automation.CommandMetadata]::new($setCommand)
Assert-True $setMetadata.SupportsShouldProcess 'Set-CfDnsRecord ShouldProcess metadata is missing.'
Assert-True (@($setCommand.ParameterSets.Name) -contains 'Replace' -and @($setCommand.ParameterSets.Name) -contains 'Edit') 'Set-CfDnsRecord operation parameter sets are incomplete.'
$setReplaceAttributes = @($setCommand.Parameters['Replace'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
$setEditAttributes = @($setCommand.Parameters['Edit'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
Assert-True ($setReplaceAttributes.Count -eq 1 -and $setReplaceAttributes[0].Mandatory -and $setReplaceAttributes[0].ParameterSetName -eq 'Replace') 'Set-CfDnsRecord Replace requiredness drifted.'
Assert-True ($setEditAttributes.Count -eq 1 -and $setEditAttributes[0].Mandatory -and $setEditAttributes[0].ParameterSetName -eq 'Edit') 'Set-CfDnsRecord Edit requiredness drifted.'
Assert-True $dnsCommand.Parameters.ContainsKey('TagAbsent') 'Get-CfDnsRecord TagAbsent projection is missing.'
Assert-True $setCommand.Parameters.ContainsKey('IncludeShadowMetadata') 'Set-CfDnsRecord IncludeShadowMetadata projection is missing.'
$setShadowAttributes = @($setCommand.Parameters['IncludeShadowMetadata'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
Assert-True ($setShadowAttributes.Count -eq 2 -and @($setShadowAttributes.ParameterSetName) -contains 'Edit' -and @($setShadowAttributes.ParameterSetName) -contains 'Replace') 'Set-CfDnsRecord IncludeShadowMetadata parameter-set applicability drifted.'
Assert-True ($dnsCommand.Parameters['DnsRecordId'].Aliases -contains 'RecordId') 'Get-CfDnsRecord RecordId compatibility alias is missing.'
Assert-True ($removeCommand.Parameters['DnsRecordId'].Aliases -contains 'RecordId') 'Remove-CfDnsRecord RecordId compatibility alias is missing.'
Assert-True ($setCommand.Parameters['DnsRecordId'].Aliases -contains 'RecordId') 'Set-CfDnsRecord RecordId compatibility alias is missing.'
Assert-True ([Cloudflare.PowerShell.P32CmdletHelpMetadata]::Commands.ContainsKey('Get-CfZone')) 'Generated Get-CfZone help model is missing.'
Assert-True (-not [string]::IsNullOrWhiteSpace([Cloudflare.PowerShell.P32CmdletHelpMetadata]::Commands['Get-CfZone'].Synopsis)) 'Generated Get-CfZone help synopsis is missing.'
Assert-True (@([Cloudflare.PowerShell.P32PipelineIdentityMetadata]::Aliases | Where-Object { $_.TypeName -eq 'Cloudflare.PowerShell.CfZone' -and $_.AliasName -eq 'ZoneId' -and $_.SourceProperty -eq 'Id' }).Count -eq 1) 'Generated CfZone pipeline identity metadata is missing.'
Assert-True (@([Cloudflare.PowerShell.P32PipelineIdentityMetadata]::Aliases | Where-Object { $_.TypeName -eq 'Cloudflare.PowerShell.CfDnsRecord' -and $_.AliasName -eq 'DnsRecordId' -and $_.SourceProperty -eq 'Id' }).Count -eq 1) 'Generated CfDnsRecord pipeline identity metadata is missing.'
$identityZone = [Cloudflare.PowerShell.CfZone]::new()
$identityZone.Id = 'zone'
$identityRecord = [Cloudflare.PowerShell.CfDnsRecord]::new()
$identityRecord.Id = 'record'
Assert-True (@($identityZone | Get-Member -Name ZoneId).Count -eq 1 -and @($identityRecord | Get-Member -Name DnsRecordId).Count -eq 1) 'ETS pipeline identity aliases are not discoverable.'
Assert-True (($identityZone | ConvertTo-Json -Compress) -match '"ZoneId":"zone"' -and ($identityRecord | ConvertTo-Json -Compress) -match '"DnsRecordId":"record"') 'ETS pipeline identity serialization behavior drifted.'
$dnsRecordIdAttributes = @($dnsCommand.Parameters['DnsRecordId'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
Assert-True ($dnsRecordIdAttributes.Count -eq 1 -and $dnsRecordIdAttributes[0].Mandatory -and $dnsRecordIdAttributes[0].ParameterSetName -eq 'Get') 'DNS record id requiredness/applicability drifted.'
$dnsNameAttributes = @($dnsCommand.Parameters['Name'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
Assert-True ($dnsNameAttributes.Count -eq 1 -and $dnsNameAttributes[0].ParameterSetName -eq 'List') 'DNS list-only parameter applicability drifted.'
$newRecordAttributes = @($newCommand.Parameters['Record'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
Assert-True ($newRecordAttributes.Count -eq 1 -and $newRecordAttributes[0].Mandatory) 'DNS create body requiredness drifted.'
$removeIdAttributes = @($removeCommand.Parameters['DnsRecordId'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
Assert-True ($removeIdAttributes.Count -eq 1 -and $removeIdAttributes[0].Mandatory) 'DNS delete id requiredness drifted.'
$projection = Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'artifacts/p3.2/CmdletModel.json') | ConvertFrom-Json
$runtimeOperationsByType = @{
    CfDnsRecordRuntimeMetadata = @([Cloudflare.PowerShell.CfDnsRecordRuntimeMetadata]::Operations)
    CfZoneRuntimeMetadata = @([Cloudflare.PowerShell.CfZoneRuntimeMetadata]::Operations)
}
foreach ($runtimeMetadataType in @($runtimeOperationsByType.Keys | Sort-Object)) {
    $runtimeOperations = @($runtimeOperationsByType[$runtimeMetadataType])
    $expectedRuntimeOperations = @($projection.cmdlets | Where-Object runtimeMetadataType -eq $runtimeMetadataType | ForEach-Object operations)
    Assert-True ($runtimeOperations.Count -eq $expectedRuntimeOperations.Count) "$runtimeMetadataType operation count drifted."
    foreach ($expectedOperation in $expectedRuntimeOperations) {
        $actualOperation = @($runtimeOperations | Where-Object { [string]$_.OperationId -eq [string]$expectedOperation.operationId })
        Assert-True ($actualOperation.Count -eq 1) "$runtimeMetadataType is missing '$($expectedOperation.operationId)'."
        Assert-RuntimeOperationParity $expectedOperation $actualOperation[0]
    }
}
$dnsRuntimeOperations = @($runtimeOperationsByType['CfDnsRecordRuntimeMetadata'])
$dnsListRuntime = @($dnsRuntimeOperations | Where-Object { [string]$_.OperationId -eq 'dns-records-for-a-zone-list-dns-records' })
Assert-True ($dnsListRuntime.Count -eq 1) 'DNS list runtime metadata operation is not unique.'
$dnsListResponse = @($dnsListRuntime[0].ResponseRepresentations)[0]
Assert-True ([string]$dnsListResponse.EnvelopePolicy -eq 'CloudflareResult' -and [string]$dnsListResponse.ParsingMode -eq 'Json') 'DNS list response envelope/parsing is not independently verified.'
Assert-True ([string]$dnsListRuntime[0].Pagination.StopRule -eq 'empty result page') 'DNS list pagination stop rule is not independently verified.'
$zoneRuntimeOperations = @($runtimeOperationsByType['CfZoneRuntimeMetadata'])
$zoneGetRuntime = @($zoneRuntimeOperations | Where-Object { [string]$_.OperationId -eq 'zones-0-get' })
$zoneListRuntime = @($zoneRuntimeOperations | Where-Object { [string]$_.OperationId -eq 'zones-get' })
Assert-True ($zoneGetRuntime.Count -eq 1 -and $zoneListRuntime.Count -eq 1) 'Zone runtime metadata operations are not unique.'
$zoneGetResponse = @($zoneGetRuntime[0].ResponseRepresentations)[0]
$zoneListResponse = @($zoneListRuntime[0].ResponseRepresentations)[0]
Assert-True ([string]$zoneGetResponse.EnvelopePolicy -eq 'CloudflareResult' -and [string]$zoneGetResponse.ParsingMode -eq 'Json') 'Zone get response envelope/parsing is not independently verified.'
Assert-True ([string]$zoneListResponse.EnvelopePolicy -eq 'CloudflareResult' -and [string]$zoneListResponse.ParsingMode -eq 'Json') 'Zone list response envelope/parsing is not independently verified.'
Assert-True ([string]$zoneGetRuntime[0].Pagination.StopRule -eq 'single response' -and [string]$zoneListRuntime[0].Pagination.StopRule -eq 'empty result page') 'Zone pagination stop rules are not independently verified.'
Write-Output 'PASS full DNS and zone runtime metadata parity'
foreach ($model in $projection.cmdlets) {
    $command = Get-GeneratedCommand $model.cmdletName
    $actualSets = @($command.ParameterSets.Name | Where-Object { $_ -ne '__AllParameterSets' } | Sort-Object -Unique)
    $expectedSets = @($model.parameterSets | ForEach-Object name | Sort-Object -Unique)
    Assert-True (($actualSets -join '|') -eq ($expectedSets -join '|')) "$($model.cmdletName) parameter-set projection drifted."
    foreach ($parameterName in @($model.parameters | ForEach-Object name)) {
        Assert-True $command.Parameters.ContainsKey([string]$parameterName) "$($model.cmdletName) is missing projected parameter '$parameterName'."
    }
}
Write-Output 'PASS generated cmdlet metadata'

$baseArgs = @{ BaseUrl = 'https://mock.test/client/v4/'; Token = 'token'; Handler = [P32MockHandler]::new() }
$generatedSource = Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Cmdlets/P32RepresentativeCmdlets.cs')
$zoneModel = @($projection.cmdlets | Where-Object cmdletName -eq 'Get-CfZone')[0]
$dnsModel = @($projection.cmdlets | Where-Object cmdletName -eq 'Get-CfDnsRecord')[0]
foreach ($expectedDefault in @(
        @{ Name = 'Match'; Value = '"all"'; Type = 'string\?' },
        @{ Name = 'Page'; Value = '1m'; Type = 'decimal' },
        @{ Name = 'PerPage'; Value = '20m'; Type = 'decimal' })) {
    $pattern = "public $($expectedDefault.Type) $($expectedDefault.Name) \{ get; set; \} = $($expectedDefault.Value);"
    Assert-True ($generatedSource -match $pattern) "Get-CfZone generated default initialization drifted for '$($expectedDefault.Name)'."
    $modelParameter = @($zoneModel.parameters | Where-Object name -eq $expectedDefault.Name)[0]
    Assert-True ([string]$modelParameter.defaultValue -eq ($expectedDefault.Value.Trim('"','m'))) "Get-CfZone canonical default drifted for '$($expectedDefault.Name)'."
}
foreach ($parameterName in @('Direction','Match','Order','Page','PerPage','TagMatch','IncludeShadowMetadata','Proxied')) {
    $modelParameter = @($dnsModel.parameters | Where-Object name -eq $parameterName)[0]
    Assert-True ($null -ne $modelParameter -and $null -ne $modelParameter.defaultValue) "Get-CfDnsRecord canonical default is missing for '$parameterName'."
    $defaultLiteral = if ([string]$modelParameter.type -in @('bool','bool?')) { 'false' } elseif ([string]$modelParameter.type -eq 'decimal') { "$($modelParameter.defaultValue)m" } else { '"' + [string]$modelParameter.defaultValue + '"' }
    $pattern = "public $([regex]::Escape([string]$modelParameter.type)) $parameterName \{ get; set; \} = $defaultLiteral;"
    Assert-True ($generatedSource -match $pattern) "Get-CfDnsRecord generated default initialization drifted for '$parameterName'."
}
[P32MockHandler]::Reset()
$zoneDefaultArgs = @{} + $baseArgs
$zoneDefaultArgs['Match'] = 'all'
$zoneDefaultArgs['Page'] = 1
$zoneDefaultArgs['PerPage'] = 20
$null = @(& $zoneCommand @zoneDefaultArgs)
$zoneDefaultQuery = [string][P32MockHandler]::Requests[0].RequestUri.Query
foreach ($expectedQuery in @('match=all','page=1','per_page=20')) { Assert-True ($zoneDefaultQuery -match [regex]::Escape($expectedQuery)) "Get-CfZone default query is missing '$expectedQuery'." }
[P32MockHandler]::Reset()
$dnsDefaultArgs = @{} + $baseArgs
$dnsDefaultArgs['ZoneId'] = 'zone'
$dnsDefaultArgs['Direction'] = 'asc'
$dnsDefaultArgs['Match'] = 'all'
$dnsDefaultArgs['Order'] = 'type'
$dnsDefaultArgs['Page'] = 1
$dnsDefaultArgs['PerPage'] = 100
$dnsDefaultArgs['TagMatch'] = 'all'
$null = @(& $dnsCommand @dnsDefaultArgs)
$dnsDefaultQuery = [string][P32MockHandler]::Requests[0].RequestUri.Query
foreach ($expectedQuery in @('direction=asc','match=all','order=type','page=1','per_page=100','tag_match=all')) { Assert-True ($dnsDefaultQuery -match [regex]::Escape($expectedQuery)) "Get-CfDnsRecord default query is missing '$expectedQuery'." }
Assert-True ($dnsDefaultQuery -notmatch 'include_shadow_metadata=' -and $dnsDefaultQuery -notmatch 'proxied=') 'Get-CfDnsRecord omitted boolean defaults were not preserved as omitted wire values.'
Write-Output 'PASS generated source and canonical-default query binding behavior'

[P32MockHandler]::Reset()
$zones = @(& $zoneCommand @baseArgs -AccountId account -AccountName acct -Direction asc -Match all -Name example.com -Order name -PerPage 1 -Status active -Type full)
Assert-True ($zones.Count -eq 1 -and $zones[0] -is [Cloudflare.PowerShell.CfZone]) 'Generated Get-CfZone list did not emit typed items.'
Assert-True ([P32MockHandler]::Requests.Count -eq 2) 'Generated Get-CfZone list did not use shared pagination.'
Assert-True ([P32MockHandler]::Requests[0].RequestUri.Query -match 'page=1') 'Generated Get-CfZone page 1 was not requested.'
Assert-True ([P32MockHandler]::Requests[0].Headers.Authorization.ToString() -eq 'Bearer token') 'Generated Get-CfZone did not apply the authentication header.'
Assert-True ([P32MockHandler]::Requests[0].RequestUri.Query -match 'account.id=account' -and [P32MockHandler]::Requests[0].RequestUri.Query -match 'per_page=1') 'Generated Get-CfZone query bindings are incomplete.'
Write-Output 'PASS generated zone list dispatch and paging'

[P32MockHandler]::Reset()
$zoneInput = [pscustomobject]@{ ZoneId = 'zone' }
$zone = @($zoneInput | & $zoneCommand @baseArgs)
Assert-True ($zone.Count -eq 1 -and $zone[0].Id -eq 'zone') 'Get-CfZone pipeline-by-property-name did not dispatch.'
Write-Output 'PASS generated zone get pipeline binding'

[P32MockHandler]::Reset()
$records = @(([pscustomobject]@{ ZoneId = 'zone' }) | & $dnsCommand @baseArgs)
Assert-True ($records.Count -eq 1 -and $records[0] -is [Cloudflare.PowerShell.CfDnsRecord]) 'Generated Get-CfDnsRecord list did not emit typed items.'
Assert-True ([P32MockHandler]::Requests.Count -eq 2) 'Generated Get-CfDnsRecord list did not use shared pagination.'

[P32MockHandler]::Reset()
$record = & $dnsCommand -ZoneId zone -DnsRecordId record @baseArgs
Assert-True ($record.Id -eq 'record') 'Generated Get-CfDnsRecord get did not dispatch.'
Write-Output 'PASS generated DNS list/get dispatch'

[P32MockHandler]::Reset()
$chainedRecords = @($zones | & $dnsCommand @baseArgs)
Assert-True ($chainedRecords.Count -eq 1 -and $chainedRecords[0].Id -eq 'r1') 'CfZone ETS identity did not support zone-to-DNS pipeline binding.'
Write-Output 'PASS CfZone ETS identity zone-to-DNS pipeline binding'

[P32MockHandler]::Reset()
$recordFromPipeline = @($record | & $dnsCommand -ZoneId zone @baseArgs)
Assert-True ($recordFromPipeline.Count -eq 1 -and [P32MockHandler]::Requests[0].RequestUri.AbsolutePath -like '*/dns_records/record') 'CfDnsRecord ETS identity did not bind DnsRecordId with explicit ZoneId.'
Write-Output 'PASS CfDnsRecord ETS identity get with explicit parent scope'

[P32MockHandler]::Reset()
$pipedRemove = @($record | & $removeCommand -ZoneId zone @baseArgs -WhatIf)
Assert-True ($pipedRemove.Count -eq 0 -and [P32MockHandler]::Requests.Count -eq 0) 'CfDnsRecord pipeline Remove with explicit ZoneId was not a no-request WhatIf.'

[P32MockHandler]::Reset()
$pipedSet = @($record | & $setCommand -ZoneId zone -Edit @{ content = '198.51.100.6' } @baseArgs -WhatIf)
Assert-True ($pipedSet.Count -eq 0 -and [P32MockHandler]::Requests.Count -eq 0) 'CfDnsRecord pipeline Set with explicit ZoneId was not a no-request WhatIf.'
Write-Output 'PASS CfDnsRecord ETS identity mutation workflows with explicit parent scope'

[P32MockHandler]::Reset()
$missingScopeFailed = $false
try { @($record | & $removeCommand @baseArgs -WhatIf -ErrorAction Stop) | Out-Null } catch { $missingScopeFailed = $true }
Assert-True ($missingScopeFailed -and [P32MockHandler]::Requests.Count -eq 0) 'CfDnsRecord pipeline Remove without ZoneId did not fail clearly before dispatch.'
Write-Output 'PASS CfDnsRecord pipeline missing parent scope remains explicit'

[P32MockHandler]::Reset()
$record = & $dnsCommand -ZoneId zone -RecordId record @baseArgs
Assert-True ($record.Id -eq 'record' -and [P32MockHandler]::Requests[0].RequestUri.AbsolutePath -like '*/dns_records/record') 'Generated Get-CfDnsRecord did not bind the RecordId alias.'
[P32MockHandler]::Reset()
$records = @(& $dnsCommand -ZoneId zone -TagAbsent missing @baseArgs)
Assert-True ($records.Count -eq 1 -and [P32MockHandler]::Requests[0].RequestUri.Query -match 'tag.absent=missing') 'Generated Get-CfDnsRecord did not bind TagAbsent.'
Write-Output 'PASS generated DNS TagAbsent and RecordId alias binding'

[P32MockHandler]::Reset()
$input = [Cloudflare.PowerShell.CfARecordInput]::new()
$input.Content = [Cloudflare.PowerShell.Optional[string]]::ExplicitNull
$created = & $newCommand -ZoneId zone -Record $input @baseArgs -Confirm:$false
Assert-True ($created.Id -eq 'created') 'Generated New-CfDnsRecord did not emit typed output.'
Assert-True ([P32MockHandler]::Bodies[0] -match '"content":null') 'Generated New-CfDnsRecord lost explicit-null presence.'
Assert-True ([P32MockHandler]::Bodies[0] -notmatch '"name"') 'Generated New-CfDnsRecord did not preserve omitted presence.'
Write-Output 'PASS generated create typed input and presence'

[P32MockHandler]::Reset()
$nullResult = & $newCommand -ZoneId zone -Record $input @baseArgs -WhatIf
Assert-True ([P32MockHandler]::Requests.Count -eq 0) 'Generated New-CfDnsRecord WhatIf sent an HTTP request.'
Write-Output 'PASS generated ShouldProcess WhatIf'

[P32MockHandler]::Reset()
$removeOutput = @(& $removeCommand -ZoneId zone -DnsRecordId record @baseArgs -Confirm:$false)
Assert-True ([P32MockHandler]::Requests.Count -eq 1) 'Generated Remove-CfDnsRecord did not send exactly one request.'
Assert-True ([P32MockHandler]::Requests[0].Method -eq [System.Net.Http.HttpMethod]::Delete) 'Generated Remove-CfDnsRecord did not send DELETE.'
Assert-True ([P32MockHandler]::Bodies[0] -eq '') 'Generated Remove-CfDnsRecord sent a DELETE body.'
Assert-True ($removeOutput.Count -eq 0) 'Generated Remove-CfDnsRecord emitted an object despite outputPolicy none.'
Write-Output 'PASS generated DELETE and ShouldProcess'

[P32MockHandler]::Reset()
& $removeCommand -ZoneId zone -DnsRecordId record @baseArgs -WhatIf
Assert-True ([P32MockHandler]::Requests.Count -eq 0) 'Generated Remove-CfDnsRecord WhatIf sent an HTTP request.'
Write-Output 'PASS generated DELETE WhatIf'

[P32MockHandler]::Reset()
try {
    & $dnsCommand -ZoneId zone -Name fail @baseArgs -ErrorAction Stop | Out-Null
    throw 'Expected generated PowerShell ErrorRecord.'
}
catch {
    Assert-True ($_.Exception.FullyQualifiedErrorId -eq 'Cloudflare.Api.400') 'Generated error ID differs from handwritten baseline.'
    Assert-True ($_.CategoryInfo.Category -eq 'InvalidArgument') 'Generated error category differs from handwritten baseline.'
    Assert-True ($_.TargetObject -eq 'zone') 'Generated error target differs from handwritten baseline.'
    Assert-True ($_.Exception.RequestId -eq 'p32-ray-1') 'Generated error did not retain request ID.'
    Assert-True ($_.Exception.Errors[0].Code -eq 1001) 'Generated error did not retain Cloudflare error code.'
}
Write-Output 'PASS generated error parity'

[P32MockHandler]::Reset()
$handwritten = @(& (Get-Module Cloudflare.PowerShell) { param($bound) Invoke-CfDnsRecordHandwritten @bound } @{ ZoneId = 'zone'; Name = 'example.com'; BaseUrl = $baseArgs.BaseUrl; Token = $baseArgs.Token; Handler = $baseArgs.Handler })
$handwrittenRequest = [P32MockHandler]::Requests[0]
$handwrittenBody = [P32MockHandler]::Bodies[0]
[P32MockHandler]::Reset()
$generated = @(& $dnsCommand -ZoneId zone -Name example.com @baseArgs)
$generatedRequest = [P32MockHandler]::Requests[0]
$generatedBody = [P32MockHandler]::Bodies[0]
Assert-True ($handwritten.Count -eq $generated.Count -and $handwritten[0].Id -eq $generated[0].Id) 'Handwritten/generated output parity failed.'
Assert-True ($handwrittenRequest.Method -eq $generatedRequest.Method -and $handwrittenRequest.RequestUri.AbsolutePath -eq $generatedRequest.RequestUri.AbsolutePath -and $handwrittenRequest.RequestUri.Query -eq $generatedRequest.RequestUri.Query -and $handwrittenBody -eq $generatedBody) 'Handwritten/generated HTTP parity failed.'
Write-Output 'PASS handwritten/generated behavioral parity'

$zoneListParityArgs = @{
    BaseUrl = $baseArgs.BaseUrl
    Token = $baseArgs.Token
    Handler = $baseArgs.Handler
    AccountId = 'account'
    AccountName = 'acct'
    Direction = 'asc'
    Match = 'all'
    Name = 'example.com'
    Order = 'name'
    PerPage = 1
    Status = 'active'
    Type = @('full', 'partial')
}
[P32MockHandler]::Reset()
$handwritten = @(Invoke-HandwrittenZone $zoneListParityArgs)
$handwrittenFacts = @(for ($i = 0; $i -lt [P32MockHandler]::Requests.Count; $i++) { Get-RequestFacts ([P32MockHandler]::Requests[$i]) ([P32MockHandler]::Bodies[$i]) })
$handwrittenZoneOutput = $handwritten | ForEach-Object { "$($_.Id)|$($_.Name)|$($_.Status)|$($_.Type)|$($_.GetType().FullName)" }
[P32MockHandler]::Reset()
$generated = @(& $zoneCommand @zoneListParityArgs)
$generatedFacts = @(for ($i = 0; $i -lt [P32MockHandler]::Requests.Count; $i++) { Get-RequestFacts ([P32MockHandler]::Requests[$i]) ([P32MockHandler]::Bodies[$i]) })
$generatedZoneOutput = $generated | ForEach-Object { "$($_.Id)|$($_.Name)|$($_.Status)|$($_.Type)|$($_.GetType().FullName)" }
Assert-True (($handwrittenZoneOutput -join ';') -eq ($generatedZoneOutput -join ';')) 'Get-CfZone handwritten/generated output parity failed.'
Assert-True ($handwrittenFacts.Count -eq $generatedFacts.Count) 'Get-CfZone handwritten/generated request count parity failed.'
for ($i = 0; $i -lt $generatedFacts.Count; $i++) { Assert-RequestFactsEqual $handwrittenFacts[$i] $generatedFacts[$i] "Get-CfZone request $($i + 1)" }
Write-Output 'PASS Get-CfZone handwritten/generated method/path/query/headers/output parity'

$dnsListParityArgs = @{
    ZoneId = 'zone'
    Name = 'example.com'
    Type = 'A'
    Tag = @('one', 'two')
    PerPage = 1
    IncludeShadowMetadata = $true
    BaseUrl = $baseArgs.BaseUrl
    Token = $baseArgs.Token
    Handler = $baseArgs.Handler
}
[P32MockHandler]::Reset()
$handwritten = @(& (Get-Module Cloudflare.PowerShell) { param($bound) Invoke-CfDnsRecordHandwritten @bound } $dnsListParityArgs)
$handwrittenFacts = @(for ($i = 0; $i -lt [P32MockHandler]::Requests.Count; $i++) { Get-RequestFacts ([P32MockHandler]::Requests[$i]) ([P32MockHandler]::Bodies[$i]) })
$handwrittenOutput = $handwritten | ForEach-Object { "$($_.Id)|$($_.Name)|$($_.Type)|$($_.Content)|$($_.GetType().FullName)" }
[P32MockHandler]::Reset()
$generated = @(& $dnsCommand @dnsListParityArgs)
$generatedFacts = @(for ($i = 0; $i -lt [P32MockHandler]::Requests.Count; $i++) { Get-RequestFacts ([P32MockHandler]::Requests[$i]) ([P32MockHandler]::Bodies[$i]) })
$generatedOutput = $generated | ForEach-Object { "$($_.Id)|$($_.Name)|$($_.Type)|$($_.Content)|$($_.GetType().FullName)" }
Assert-True (($handwrittenOutput -join ';') -eq ($generatedOutput -join ';')) 'Get-CfDnsRecord list output parity failed.'
Assert-True ($handwrittenFacts.Count -eq $generatedFacts.Count) 'Get-CfDnsRecord list request count parity failed.'
for ($i = 0; $i -lt $generatedFacts.Count; $i++) { Assert-RequestFactsEqual $handwrittenFacts[$i] $generatedFacts[$i] "Get-CfDnsRecord list request $($i + 1)" }
Write-Output 'PASS Get-CfDnsRecord list handwritten/generated parity including paging'

$dnsGetParityArgs = @{
    ZoneId = 'zone'
    RecordId = 'record'
    IncludeShadowMetadata = $true
    BaseUrl = $baseArgs.BaseUrl
    Token = $baseArgs.Token
    Handler = $baseArgs.Handler
}
$dnsGeneratedGetArgs = @{
    ZoneId = 'zone'
    DnsRecordId = 'record'
    IncludeShadowMetadata = $true
    BaseUrl = $baseArgs.BaseUrl
    Token = $baseArgs.Token
    Handler = $baseArgs.Handler
}
[P32MockHandler]::Reset()
$handwritten = @(& (Get-Module Cloudflare.PowerShell) { param($bound) Invoke-CfDnsRecordHandwritten @bound } $dnsGetParityArgs)
$handwrittenFacts = @(Get-RequestFacts ([P32MockHandler]::Requests[0]) ([P32MockHandler]::Bodies[0]))
$handwrittenOutput = "$($handwritten[0].Id)|$($handwritten[0].Name)|$($handwritten[0].Type)|$($handwritten[0].GetType().FullName)"
[P32MockHandler]::Reset()
$generated = @(& $dnsCommand @dnsGeneratedGetArgs)
$generatedFacts = @(Get-RequestFacts ([P32MockHandler]::Requests[0]) ([P32MockHandler]::Bodies[0]))
$generatedOutput = "$($generated[0].Id)|$($generated[0].Name)|$($generated[0].Type)|$($generated[0].GetType().FullName)"
Assert-True ($handwrittenOutput -eq $generatedOutput) 'Get-CfDnsRecord get output parity failed.'
Assert-RequestFactsEqual $handwrittenFacts[0] $generatedFacts[0] 'Get-CfDnsRecord get'
Write-Output 'PASS Get-CfDnsRecord get handwritten/generated method/path/query/headers/output parity'

$parityInput = [Cloudflare.PowerShell.CfARecordInput]::new()
$parityInput.Name = [Cloudflare.PowerShell.Optional[string]]::From('example.com')
$parityInput.Content = [Cloudflare.PowerShell.Optional[string]]::ExplicitNull
$newParityArgs = @{
    ZoneId = 'zone'
    Record = $parityInput
    BaseUrl = $baseArgs.BaseUrl
    Token = $baseArgs.Token
    Handler = $baseArgs.Handler
    Confirm = $false
}
[P32MockHandler]::Reset()
$handwritten = @(& (Get-Module Cloudflare.PowerShell) { param($bound) Invoke-NewCfDnsRecordHandwritten @bound } $newParityArgs)
$handwrittenFacts = @(Get-RequestFacts ([P32MockHandler]::Requests[0]) ([P32MockHandler]::Bodies[0]))
$handwrittenOutput = "$($handwritten[0].Id)|$($handwritten[0].Type)|$($handwritten[0].GetType().FullName)"
[P32MockHandler]::Reset()
$generated = @(& $newCommand @newParityArgs)
$generatedFacts = @(Get-RequestFacts ([P32MockHandler]::Requests[0]) ([P32MockHandler]::Bodies[0]))
$generatedOutput = "$($generated[0].Id)|$($generated[0].Type)|$($generated[0].GetType().FullName)"
Assert-True ($handwrittenOutput -eq $generatedOutput) 'New-CfDnsRecord output parity failed.'
Assert-RequestFactsEqual $handwrittenFacts[0] $generatedFacts[0] 'New-CfDnsRecord omitted query/body'
Assert-True ($generatedFacts[0].Body -match '"content":null' -and $generatedFacts[0].Body -match '"name":"example.com"') 'New-CfDnsRecord presence semantics were not retained.'
Write-Output 'PASS New-CfDnsRecord handwritten/generated method/path/query/headers/body/output parity'

$newExplicitFalseArgs = @{} + $newParityArgs
$newExplicitFalseArgs['IncludeShadowMetadata'] = $false
[P32MockHandler]::Reset()
$null = @(& (Get-Module Cloudflare.PowerShell) { param($bound) Invoke-NewCfDnsRecordHandwritten @bound } $newExplicitFalseArgs)
$handwrittenFacts = @(Get-RequestFacts ([P32MockHandler]::Requests[0]) ([P32MockHandler]::Bodies[0]))
[P32MockHandler]::Reset()
$null = @(& $newCommand @newExplicitFalseArgs)
$generatedFacts = @(Get-RequestFacts ([P32MockHandler]::Requests[0]) ([P32MockHandler]::Bodies[0]))
Assert-RequestFactsEqual $handwrittenFacts[0] $generatedFacts[0] 'New-CfDnsRecord explicit false'
Assert-True ($generatedFacts[0].Query -match 'include_shadow_metadata=False') 'New-CfDnsRecord explicit false was omitted.'
Write-Output 'PASS New-CfDnsRecord omitted versus explicit-false query parity'

$newWhatIfArgs = @{} + $newParityArgs
$newWhatIfArgs['WhatIf'] = $true
[P32MockHandler]::Reset()
$null = @(& (Get-Module Cloudflare.PowerShell) { param($bound) Invoke-NewCfDnsRecordHandwritten @bound } $newWhatIfArgs)
Assert-True ([P32MockHandler]::Requests.Count -eq 0) 'Handwritten New-CfDnsRecord WhatIf sent an HTTP request.'
[P32MockHandler]::Reset()
$null = @(& $newCommand @newWhatIfArgs)
Assert-True ([P32MockHandler]::Requests.Count -eq 0) 'Generated New-CfDnsRecord WhatIf sent an HTTP request.'
Write-Output 'PASS handwritten/generated New-CfDnsRecord ShouldProcess no-request WhatIf parity'

$removeParityArgs = @{
    ZoneId = 'zone'
    RecordId = 'record'
    BaseUrl = $baseArgs.BaseUrl
    Token = $baseArgs.Token
    Handler = $baseArgs.Handler
    Confirm = $false
}
$removeGeneratedArgs = @{
    ZoneId = 'zone'
    DnsRecordId = 'record'
    BaseUrl = $baseArgs.BaseUrl
    Token = $baseArgs.Token
    Handler = $baseArgs.Handler
    Confirm = $false
}

[P32MockHandler]::Reset()
$null = @(& $removeCommand @removeParityArgs)
Assert-True ([P32MockHandler]::Requests.Count -eq 1 -and [P32MockHandler]::Requests[0].RequestUri.AbsolutePath -like '*/dns_records/record') 'Generated Remove-CfDnsRecord did not bind the RecordId alias.'
Write-Output 'PASS generated Remove-CfDnsRecord RecordId alias binding'

[P32MockHandler]::Reset()
$handwritten = @(& (Get-Module Cloudflare.PowerShell) { param($bound) Invoke-RemoveCfDnsRecordHandwritten @bound } $removeParityArgs)
$handwrittenFacts = @(Get-RequestFacts ([P32MockHandler]::Requests[0]) ([P32MockHandler]::Bodies[0]))
[P32MockHandler]::Reset()
$generated = @(& $removeCommand @removeGeneratedArgs)
$generatedFacts = @(Get-RequestFacts ([P32MockHandler]::Requests[0]) ([P32MockHandler]::Bodies[0]))
Assert-True ($handwritten.Count -eq 0 -and $generated.Count -eq 0) 'Remove-CfDnsRecord output parity failed.'
Assert-RequestFactsEqual $handwrittenFacts[0] $generatedFacts[0] 'Remove-CfDnsRecord'
Assert-True ($generatedFacts[0].Method -eq 'DELETE' -and [string]::IsNullOrEmpty($generatedFacts[0].Body)) 'Remove-CfDnsRecord DELETE/body behavior drifted.'
Write-Output 'PASS Remove-CfDnsRecord handwritten/generated method/path/query/headers/body/output parity'

$setBody = [ordered]@{ content = '198.51.100.8'; name = 'example.com'; type = 'A' }
$setReplaceArgs = @{
    ZoneId = 'zone'
    RecordId = 'record'
    Replace = $setBody
    BaseUrl = $baseArgs.BaseUrl
    Token = $baseArgs.Token
    Handler = $baseArgs.Handler
    Confirm = $false
}
$setGeneratedReplaceArgs = @{
    ZoneId = 'zone'
    DnsRecordId = 'record'
    Replace = $setBody
    BaseUrl = $baseArgs.BaseUrl
    Token = $baseArgs.Token
    Handler = $baseArgs.Handler
    Confirm = $false
}
[P32MockHandler]::Reset()
$handwritten = @(& (Get-Module Cloudflare.PowerShell) { param($bound) Invoke-SetCfDnsRecordHandwritten @bound } $setReplaceArgs)
$handwrittenFacts = @(Get-RequestFacts ([P32MockHandler]::Requests[0]) ([P32MockHandler]::Bodies[0]))
$handwrittenOutput = "$($handwritten[0].Id)|$($handwritten[0].Type)|$($handwritten[0].GetType().FullName)"
[P32MockHandler]::Reset()
$generated = @(& $setCommand @setGeneratedReplaceArgs)
$generatedFacts = @(Get-RequestFacts ([P32MockHandler]::Requests[0]) ([P32MockHandler]::Bodies[0]))
$generatedOutput = "$($generated[0].Id)|$($generated[0].Type)|$($generated[0].GetType().FullName)"
Assert-True ($handwrittenOutput -eq $generatedOutput) 'Set-CfDnsRecord Replace output parity failed.'
Assert-RequestFactsEqual $handwrittenFacts[0] $generatedFacts[0] 'Set-CfDnsRecord Replace'
Assert-True ($generatedFacts[0].Method -eq 'PUT' -and $generatedFacts[0].Body -match '"content":"198.51.100.8"') 'Set-CfDnsRecord Replace did not use PUT/body.'

$setEditBody = [ordered]@{ content = '198.51.100.9' }
$setEditArgs = @{} + $setReplaceArgs
$setEditArgs.Remove('Replace')
$setEditArgs['Edit'] = $setEditBody
$setGeneratedEditArgs = @{} + $setGeneratedReplaceArgs
$setGeneratedEditArgs.Remove('Replace')
$setGeneratedEditArgs['Edit'] = $setEditBody
[P32MockHandler]::Reset()
$handwritten = @(& (Get-Module Cloudflare.PowerShell) { param($bound) Invoke-SetCfDnsRecordHandwritten @bound } $setEditArgs)
$handwrittenFacts = @(Get-RequestFacts ([P32MockHandler]::Requests[0]) ([P32MockHandler]::Bodies[0]))
$handwrittenOutput = "$($handwritten[0].Id)|$($handwritten[0].Type)|$($handwritten[0].GetType().FullName)"
[P32MockHandler]::Reset()
$generated = @(& $setCommand @setGeneratedEditArgs)
$generatedFacts = @(Get-RequestFacts ([P32MockHandler]::Requests[0]) ([P32MockHandler]::Bodies[0]))
$generatedOutput = "$($generated[0].Id)|$($generated[0].Type)|$($generated[0].GetType().FullName)"
Assert-True ($handwrittenOutput -eq $generatedOutput) 'Set-CfDnsRecord Edit output parity failed.'
Assert-RequestFactsEqual $handwrittenFacts[0] $generatedFacts[0] 'Set-CfDnsRecord Edit'
Assert-True ($generatedFacts[0].Method -eq 'PATCH' -and $generatedFacts[0].Body -match '"content":"198.51.100.9"') 'Set-CfDnsRecord Edit did not use PATCH/body.'
Write-Output 'PASS Set-CfDnsRecord handwritten/generated PUT/PATCH method/path/query/headers/body/output parity'

[P32MockHandler]::Reset()
$null = @(& $setCommand @setReplaceArgs)
Assert-True ([P32MockHandler]::Requests.Count -eq 1 -and [P32MockHandler]::Requests[0].RequestUri.AbsolutePath -like '*/dns_records/record' -and [P32MockHandler]::Requests[0].Method -eq [System.Net.Http.HttpMethod]::Put) 'Generated Set-CfDnsRecord did not bind the RecordId alias.'
Write-Output 'PASS generated Set-CfDnsRecord RecordId alias binding'

$setIncludeArgs = @{} + $setGeneratedReplaceArgs
$setIncludeArgs['IncludeShadowMetadata'] = $true
[P32MockHandler]::Reset()
$null = @(& $setCommand @setIncludeArgs)
$setIncludeFacts = @(Get-RequestFacts ([P32MockHandler]::Requests[0]) ([P32MockHandler]::Bodies[0]))
Assert-True ($setIncludeFacts.Count -eq 1 -and $setIncludeFacts[0].Query -match 'include_shadow_metadata=True') 'Generated Set-CfDnsRecord IncludeShadowMetadata was omitted from the query.'
Write-Output 'PASS generated Set-CfDnsRecord IncludeShadowMetadata query binding'

$setWhatIfArgs = @{} + $setReplaceArgs
$setWhatIfArgs['WhatIf'] = $true
[P32MockHandler]::Reset()
$null = @(& (Get-Module Cloudflare.PowerShell) { param($bound) Invoke-SetCfDnsRecordHandwritten @bound } $setWhatIfArgs)
Assert-True ([P32MockHandler]::Requests.Count -eq 0) 'Handwritten Set-CfDnsRecord WhatIf sent an HTTP request.'
$setGeneratedWhatIfArgs = @{} + $setGeneratedReplaceArgs
$setGeneratedWhatIfArgs['WhatIf'] = $true
[P32MockHandler]::Reset()
$null = @(& $setCommand @setGeneratedWhatIfArgs)
Assert-True ([P32MockHandler]::Requests.Count -eq 0) 'Generated Set-CfDnsRecord WhatIf sent an HTTP request.'
Write-Output 'PASS handwritten/generated Set-CfDnsRecord ShouldProcess no-request WhatIf parity'

$removeWhatIfArgs = @{} + $removeParityArgs
$removeWhatIfArgs['WhatIf'] = $true
[P32MockHandler]::Reset()
$null = @(& (Get-Module Cloudflare.PowerShell) { param($bound) Invoke-RemoveCfDnsRecordHandwritten @bound } $removeWhatIfArgs)
Assert-True ([P32MockHandler]::Requests.Count -eq 0) 'Handwritten Remove-CfDnsRecord WhatIf sent an HTTP request.'
$removeGeneratedWhatIfArgs = @{} + $removeGeneratedArgs
$removeGeneratedWhatIfArgs['WhatIf'] = $true
[P32MockHandler]::Reset()
$null = @(& $removeCommand @removeGeneratedWhatIfArgs)
Assert-True ([P32MockHandler]::Requests.Count -eq 0) 'Generated Remove-CfDnsRecord WhatIf sent an HTTP request.'
Write-Output 'PASS handwritten/generated Remove-CfDnsRecord ShouldProcess no-request WhatIf parity'

function Assert-ErrorParity {
    param([Parameter(Mandatory)][scriptblock]$Handwritten, [Parameter(Mandatory)][scriptblock]$Generated, [Parameter(Mandatory)][string]$Label)
    [P32MockHandler]::Reset()
    [P32MockHandler]::FailMode = 'bad'
    $handwrittenFacts = Get-ErrorFacts $Handwritten
    [P32MockHandler]::Reset()
    [P32MockHandler]::FailMode = 'bad'
    $generatedFacts = Get-ErrorFacts $Generated
    $expectedJson = $handwrittenFacts | ConvertTo-Json -Compress -Depth 10
    $actualJson = $generatedFacts | ConvertTo-Json -Compress -Depth 10
    Assert-True ($expectedJson -eq $actualJson) "$Label ErrorRecord parity failed. Expected $expectedJson, actual $actualJson."
    Write-Output "PASS $Label ErrorRecord parity"
}

$zoneGetArgs = @{
    ZoneId = 'zone'
    BaseUrl = $baseArgs.BaseUrl
    Token = $baseArgs.Token
    Handler = $baseArgs.Handler
}
$zoneErrorArgs = @{} + $zoneGetArgs
$zoneErrorArgs['ErrorAction'] = 'Stop'
$dnsHandwrittenErrorArgs = @{} + $dnsGetParityArgs
$dnsHandwrittenErrorArgs['ErrorAction'] = 'Stop'
$dnsErrorArgs = @{} + $dnsGeneratedGetArgs
$dnsErrorArgs['ErrorAction'] = 'Stop'
$newErrorArgs = @{} + $newParityArgs
$newErrorArgs['ErrorAction'] = 'Stop'
$removeHandwrittenErrorArgs = @{} + $removeParityArgs
$removeHandwrittenErrorArgs['ErrorAction'] = 'Stop'
$removeErrorArgs = @{} + $removeGeneratedArgs
$removeErrorArgs['ErrorAction'] = 'Stop'
Assert-ErrorParity {
    & (Get-Module Cloudflare.PowerShell) { param($bound) Invoke-CfZoneHandwritten @bound } $zoneErrorArgs
} {
    & $zoneCommand @zoneErrorArgs
} 'Get-CfZone'
Assert-ErrorParity {
    & (Get-Module Cloudflare.PowerShell) { param($bound) Invoke-CfDnsRecordHandwritten @bound } $dnsHandwrittenErrorArgs
} {
    & $dnsCommand @dnsErrorArgs
} 'Get-CfDnsRecord'
Assert-ErrorParity {
    & (Get-Module Cloudflare.PowerShell) { param($bound) Invoke-NewCfDnsRecordHandwritten @bound } $newErrorArgs
} {
    & $newCommand @newErrorArgs
} 'New-CfDnsRecord'
Assert-ErrorParity {
    & (Get-Module Cloudflare.PowerShell) { param($bound) Invoke-RemoveCfDnsRecordHandwritten @bound } $removeHandwrittenErrorArgs
} {
    & $removeCommand @removeErrorArgs
} 'Remove-CfDnsRecord'
$setHandwrittenErrorArgs = @{} + $setReplaceArgs
$setHandwrittenErrorArgs['ErrorAction'] = 'Stop'
$setGeneratedErrorArgs = @{} + $setGeneratedReplaceArgs
$setGeneratedErrorArgs['ErrorAction'] = 'Stop'
Assert-ErrorParity {
    & (Get-Module Cloudflare.PowerShell) { param($bound) Invoke-SetCfDnsRecordHandwritten @bound } $setHandwrittenErrorArgs
} {
    & $setCommand @setGeneratedErrorArgs
} 'Set-CfDnsRecord Replace'
$setEditHandwrittenErrorArgs = @{} + $setEditArgs
$setEditHandwrittenErrorArgs['ErrorAction'] = 'Stop'
$setEditGeneratedErrorArgs = @{} + $setGeneratedEditArgs
$setEditGeneratedErrorArgs['ErrorAction'] = 'Stop'
Assert-ErrorParity {
    & (Get-Module Cloudflare.PowerShell) { param($bound) Invoke-SetCfDnsRecordHandwritten @bound } $setEditHandwrittenErrorArgs
} {
    & $setCommand @setEditGeneratedErrorArgs
} 'Set-CfDnsRecord Edit'

[P32MockHandler]::Reset()
[P32MockHandler]::FailMode = 'retry'
$retryError = Get-ErrorFacts { & $dnsCommand @dnsErrorArgs }
Assert-True ([P32MockHandler]::Requests.Count -eq 1 -and $retryError.RetryCount -eq 0) 'Generated default retry boundary changed unexpectedly.'
[P32MockHandler]::Reset()
[P32MockHandler]::FailMode = 'retry'
$handwrittenRetryError = Get-ErrorFacts { & (Get-Module Cloudflare.PowerShell) { param($bound) Invoke-CfDnsRecordHandwritten @bound } $dnsHandwrittenErrorArgs }
Assert-True ([P32MockHandler]::Requests.Count -eq 1 -and $handwrittenRetryError.RetryCount -eq 0) 'Handwritten default retry boundary changed unexpectedly.'
Assert-True (($retryError | ConvertTo-Json -Compress -Depth 10) -eq ($handwrittenRetryError | ConvertTo-Json -Compress -Depth 10)) 'Generated/handwritten retry boundary parity failed.'
Write-Output 'PASS generated/handwritten default retry boundary parity'

[P32MockHandler]::Reset()
$bindingFailed = $false
try { & $dnsCommand -ZoneId zone -DnsRecordId record -Name invalid @baseArgs -ErrorAction Stop | Out-Null } catch { $bindingFailed = $true }
Assert-True ($bindingFailed -and [P32MockHandler]::Requests.Count -eq 0) 'Generated DNS get accepted a list-only parameter or sent a request.'
Write-Output 'PASS generated parameter applicability no-request boundary; requiredness is asserted from command metadata'

$helpNames = @('Get-CfZone', 'Get-CfDnsRecord', 'New-CfDnsRecord', 'Remove-CfDnsRecord', 'Set-CfDnsRecord')
$helpModels = @{}
foreach ($model in @($projection.cmdlets)) { $helpModels[[string]$model.cmdletName] = $model.help }
$moduleHelpPath = Join-Path $modulePath 'Cloudflare.PowerShell-help.xml'
Assert-True (Test-Path -LiteralPath $moduleHelpPath -PathType Leaf) 'Generated module help resource is missing from the current module directory.'
foreach ($evidence in @($helpNames | ForEach-Object { Get-HelpEvidence $_ })) {
    $expectedHelp = $helpModels[$evidence.Name]
    Assert-True (-not [string]::IsNullOrWhiteSpace($evidence.Synopsis) -and -not [string]::IsNullOrWhiteSpace($evidence.Description)) "Get-Help $($evidence.Name) returned empty generated help."
    Assert-True ($evidence.Synopsis -eq [string]$expectedHelp.synopsis -and $evidence.Description.StartsWith([string]$expectedHelp.description, [StringComparison]::Ordinal)) "Get-Help $($evidence.Name) drifted from canonical projection help."
    $command = Get-Command $evidence.Name -ErrorAction Stop
    $fullHelp = Get-Help $evidence.Name -Full -ErrorAction Stop
    $syntax = @(Get-Command $evidence.Name -Syntax | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $mamlParameters = @($fullHelp.parameters.parameter)
    $mamlSyntaxItems = @($fullHelp.syntax.syntaxItem)
    $mamlInputs = @($fullHelp.inputTypes.inputType)
    $mamlOutputs = @($fullHelp.returnValues.returnValue)
    $mamlExamples = @($fullHelp.examples.example)
    $mamlLinks = @($fullHelp.relatedLinks.navigationLink)
    $expectedParameters = @($expectedHelp.parameterDescriptions.PSObject.Properties | ForEach-Object Name)
    $actualParameterNames = @($mamlParameters | ForEach-Object Name)
    Assert-True ($syntax.Count -gt 0) "Get-Command -Syntax returned no syntax for '$($evidence.Name)'."
    Assert-True ($mamlSyntaxItems.Count -eq @($command.ParameterSets | Where-Object Name -ne '__AllParameterSets').Count) "Generated MAML parameter-set syntax drifted for '$($evidence.Name)'."
    Assert-True ($mamlParameters.Count -ge $expectedParameters.Count) "Generated MAML parameter help is incomplete for '$($evidence.Name)'."
    foreach ($parameterName in $expectedParameters) {
        Assert-True ($actualParameterNames -contains [string]$parameterName) "Generated MAML is missing parameter '$parameterName' for '$($evidence.Name)'."
    }
    Assert-True ($mamlInputs.Count -gt 0 -and $mamlOutputs.Count -gt 0) "Generated MAML input/output help is empty for '$($evidence.Name)'."
    Assert-True ($mamlExamples.Count -eq @($expectedHelp.examples).Count -and $mamlExamples.Count -gt 0) "Generated MAML examples drifted for '$($evidence.Name)'."
    Assert-True ($mamlLinks.Count -eq @($expectedHelp.relatedLinks).Count) "Generated MAML related links drifted for '$($evidence.Name)'."
}

$isolatedHelpRoot = Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p32-help-' + [guid]::NewGuid().ToString('N'))
try {
    $null = New-Item -ItemType Directory -Path $isolatedHelpRoot -Force
    Copy-Item -LiteralPath (Join-Path $modulePath 'Cloudflare.PowerShell.psd1') -Destination $isolatedHelpRoot -Force
    Copy-Item -LiteralPath (Join-Path $modulePath 'Cloudflare.PowerShell.psm1') -Destination $isolatedHelpRoot -Force
    Copy-Item -LiteralPath (Join-Path $modulePath 'Cloudflare.PowerShell.dll') -Destination $isolatedHelpRoot -Force
    Copy-Item -LiteralPath $moduleHelpPath -Destination (Join-Path $isolatedHelpRoot 'Cloudflare.PowerShell-help.xml') -Force
    Remove-Module -Name Cloudflare.PowerShell -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $isolatedHelpRoot 'Cloudflare.PowerShell.psd1') -Force
    $loadedModule = @(Get-Module -Name Cloudflare.PowerShell | Select-Object -First 1)[0]
    Assert-True ($null -ne $loadedModule -and [IO.Path]::GetFullPath($loadedModule.ModuleBase) -eq [IO.Path]::GetFullPath($isolatedHelpRoot)) 'Isolated module was not loaded from the temporary module directory.'
    $isolatedHelpPath = Join-Path $isolatedHelpRoot 'Cloudflare.PowerShell-help.xml'
    Assert-True (Test-Path -LiteralPath $isolatedHelpPath -PathType Leaf) 'Generated module help resource is missing from the isolated module directory.'
    foreach ($evidence in @($helpNames | ForEach-Object { Get-HelpEvidence $_ })) {
        $expectedHelp = $helpModels[$evidence.Name]
        Assert-True (-not [string]::IsNullOrWhiteSpace($evidence.Synopsis) -and -not [string]::IsNullOrWhiteSpace($evidence.Description)) "Isolated Get-Help $($evidence.Name) returned empty generated help."
        Assert-True ($evidence.Synopsis -eq [string]$expectedHelp.synopsis -and $evidence.Description.StartsWith([string]$expectedHelp.description, [StringComparison]::Ordinal)) "Isolated Get-Help $($evidence.Name) drifted from canonical projection help."
    }
}
finally {
    Remove-Module -Name Cloudflare.PowerShell -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $isolatedHelpRoot) { Remove-Item -LiteralPath $isolatedHelpRoot -Recurse -Force }
}
Write-Output 'PASS actual Get-Help host discovery in current and isolated module directories'
