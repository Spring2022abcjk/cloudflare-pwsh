[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $ProjectRoot 'module/Cloudflare.PowerShell'
$dllPath = Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/bin/Release/net10.0/Cloudflare.PowerShell.dll'
Copy-Item -LiteralPath $dllPath -Destination $modulePath -Force

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
    public static void Reset() { Requests.Clear(); Bodies.Clear(); }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Requests.Add(request);
        Bodies.Add(request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellationToken));
        var path = request.RequestUri.AbsolutePath;
        var query = request.RequestUri.Query;
        if (query.Contains("name=fail", StringComparison.Ordinal))
        {
            var error = new HttpResponseMessage(HttpStatusCode.BadRequest)
            {
                Content = new StringContent("{\"success\":false,\"errors\":[{\"code\":1001,\"message\":\"bad request\"}]}", Encoding.UTF8, "application/json")
            };
            error.Headers.TryAddWithoutValidation("CF-Ray", "p32-ray-1");
            return error;
        }
        if (request.Method == HttpMethod.Delete)
            return Response("{\"success\":true,\"result\":{}}");
        if (request.Method == HttpMethod.Post)
            return Response("{\"success\":true,\"result\":{\"id\":\"created\",\"type\":\"A\"}}");
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

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-GeneratedCommand {
    param([Parameter(Mandatory)][string]$Name)
    return Get-Command $Name -CommandType Cmdlet -ErrorAction Stop
}

$zoneCommand = Get-GeneratedCommand 'Get-CfZone'
$dnsCommand = Get-GeneratedCommand 'Get-CfDnsRecord'
$newCommand = Get-GeneratedCommand 'New-CfDnsRecord'
$removeCommand = Get-GeneratedCommand 'Remove-CfDnsRecord'
Assert-True (@($zoneCommand.ParameterSets.Name) -contains 'List' -and @($zoneCommand.ParameterSets.Name) -contains 'Get') 'Get-CfZone parameter sets are incomplete.'
Assert-True (@($dnsCommand.ParameterSets.Name) -contains 'List' -and @($dnsCommand.ParameterSets.Name) -contains 'Get') 'Get-CfDnsRecord parameter sets are incomplete.'
Assert-True ($zoneCommand.OutputType.Type.FullName -contains 'Cloudflare.PowerShell.CfZone') 'Get-CfZone output metadata is not typed.'
Assert-True ($dnsCommand.OutputType.Type.FullName -contains 'Cloudflare.PowerShell.CfDnsRecord') 'Get-CfDnsRecord output metadata is not typed.'
$zoneAttribute = @($zoneCommand.Parameters['ZoneId'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })[0]
Assert-True $zoneAttribute.ValueFromPipelineByPropertyName 'Get-CfZone ZoneId pipeline binding is missing.'
$newMetadata = [System.Management.Automation.CommandMetadata]::new($newCommand)
$removeMetadata = [System.Management.Automation.CommandMetadata]::new($removeCommand)
Assert-True $newMetadata.SupportsShouldProcess 'New-CfDnsRecord ShouldProcess metadata is missing.'
Assert-True $removeMetadata.SupportsShouldProcess 'Remove-CfDnsRecord ShouldProcess metadata is missing.'
Assert-True ([Cloudflare.PowerShell.P32CmdletHelpMetadata]::Commands.ContainsKey('Get-CfZone')) 'Generated Get-CfZone help model is missing.'
Assert-True (-not [string]::IsNullOrWhiteSpace([Cloudflare.PowerShell.P32CmdletHelpMetadata]::Commands['Get-CfZone'].Synopsis)) 'Generated Get-CfZone help synopsis is missing.'
$projection = Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'artifacts/p3.2/CmdletModel.json') | ConvertFrom-Json
foreach ($model in $projection.cmdlets) {
    $command = Get-GeneratedCommand $model.cmdletName
    $actualSets = @($command.ParameterSets.Name | Where-Object { $_ -ne '__AllParameterSets' } | Sort-Object -Unique)
    $expectedSets = @($model.parameterSets | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    Assert-True (($actualSets -join '|') -eq ($expectedSets -join '|')) "$($model.cmdletName) parameter-set projection drifted."
    foreach ($parameterName in $model.parameterNames) {
        Assert-True $command.Parameters.ContainsKey([string]$parameterName) "$($model.cmdletName) is missing projected parameter '$parameterName'."
    }
}
Write-Output 'PASS generated cmdlet metadata'

$baseArgs = @{ BaseUrl = 'https://mock.test/client/v4/'; Token = 'token'; Handler = [P32MockHandler]::new() }

[P32MockHandler]::Reset()
$zones = @(& $zoneCommand @baseArgs)
Assert-True ($zones.Count -eq 1 -and $zones[0] -is [Cloudflare.PowerShell.CfZone]) 'Generated Get-CfZone list did not emit typed items.'
Assert-True ([P32MockHandler]::Requests.Count -eq 2) 'Generated Get-CfZone list did not use shared pagination.'
Assert-True ([P32MockHandler]::Requests[0].RequestUri.Query -match 'page=1') 'Generated Get-CfZone page 1 was not requested.'
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
& $removeCommand -ZoneId zone -DnsRecordId record @baseArgs -Confirm:$false
Assert-True ([P32MockHandler]::Requests.Count -eq 1) 'Generated Remove-CfDnsRecord did not send exactly one request.'
Assert-True ([P32MockHandler]::Requests[0].Method -eq [System.Net.Http.HttpMethod]::Delete) 'Generated Remove-CfDnsRecord did not send DELETE.'
Assert-True ([P32MockHandler]::Bodies[0] -eq '') 'Generated Remove-CfDnsRecord sent a DELETE body.'
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
$handwritten = @(Get-CfDnsRecord -ZoneId zone -Name example.com -BaseUrl $baseArgs.BaseUrl -Token $baseArgs.Token -Handler $baseArgs.Handler)
$handwrittenRequest = [P32MockHandler]::Requests[0]
$handwrittenBody = [P32MockHandler]::Bodies[0]
[P32MockHandler]::Reset()
$generated = @(& $dnsCommand -ZoneId zone -Name example.com @baseArgs)
$generatedRequest = [P32MockHandler]::Requests[0]
$generatedBody = [P32MockHandler]::Bodies[0]
Assert-True ($handwritten.Count -eq $generated.Count -and $handwritten[0].Id -eq $generated[0].Id) 'Handwritten/generated output parity failed.'
Assert-True ($handwrittenRequest.Method -eq $generatedRequest.Method -and $handwrittenRequest.RequestUri.AbsolutePath -eq $generatedRequest.RequestUri.AbsolutePath -and $handwrittenRequest.RequestUri.Query -eq $generatedRequest.RequestUri.Query -and $handwrittenBody -eq $generatedBody) 'Handwritten/generated HTTP parity failed.'
Write-Output 'PASS handwritten/generated behavioral parity'
