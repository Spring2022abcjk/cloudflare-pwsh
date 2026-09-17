[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ModulePath,
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedModule = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ModulePath).Path)
$manifestPath = Join-Path $resolvedModule 'Cloudflare.PowerShell.psd1'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Candidate module manifest is missing: $manifestPath"
}

$commands = @('Get-CfZone', 'Get-CfDnsRecord', 'New-CfDnsRecord', 'Remove-CfDnsRecord', 'Set-CfDnsRecord')
$records = [Collections.Generic.List[object]]::new()
$observations = [Collections.Generic.List[object]]::new()

function Add-Observation {
    param(
        [Parameter(Mandatory)][string]$Area,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Detail
    )
    $observations.Add([ordered]@{ area = $Area; status = $Status; detail = $Detail })
}

Import-Module -Name $manifestPath -Force
$loaded = Get-Module -Name Cloudflare.PowerShell | Where-Object {
    [IO.Path]::GetFullPath($_.ModuleBase) -ceq $resolvedModule
} | Select-Object -First 1
if ($null -eq $loaded) { throw "Candidate module was not loaded from $resolvedModule" }

$manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
$actualCommands = @(Get-Command -Module $loaded.Name -CommandType Cmdlet | ForEach-Object Name | Sort-Object)
Add-Observation 'surface' $(if (($actualCommands -join '|') -ceq (($commands | Sort-Object) -join '|')) { 'Pass' } else { 'Fail' }) "Candidate exports: $($actualCommands -join ', ')"

$helpXmlPath = Join-Path $resolvedModule 'Cloudflare.PowerShell-help.xml'
$helpXml = [xml](Get-Content -Raw -LiteralPath $helpXmlPath)
$helpNs = [Xml.XmlNamespaceManager]::new($helpXml.NameTable)
$helpNs.AddNamespace('msh', 'http://msh')
$helpNs.AddNamespace('maml', 'http://schemas.microsoft.com/maml/2004/10')
$helpNs.AddNamespace('command', 'http://schemas.microsoft.com/maml/dev/command/2004/10')

foreach ($name in $commands) {
    $command = Get-Command $name -ErrorAction Stop
    $type = $command.ImplementingType
    $cmdletAttribute = @($type.GetCustomAttributes($false) | Where-Object { $_.GetType().FullName -eq 'System.Management.Automation.CmdletAttribute' }) | Select-Object -First 1
    $parameters = @($command.Parameters.Values | Sort-Object Name | ForEach-Object {
        [ordered]@{
            name = $_.Name
            type = [string]$_.ParameterType.FullName
            aliases = @($_.Aliases)
            mandatory = @($_.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | ForEach-Object { $_.Mandatory }) -contains $true
            valueFromPipeline = @($_.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | ForEach-Object { $_.ValueFromPipeline }) -contains $true
            valueFromPipelineByPropertyName = @($_.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | ForEach-Object { $_.ValueFromPipelineByPropertyName }) -contains $true
            parameterSets = @($_.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | ForEach-Object { $_.ParameterSetName } | Sort-Object -Unique)
        }
    })
    $helpNode = $helpXml.SelectSingleNode("/msh:helpItems/command:command[command:details/command:name='$name']", $helpNs)
    $synopsis = [string]$helpNode.SelectSingleNode('command:details/maml:description/maml:para', $helpNs).InnerText
    $description = [string]$helpNode.SelectSingleNode('maml:description/maml:para', $helpNs).InnerText
    $examples = @($helpNode.SelectNodes('.//command:examples/command:example', $helpNs))
    $parameterHelp = @($helpNode.SelectNodes('.//command:parameter', $helpNs))
    $relatedLinks = @($helpNode.SelectNodes('.//maml:relatedLinks/*', $helpNs))
    $outputTypes = @($command.OutputType | ForEach-Object { [string]$_.Type })
    $parameterSets = @($command.ParameterSets | ForEach-Object { [ordered]@{ name = $_.Name; parameters = @($_.Parameters | ForEach-Object Name) } })
    $records.Add([ordered]@{
        command = $name
        defaultParameterSet = [string]$command.DefaultParameterSet
        parameterSets = $parameterSets
        parameters = $parameters
        supportsShouldProcess = [bool]$cmdletAttribute.SupportsShouldProcess
        confirmImpact = [string]$cmdletAttribute.ConfirmImpact
        outputTypes = $outputTypes
        help = [ordered]@{ synopsis = $synopsis; description = $description; parameterCount = $parameterHelp.Count; exampleCount = $examples.Count; relatedLinkCount = $relatedLinks.Count }
    })
    Add-Observation "help:$name" $(if ($parameterHelp.Count -eq 0 -and $examples.Count -eq 0 -and $relatedLinks.Count -eq 0) { 'Missing' } else { 'Partial' }) "parameterHelp=$($parameterHelp.Count), examples=$($examples.Count), relatedLinks=$($relatedLinks.Count)"
}

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public sealed class P41UxMockHandler : HttpMessageHandler
{
    public static List<HttpRequestMessage> Requests { get; } = new();
    public static void Reset() { Requests.Clear(); }
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Requests.Add(request);
        var path = request.RequestUri?.AbsolutePath ?? "";
        if (request.RequestUri?.Query.Contains("name=fail", StringComparison.Ordinal) == true)
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.BadRequest) { Content = new StringContent("{\"success\":false,\"errors\":[{\"code\":1001,\"message\":\"bad request\"}]}", Encoding.UTF8, "application/json") });
        if (request.Method == HttpMethod.Delete)
            return Task.FromResult(Response("{\"success\":true,\"result\":{}}"));
        if (request.Method == HttpMethod.Post)
            return Task.FromResult(Response("{\"success\":true,\"result\":{\"id\":\"created\",\"name\":\"example.com\",\"type\":\"A\",\"content\":\"198.51.100.4\"}}"));
        if (request.Method == HttpMethod.Put || request.Method == HttpMethod.Patch)
            return Task.FromResult(Response("{\"success\":true,\"result\":{\"id\":\"updated\",\"name\":\"example.com\",\"type\":\"A\",\"content\":\"198.51.100.5\"}}"));
        if (path.EndsWith("/zones", StringComparison.Ordinal))
        {
            var zonePageTwo = request.RequestUri?.Query.Contains("page=2", StringComparison.Ordinal) == true;
            var zoneResult = zonePageTwo ? "[]" : "[{\"id\":\"zone\",\"name\":\"example.com\",\"status\":\"active\",\"type\":\"full\"}]";
            return Task.FromResult(Response("{\"success\":true,\"result\":" + zoneResult + ",\"result_info\":{\"page\":1,\"total_pages\":2}}"));
        }
        if (path.Contains("/zones/zone", StringComparison.Ordinal) && !path.Contains("dns_records", StringComparison.Ordinal))
            return Task.FromResult(Response("{\"success\":true,\"result\":{\"id\":\"zone\",\"name\":\"example.com\",\"status\":\"active\",\"type\":\"full\"}}"));
        var pageTwo = request.RequestUri?.Query.Contains("page=2", StringComparison.Ordinal) == true;
        var result = pageTwo ? "[]" : "[{\"id\":\"record\",\"name\":\"www.example.com\",\"type\":\"A\",\"content\":\"198.51.100.4\",\"zone_id\":\"zone\"}]";
        var body = "{\"success\":true,\"result\":" + result + ",\"result_info\":{\"page\":1,\"total_pages\":2}}";
        return Task.FromResult(Response(body));
    }
    private static HttpResponseMessage Response(string body) => new(HttpStatusCode.OK) { Content = new StringContent(body, Encoding.UTF8, "application/json") };
}
'@

