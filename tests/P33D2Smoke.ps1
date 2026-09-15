[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ModulePath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryModulePath = [IO.Path]::GetFullPath((Join-Path $ProjectRoot 'module/Cloudflare.PowerShell'))
$requestedModulePath = if ([string]::IsNullOrWhiteSpace($ModulePath)) { $repositoryModulePath } else { [IO.Path]::GetFullPath($ModulePath) }
$p33StagingRoot = Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p33-d2-smoke-' + [guid]::NewGuid().ToString('N'))
$modulePath = Join-Path (Join-Path $p33StagingRoot 'module') 'Cloudflare.PowerShell'
$dllPath = Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/bin/Release/net10.0/Cloudflare.PowerShell.dll'
. (Join-Path $ProjectRoot 'tools/ReadOnlyStaging.ps1') -Library
try {
    foreach ($staleRoot in @(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'cloudflare-p33-d2-smoke-*' -Force | Where-Object { $_.FullName -ne $p33StagingRoot })) {
        try { Remove-Item -LiteralPath $staleRoot.FullName -Recurse -Force -ErrorAction Stop } catch { }
    }
    if (-not (Test-Path -LiteralPath $requestedModulePath -PathType Container)) { throw "D2 smoke module source is missing: $requestedModulePath" }
    if (-not (Test-Path -LiteralPath $dllPath -PathType Leaf)) { throw "Release PowerShell assembly is missing: $dllPath" }
    $moduleInputs = @('Cloudflare.PowerShell.psd1','Cloudflare.PowerShell.psm1')
    Copy-ReadOnlyStagingFiles -SourceRoot $requestedModulePath -DestinationRoot $modulePath -RelativePaths $moduleInputs
    [void](Assert-ReadOnlyStagingInputContract -Root $modulePath -ExpectedRelativePaths $moduleInputs)
    if ([IO.Path]::GetFullPath($modulePath) -eq $repositoryModulePath) { throw 'D2 smoke staging resolved to the repository module path.' }
    Copy-Item -LiteralPath $dllPath -Destination $modulePath -Force
    $bundled = @(Get-ChildItem -LiteralPath $modulePath -Recurse -File | Where-Object { $_.Name -in @('System.Management.Automation.dll','Microsoft.PowerShell.SDK.dll') -or $_.Name -like 'Microsoft.PowerShell*.dll' -or $_.FullName -match '[\/]runtimes[\/]'} )
    if ($bundled.Count -ne 0) { throw 'D2 smoke staging contains bundled PowerShell runtime files.' }

Add-Type -TypeDefinition @'
#nullable enable
using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public sealed class P33D2MockHandler : HttpMessageHandler
{
    public static List<HttpRequestMessage> Requests { get; } = new();
    public static List<string> Bodies { get; } = new();
    public static string FailMode { get; set; } = "";
    public static void Reset() { Requests.Clear(); Bodies.Clear(); FailMode = ""; }
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var body = request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellationToken);
        Requests.Add(request); Bodies.Add(body);
        var path = request.RequestUri!.AbsolutePath;
        if (FailMode == "error" && request.Method == HttpMethod.Get && path.EndsWith("/healthchecks", StringComparison.Ordinal))
            return Response(HttpStatusCode.BadRequest, "{\"success\":false,\"errors\":[{\"code\":1001,\"message\":\"healthcheck mock failure\"}],\"messages\":[],\"result\":null}", "p33-d2-ray-error");
        if (request.Method == HttpMethod.Get && path.EndsWith("/healthchecks", StringComparison.Ordinal))
        {
            var pageTwo = request.RequestUri.Query.Contains("page=2", StringComparison.Ordinal);
            var result = pageTwo ? "[]" : "[{\"address\":\"https://example.test\",\"check_regions\":[\"WNAM\"],\"http_config\":{\"method\":\"GET\",\"path\":\"/health\",\"header\":{\"X-Test\":[\"one\"]}},\"id\":\"hc-1\",\"name\":\"demo\",\"status\":\"healthy\"}]";
            return Response(HttpStatusCode.OK, "{\"success\":true,\"result\":" + result + ",\"result_info\":{\"count\":1,\"page\":1,\"per_page\":1,\"total_count\":1}}");
        }
        if (request.Method == HttpMethod.Get && path.EndsWith("/healthchecks/hc-1", StringComparison.Ordinal))
            return Response(HttpStatusCode.OK, "{\"success\":true,\"result\":{\"address\":\"https://example.test\",\"id\":\"hc-1\",\"name\":\"demo\",\"status\":\"healthy\"}}");
        if (request.Method == HttpMethod.Delete)
            return Response(HttpStatusCode.OK, "{\"success\":true,\"result\":{\"id\":\"hc-1\"}}");
        if (request.Method == HttpMethod.Post)
            return Response(HttpStatusCode.OK, "{\"success\":true,\"result\":{\"address\":\"https://example.test\",\"id\":\"hc-new\",\"name\":\"created\",\"status\":\"healthy\"}}");
        if (request.Method == HttpMethod.Put)
            return Response(HttpStatusCode.OK, "{\"success\":true,\"result\":{\"address\":\"https://example.test\",\"id\":\"hc-1\",\"name\":\"updated\",\"status\":\"healthy\"}}");
        if (request.Method == HttpMethod.Patch)
            return Response(HttpStatusCode.OK, "{\"success\":true,\"result\":{\"address\":\"https://example.test\",\"id\":\"hc-1\",\"name\":\"patched\",\"status\":\"healthy\"}}");
        return Response(HttpStatusCode.NotFound, "{\"success\":false,\"errors\":[{\"code\":404,\"message\":\"not found\"}],\"messages\":[],\"result\":null}", "p33-d2-ray-404");
    }
    private static HttpResponseMessage Response(HttpStatusCode status, string body, string? ray = null)
    {
        var response = new HttpResponseMessage(status) { Content = new StringContent(body, Encoding.UTF8, "application/json") };
        if (!String.IsNullOrEmpty(ray)) response.Headers.TryAddWithoutValidation("cf-ray", ray);
        return response;
    }
}
'@

