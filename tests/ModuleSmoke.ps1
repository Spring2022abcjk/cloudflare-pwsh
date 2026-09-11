[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $ProjectRoot 'module/Cloudflare.PowerShell'
$dllPath = Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/bin/Release/net8.0/Cloudflare.PowerShell.dll'
Copy-Item -LiteralPath $dllPath -Destination $modulePath -Force

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public sealed class P1ModuleMockHandler : HttpMessageHandler
{
    public static List<HttpRequestMessage> Requests { get; } = new();
    public static List<string> Bodies { get; } = new();
    public static void Reset() { Requests.Clear(); Bodies.Clear(); }
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Requests.Add(request);
        Bodies.Add(request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellationToken));
        if (request.RequestUri.Query.Contains("name=fail", StringComparison.Ordinal))
            return new HttpResponseMessage(HttpStatusCode.BadRequest) { Content = new StringContent("{\"success\":false,\"errors\":[{\"code\":1001,\"message\":\"bad request\"}]}", Encoding.UTF8, "application/json") };
        var page = request.RequestUri.Query.Contains("page=2", StringComparison.Ordinal) ? "[]" : "[{\"id\":\"r1\",\"name\":\"example.com\",\"type\":\"A\",\"content\":\"198.51.100.4\"}]";
        if (request.Method == HttpMethod.Delete)
            return Response("{\"success\":true,\"result\":{}}");
        if (request.Method == HttpMethod.Post)
            return Response("{\"success\":true,\"result\":{\"id\":\"created\",\"type\":\"A\"}}");
        return Response("{\"success\":true,\"result\":" + page + "}");
    }
    private static HttpResponseMessage Response(string body) => new(HttpStatusCode.OK) { Content = new StringContent(body, Encoding.UTF8, "application/json") };
}
'@

Import-Module (Join-Path $modulePath 'Cloudflare.PowerShell.psd1') -Force
[P1ModuleMockHandler]::Reset()
$handler = [P1ModuleMockHandler]::new()
$records = @(Get-CfDnsRecord -ZoneId zone -BaseUrl 'https://mock.test/client/v4/' -Token token -Handler $handler)
if ($records.Count -ne 1 -or $records[0].Id -ne 'r1') { throw 'Get-CfDnsRecord did not emit typed records.' }
if ([P1ModuleMockHandler]::Requests.Count -ne 2) { throw 'List did not request page 1 and page 2.' }
if ([P1ModuleMockHandler]::Requests[0].RequestUri.Query -notmatch 'page=1') { throw 'Page 1 query missing.' }

[P1ModuleMockHandler]::Reset()
$handler = [P1ModuleMockHandler]::new()
$typedInput = [Cloudflare.PowerShell.CfDnsRecordInput]@{ Type = 'A'; Name = 'example.com'; Ttl = 300; Content = '198.51.100.4' }
$created = New-CfDnsRecord -ZoneId zone -Record $typedInput -BaseUrl 'https://mock.test/client/v4/' -Token token -Handler $handler -Confirm:$false
if ($created.Id -ne 'created') { throw 'New-CfDnsRecord did not unwrap typed output.' }
if ([P1ModuleMockHandler]::Bodies[0] -notmatch '"type":"A"') { throw 'Create body missing discriminator.' }

[P1ModuleMockHandler]::Reset()
$handler = [P1ModuleMockHandler]::new()
Remove-CfDnsRecord -ZoneId zone -RecordId record -BaseUrl 'https://mock.test/client/v4/' -Token token -Handler $handler -Confirm:$false
if ([P1ModuleMockHandler]::Bodies[0] -ne '') { throw 'Remove sent a DELETE body.' }

[P1ModuleMockHandler]::Reset()
try {
    Get-CfDnsRecord -ZoneId zone -Name fail -BaseUrl 'https://mock.test/client/v4/' -Token token -Handler ([P1ModuleMockHandler]::new()) -ErrorAction Stop | Out-Null
    throw 'Expected a PowerShell ErrorRecord.'
} catch {
    if ($_.Exception.FullyQualifiedErrorId -ne 'Cloudflare.Api.400') { throw "Unexpected stable error id: $($_.Exception.FullyQualifiedErrorId)" }
}

Write-Output 'PASS module import and cmdlet smoke'