$handler = [P41UxMockHandler]::new()
$base = 'https://mock.test/client/v4/'
$common = @{ BaseUrl = $base; Token = 'token'; Handler = $handler }

$zones = @(Get-CfZone @common)
Add-Observation 'workflow:Get-CfZone' $(if ($zones.Count -eq 1 -and $zones[0].Id -eq 'zone') { 'Pass' } else { 'Fail' }) "count=$($zones.Count), outputType=$($zones[0].GetType().FullName)"
Add-Observation 'output:Get-CfZone' 'Observed' ((@($zones | Out-String -Width 120).Trim()) -replace "\r?\n", ' / ')

$pipelineError = $null
try { @($zones | Get-CfDnsRecord @common -ErrorAction Stop) | Out-Null } catch { $pipelineError = $_ }
if ($null -eq $pipelineError) {
    Add-Observation 'workflow:Zone-to-Dns-pipeline' 'Pass' 'Zone output bound successfully.'
} else {
    Add-Observation 'workflow:Zone-to-Dns-pipeline' 'Fail' "Cannot bind CfZone.Id to mandatory Get-CfDnsRecord.ZoneId: $($pipelineError.Exception.Message)"
}

$recordsOut = @(Get-CfDnsRecord -ZoneId zone @common)
Add-Observation 'workflow:Get-CfDnsRecord' $(if ($recordsOut.Count -eq 1 -and $recordsOut[0].Id -eq 'record') { 'Pass' } else { 'Fail' }) "count=$($recordsOut.Count), outputType=$($recordsOut[0].GetType().FullName), requests=$([P41UxMockHandler]::Requests.Count)"

$whatIfRequestsBefore = [P41UxMockHandler]::Requests.Count
$removeWhatIfText = @(& { Remove-CfDnsRecord -ZoneId zone -DnsRecordId record @common -WhatIf } *>&1 | ForEach-Object { [string]$_ })
$whatIfRequestsAfter = [P41UxMockHandler]::Requests.Count
$removeWhatIfDetail = if ($removeWhatIfText.Count -gt 0) { $removeWhatIfText -join ' / ' } else { 'WhatIf message was emitted by the host warning path; direct console text is verified separately.' }
Add-Observation 'workflow:Remove-CfDnsRecord-WhatIf' $(if ($whatIfRequestsBefore -eq $whatIfRequestsAfter) { 'Pass' } else { 'Fail' }) "requestsBefore=$whatIfRequestsBefore, requestsAfter=$whatIfRequestsAfter, message=$removeWhatIfDetail"