Import-Module (Join-Path $modulePath 'Cloudflare.PowerShell.psd1') -Force
$hostSmaPath = [System.Management.Automation.PSCmdlet].Assembly.Location
if ([IO.Path]::GetFullPath($hostSmaPath) -ne [IO.Path]::GetFullPath((Join-Path $PSHOME 'System.Management.Automation.dll'))) { throw "PowerShell runtime SMA was not loaded from the current host: $hostSmaPath" }
function Assert-True { param([bool]$Condition,[string]$Message); if (-not $Condition) { throw $Message } }
foreach ($name in @('Get-CfHealthCheck','New-CfHealthCheck','Remove-CfHealthCheck','Set-CfHealthCheck')) {
    $command = Get-Command $name -ErrorAction Stop
    Assert-True ($command.CommandType -eq 'Cmdlet') "D2 public command '$name' is not a cmdlet."
    Assert-True (@(Get-Command $name -All | Where-Object CommandType -eq 'Function').Count -eq 0) "D2 command '$name' is shadowed by a function."
}
$get = Get-Command Get-CfHealthCheck; $new = Get-Command New-CfHealthCheck; $remove = Get-Command Remove-CfHealthCheck; $set = Get-Command Set-CfHealthCheck
Assert-True (@($get.ParameterSets.Name) -contains 'Get' -and @($get.ParameterSets.Name) -contains 'List') 'D2 Get parameter sets are incomplete.'
Assert-True (@($set.ParameterSets.Name) -contains 'Update' -and @($set.ParameterSets.Name) -contains 'Edit') 'D2 Set parameter sets are incomplete.'
$patchParameter = $set.Parameters['Patch']
$patchAttributes = @($patchParameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
Assert-True ($patchParameter.ParameterType -eq [System.Management.Automation.SwitchParameter] -and $patchAttributes.Count -eq 1 -and [string]$patchAttributes[0].ParameterSetName -eq 'Edit') 'D2 imported Patch parameter is not limited to the Edit parameter set.'
Assert-True ($get.OutputType.Type.FullName -contains 'Cloudflare.PowerShell.CfHealthCheck' -and $new.OutputType.Type.FullName -contains 'Cloudflare.PowerShell.CfHealthCheck' -and $set.OutputType.Type.FullName -contains 'Cloudflare.PowerShell.CfHealthCheck') 'D2 typed output metadata is incomplete.'
Assert-True (@($remove.OutputType).Count -eq 0) 'D2 Remove incorrectly advertises output.'
foreach ($command in @($new,$remove,$set)) { Assert-True ([System.Management.Automation.CommandMetadata]::new($command).SupportsShouldProcess) "ShouldProcess metadata is missing for $($command.Name)." }
Assert-True ($get.Parameters['HealthCheckId'].ParameterType -eq [string]) 'D2 health check id was not projected as string.'
$artifact = Get-Content -Raw (Join-Path $ProjectRoot 'artifacts/p3.3/healthchecks/CmdletModel.json') | ConvertFrom-Json
$fixture = Get-Content -Raw (Join-Path $ProjectRoot 'fixtures/p3.3/healthchecks/document.json') | ConvertFrom-Json
$deleteFixture = @($fixture.operations | Where-Object OperationId -eq 'health-checks-delete-health-check')[0]
$deleteTrace = @($deleteFixture.correctionTrace)
Assert-True (@($deleteTrace).Count -eq 1 -and ([string]$deleteTrace[0].match | ConvertFrom-Json).operationId -eq 'health-checks-delete-health-check') 'D2 DELETE correction trace is not exact.'
$corrections = Get-Content -Raw (Join-Path $ProjectRoot 'overrides/api-corrections.json') | ConvertFrom-Json
$d2CorrectionRules = @($corrections.rules | Where-Object { $_.match.operationId -eq 'health-checks-delete-health-check' })
Assert-True (@($d2CorrectionRules).Count -eq 1 -and @($d2CorrectionRules[0].match.PSObject.Properties.Name).Count -eq 1) 'D2 DELETE correction is not scoped to one exact operationId.'
$broadDeleteRules = @($corrections.rules | Where-Object { $match = $_.match; ($null -ne $match.PSObject.Properties['method'] -or $null -ne $match.PSObject.Properties['path']) -and $null -eq $match.PSObject.Properties['operationId'] })
Assert-True (@($broadDeleteRules).Count -eq 0) 'A broad DELETE method/path correction could affect another DELETE operation.'
$runtimeOperations = @([Cloudflare.PowerShell.CfHealthCheckRuntimeMetadata]::Operations)
Assert-True ($runtimeOperations.Count -eq 6) 'D2 runtime metadata does not contain six operations.'
Assert-True ((@($runtimeOperations | ForEach-Object OperationId | Sort-Object) -join '|') -eq (@($artifact.cmdlets | ForEach-Object operations | ForEach-Object operationId | Sort-Object) -join '|')) 'D2 runtime operation ids drifted from canonical artifact.'
Write-Output 'PASS P3.3 D2 generated cmdlet metadata, public surface, and runtime parity'

$base = @{ BaseUrl='https://mock.test/client/v4/'; Token='token'; Handler=[P33D2MockHandler]::new() }
[P33D2MockHandler]::Reset(); $list = @(& $get -ZoneId zone -PerPage 1 @base)
Assert-True ($list.Count -eq 1 -and $list[0] -is [Cloudflare.PowerShell.CfHealthCheck] -and $list[0].Id -eq 'hc-1' -and $list[0].HttpConfig.Header['X-Test'][0] -eq 'one') 'D2 list did not emit typed nested output.'
Assert-True ([P33D2MockHandler]::Requests.Count -eq 2 -and [P33D2MockHandler]::Requests[0].RequestUri.AbsolutePath -eq '/client/v4/zones/zone/healthchecks') 'D2 list path or shared pagination drifted.'
Assert-True ([P33D2MockHandler]::Requests[0].RequestUri.Query -match 'page=1' -and [P33D2MockHandler]::Requests[0].RequestUri.Query -match 'per_page=1' -and [P33D2MockHandler]::Requests[0].Headers.Authorization.ToString() -eq 'Bearer token') 'D2 list query or authentication binding drifted.'
Write-Output 'PASS P3.3 D2 list paging, zone path, authentication, and nested typed output'

[P33D2MockHandler]::Reset(); $one = & $get -ZoneId zone -HealthCheckId hc-1 @base
Assert-True ($one.Id -eq 'hc-1' -and [P33D2MockHandler]::Requests[0].RequestUri.AbsolutePath -eq '/client/v4/zones/zone/healthchecks/hc-1') 'D2 get path or typed response drifted.'
$body = [Cloudflare.PowerShell.CfHealthCheckRequest]::new(); $body.Address='https://example.test'; $body.Name='created'; $body.CheckRegions=@('WNAM'); $body.HttpConfig=[Cloudflare.PowerShell.CfHealthCheckHttpConfig]::new(); $body.HttpConfig.Header=[Collections.Generic.Dictionary[string,string[]]]::new(); $body.HttpConfig.Header['X-Test']=@('one')
[P33D2MockHandler]::Reset(); $created = & $new -ZoneId zone -HealthCheck $body @base -Confirm:$false; $createJson=[System.Text.Json.Nodes.JsonNode]::Parse([P33D2MockHandler]::Bodies[0])
Assert-True ($created -is [Cloudflare.PowerShell.CfHealthCheck] -and [P33D2MockHandler]::Requests[0].Method -eq [Net.Http.HttpMethod]::Post -and $createJson['address'].ToString() -eq 'https://example.test' -and $createJson['http_config']['header']['X-Test'][0].ToString() -eq 'one') 'D2 create JSON body or typed output drifted.'
[P33D2MockHandler]::Reset(); & $new -ZoneId zone -HealthCheck $body @base -WhatIf | Out-Null; Assert-True ([P33D2MockHandler]::Requests.Count -eq 0) 'D2 create WhatIf sent an HTTP request.'
$updatedBody=[Cloudflare.PowerShell.CfHealthCheckRequest]::new(); $updatedBody.Address='https://example.test'; $updatedBody.Name='updated'
[P33D2MockHandler]::Reset(); $updated=& $set -ZoneId zone -HealthCheckId hc-1 -HealthCheck $updatedBody @base -Confirm:$false; Assert-True ($updated.Name -eq 'updated' -and [P33D2MockHandler]::Requests[0].Method -eq [Net.Http.HttpMethod]::Put -and [P33D2MockHandler]::Bodies[0] -match 'address') 'D2 PUT body dispatch drifted.'
[P33D2MockHandler]::Reset(); $patched=& $set -ZoneId zone -HealthCheckId hc-1 -HealthCheck $updatedBody -Patch @base -Confirm:$false; Assert-True ($patched.Name -eq 'patched' -and [P33D2MockHandler]::Requests[0].Method -eq [Net.Http.HttpMethod]::Patch -and [P33D2MockHandler]::Bodies[0] -match 'name') 'D2 PATCH body dispatch drifted.'
Write-Output 'PASS P3.3 D2 create/PUT/PATCH JSON bodies, typed output, and WhatIf'
[P33D2MockHandler]::Reset(); $removed=@(& $remove -ZoneId zone -HealthCheckId hc-1 @base -Confirm:$false); $deleteRequest=[P33D2MockHandler]::Requests[0]; $deleteRequestHeaders=@($deleteRequest.Headers | ForEach-Object { $_.Key }); Assert-True ($removed.Count -eq 0 -and $deleteRequest.Method -eq [Net.Http.HttpMethod]::Delete -and [P33D2MockHandler]::Bodies[0] -eq '' -and $deleteRequest.Content -eq $null -and 'Content-Type' -notin $deleteRequestHeaders) 'D2 DELETE no-output, body, or Content-Type contract drifted.'
Write-Output 'PASS P3.3 D2 DELETE empty body, absent Content-Type, exact correction trace, and non-broad correction scope'
[P33D2MockHandler]::Reset(); [P33D2MockHandler]::FailMode='error'
try { & $get -ZoneId zone @base -ErrorAction Stop | Out-Null; throw 'Expected D2 generated error.' } catch { $exception=$_.Exception; while($exception -and $exception -isnot [Cloudflare.PowerShell.CloudflareApiException] -and $exception.InnerException){$exception=$exception.InnerException}; Assert-True ($exception -is [Cloudflare.PowerShell.CloudflareApiException] -and $exception.RequestId -eq 'p33-d2-ray-error' -and $exception.Errors[0].Code -eq 1001) 'D2 stable error mapping did not retain request id and code.' }
Write-Output 'PASS P3.3 D2 stable error mapping'
}
finally {
    Remove-Module -Name Cloudflare.PowerShell -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $p33StagingRoot) {
        try { Remove-Item -LiteralPath $p33StagingRoot -Recurse -Force -ErrorAction Stop }
        catch { $cleanupPath=$p33StagingRoot.Replace("'","''"); $parentPid=$PID; $cleanupCommand="while (Get-Process -Id $parentPid -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 250 }; Remove-Item -LiteralPath '$cleanupPath' -Recurse -Force -ErrorAction SilentlyContinue"; Start-Process -FilePath (Get-Command pwsh).Source -WindowStyle Hidden -ArgumentList @('-NoLogo','-NoProfile','-Command',$cleanupCommand) | Out-Null }
    }
}
