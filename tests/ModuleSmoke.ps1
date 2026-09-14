[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $ProjectRoot 'module/Cloudflare.PowerShell'
$projectFile = Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Cloudflare.PowerShell.csproj'
$projectXml = [xml](Get-Content -Raw -LiteralPath $projectFile)
$targetFramework = [string]$projectXml.Project.PropertyGroup.TargetFramework
if ([string]::IsNullOrWhiteSpace($targetFramework)) { throw 'Could not determine the Cloudflare.PowerShell target framework.' }
$dllPath = Join-Path $ProjectRoot "src/Cloudflare.PowerShell/bin/Release/$targetFramework/Cloudflare.PowerShell.dll"
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
        {
            var error = new HttpResponseMessage(HttpStatusCode.BadRequest) { Content = new StringContent("{\"success\":false,\"errors\":[{\"code\":1001,\"message\":\"bad request\"}]}", Encoding.UTF8, "application/json") };
            error.Headers.TryAddWithoutValidation("CF-Ray", "smoke-ray-1");
            return error;
        }
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
$hostSmaPath = [System.Management.Automation.PSCmdlet].Assembly.Location
$expectedHostSmaPath = Join-Path $PSHOME 'System.Management.Automation.dll'
if ([IO.Path]::GetFullPath($hostSmaPath) -ne [IO.Path]::GetFullPath($expectedHostSmaPath)) {
    throw "PowerShell runtime SMA was not loaded from the current host: $hostSmaPath"
}
$publicCommandNames = @('Get-CfZone', 'Get-CfDnsRecord', 'New-CfDnsRecord', 'Remove-CfDnsRecord', 'Set-CfDnsRecord')
foreach ($name in $publicCommandNames) {
    $command = Get-Command $name -ErrorAction Stop
    if ($command.CommandType -ne 'Cmdlet') { throw "Public command '$name' did not resolve to a generated cmdlet." }
    $shadowingFunctions = @(Get-Command $name -All -ErrorAction Stop | Where-Object CommandType -eq 'Function')
    if ($shadowingFunctions.Count -ne 0) { throw "Public command '$name' is still shadowed by an exported function." }
}
Write-Output 'PASS ordinary public command routing'
[P1ModuleMockHandler]::Reset()
$handler = [P1ModuleMockHandler]::new()
$records = @(Get-CfDnsRecord -ZoneId zone -BaseUrl 'https://mock.test/client/v4/' -Token token -Handler $handler)
if ($records.Count -ne 1 -or $records[0].Id -ne 'r1') { throw 'Get-CfDnsRecord did not emit typed records.' }
if ([P1ModuleMockHandler]::Requests.Count -ne 2) { throw 'List did not request page 1 and page 2.' }
if ([P1ModuleMockHandler]::Requests[0].RequestUri.Query -notmatch 'page=1') { throw 'Page 1 query missing.' }

[P1ModuleMockHandler]::Reset()
$handler = [P1ModuleMockHandler]::new()
$typedInput = [Cloudflare.PowerShell.CfARecordInput]::new()
$typedInput.Name = [Cloudflare.PowerShell.Optional[string]]::From('example.com')
$typedInput.Ttl = [Cloudflare.PowerShell.Optional[int]]::From(300)
$typedInput.Content = [Cloudflare.PowerShell.Optional[string]]::From('198.51.100.4')
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
    if ($_.CategoryInfo.Category -ne 'InvalidArgument') { throw "Unexpected ErrorRecord category: $($_.CategoryInfo.Category)" }
    if ($_.TargetObject -ne 'zone') { throw "Unexpected ErrorRecord target: $($_.TargetObject)" }
    if ($_.Exception.RequestId -ne 'smoke-ray-1') { throw "Request ID was not retained: $($_.Exception.RequestId)" }
    if ($_.Exception.Errors[0].Code -ne 1001) { throw 'Cloudflare error code was not retained.' }
    if ($_.Exception.RawBody -notmatch 'bad request') { throw 'Safe raw error body was not retained.' }
}

Write-Output 'PASS module import and cmdlet smoke'