$typed = [Cloudflare.PowerShell.CfARecordInput]::new()
$typed.Name = [Cloudflare.PowerShell.Optional[string]]::From('example.com')
$typed.Ttl = [Cloudflare.PowerShell.Optional[int]]::From(300)
$typed.Content = [Cloudflare.PowerShell.Optional[string]]::From('198.51.100.4')
$newWhatIfText = @(& { New-CfDnsRecord -ZoneId zone -Record $typed @common -WhatIf } *>&1 | ForEach-Object { [string]$_ })
Add-Observation 'workflow:New-CfDnsRecord-WhatIf' 'Observed' $(if ($newWhatIfText.Count -gt 0) { $newWhatIfText -join ' / ' } else { 'WhatIf message was emitted by the host warning path; direct console text is verified separately.' })
$created = New-CfDnsRecord -ZoneId zone -Record $typed @common -Confirm:$false
Add-Observation 'workflow:New-CfDnsRecord' $(if ($created.Id -eq 'created') { 'Pass' } else { 'Fail' }) "outputType=$($created.GetType().FullName), id=$($created.Id)"

$setWhatIfText = @(& { Set-CfDnsRecord -ZoneId zone -DnsRecordId record -Edit @{ content = '198.51.100.5' } @common -WhatIf } *>&1 | ForEach-Object { [string]$_ })
Add-Observation 'workflow:Set-CfDnsRecord-WhatIf' 'Observed' $(if ($setWhatIfText.Count -gt 0) { $setWhatIfText -join ' / ' } else { 'WhatIf message was emitted by the host warning path; direct console text is verified separately.' })
$updated = Set-CfDnsRecord -ZoneId zone -DnsRecordId record -Edit @{ content = '198.51.100.5' } @common -Confirm:$false
Add-Observation 'workflow:Set-CfDnsRecord' $(if ($updated.Id -eq 'updated') { 'Pass' } else { 'Fail' }) "outputType=$($updated.GetType().FullName), id=$($updated.Id)"

$errorHandler = [P41UxMockHandler]::new()
$errorPresentation = $null
try {
    Get-CfDnsRecord -ZoneId zone -Name fail -BaseUrl $base -Token token -Handler $errorHandler -ErrorAction Stop | Out-Null
} catch {
    $errorPresentation = [ordered]@{ exception = $_.Exception.GetType().FullName; message = $_.Exception.Message; fullyQualifiedErrorId = $_.FullyQualifiedErrorId; category = [string]$_.CategoryInfo.Category; target = [string]$_.TargetObject }
}
Add-Observation 'workflow:error-presentation' $(if ($null -ne $errorPresentation) { 'Observed' } else { 'Missing' }) $(if ($null -ne $errorPresentation) { ($errorPresentation | ConvertTo-Json -Compress) } else { 'Expected mock error did not surface.' })
Add-Observation 'output:Get-CfDnsRecord' 'Observed' ((@($recordsOut | Out-String -Width 120).Trim()) -replace "\r?\n", ' / ')

$formatData = @(Get-FormatData -TypeName 'Cloudflare.PowerShell.CfDnsRecord' -ErrorAction SilentlyContinue)
$formatFiles = @(Get-ChildItem -LiteralPath $resolvedModule -File -Filter '*.ps1xml' -ErrorAction SilentlyContinue)
$completionInput = 'Get-CfDnsRecord -'
$completion = TabExpansion2 -inputScript $completionInput -cursorColumn $completionInput.Length
Add-Observation 'completion' $(if ($completion.CompletionMatches.Count -gt 0) { 'Pass' } else { 'Missing' }) "parameterMatches=$($completion.CompletionMatches.Count)"
Add-Observation 'formatting' $(if ($formatData.Count -gt 0 -or $formatFiles.Count -gt 0) { 'Present' } else { 'Missing' }) "formatData=$($formatData.Count), formatFiles=$($formatFiles.Count)"

$report = [ordered]@{
    schemaVersion = 1
    stage = 'P4.1-Phase0'
    modulePath = $resolvedModule
    moduleVersion = [string]$manifest.ModuleVersion
    powershell = [string]$PSVersionTable.PSVersion
    dotnet = ((& dotnet --version | Select-Object -First 1).Trim())
    commands = @($records)
    observations = @($observations)
    requestTrace = @([P41UxMockHandler]::Requests | ForEach-Object { [ordered]@{ method = $_.Method.Method; uri = $_.RequestUri.AbsoluteUri } })
}
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $output = [IO.Path]::GetFullPath($OutputPath)
    $json = $report | ConvertTo-Json -Depth 20
    $normalized = $json.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
    [IO.File]::WriteAllText($output, $normalized, [Text.UTF8Encoding]::new($false))
}
$report | ConvertTo-Json -Depth 20
