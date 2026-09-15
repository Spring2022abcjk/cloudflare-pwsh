[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ModulePath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryModulePath = [IO.Path]::GetFullPath((Join-Path $ProjectRoot 'module/Cloudflare.PowerShell'))
$requestedModulePath = if ([string]::IsNullOrWhiteSpace($ModulePath)) { $repositoryModulePath } else { [IO.Path]::GetFullPath($ModulePath) }
$moduleSourcePath = if ($requestedModulePath -eq $repositoryModulePath) { $repositoryModulePath } else { $requestedModulePath }
$p33StagingRoot = Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p33-d1-smoke-' + [guid]::NewGuid().ToString('N'))
$stagedModuleParent = Join-Path $p33StagingRoot 'module'
$modulePath = Join-Path $stagedModuleParent 'Cloudflare.PowerShell'
$dllPath = Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/bin/Release/net10.0/Cloudflare.PowerShell.dll'
. (Join-Path $ProjectRoot 'tools/ReadOnlyStaging.ps1') -Library
try {
    foreach ($staleRoot in @(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'cloudflare-p33-d1-smoke-*' -Force | Where-Object { $_.FullName -ne $p33StagingRoot })) {
        try { Remove-Item -LiteralPath $staleRoot.FullName -Recurse -Force -ErrorAction Stop } catch { }
    }
    if (-not (Test-Path -LiteralPath $moduleSourcePath -PathType Container)) { throw "Smoke module source is missing: $moduleSourcePath" }
    if (-not (Test-Path -LiteralPath $dllPath -PathType Leaf)) { throw "Release PowerShell assembly is missing: $dllPath" }
    $moduleInputPaths = @(
        'Cloudflare.PowerShell.psd1',
        'Cloudflare.PowerShell.psm1'
    )
    Copy-ReadOnlyStagingFiles -SourceRoot $moduleSourcePath -DestinationRoot $modulePath -RelativePaths $moduleInputPaths
    $moduleInventory = @(Assert-ReadOnlyStagingInputContract -Root $modulePath -ExpectedRelativePaths $moduleInputPaths)
    if ($moduleInventory.Count -ne $moduleInputPaths.Count) { throw 'P3.3 smoke module staging admitted an unexpected source file.' }
    if ([IO.Path]::GetFullPath($modulePath) -eq $repositoryModulePath) { throw 'P3.3 smoke staging resolved to the repository module path.' }
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
#nullable enable
using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public sealed class P33D1MockHandler : HttpMessageHandler
{
    public static List<HttpRequestMessage> Requests { get; } = new();
    public static List<string> Bodies { get; } = new();
    public static string FailMode { get; set; } = "";
    public static void Reset() { Requests.Clear(); Bodies.Clear(); FailMode = ""; }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var body = request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellationToken);
        Requests.Add(request);
        Bodies.Add(body);
        var path = request.RequestUri!.AbsolutePath;
        if (FailMode == "error" && path.EndsWith("/d1/database", StringComparison.Ordinal))
            return Response(HttpStatusCode.BadRequest, "{\"success\":false,\"errors\":[{\"code\":1001,\"message\":\"D1 mock failure\"}],\"messages\":[],\"result\":null}", "p33-ray-1");
        if (request.Method == HttpMethod.Get && path.EndsWith("/d1/database", StringComparison.Ordinal))
        {
            var pageTwo = request.RequestUri.Query.Contains("page=2", StringComparison.Ordinal);
            var result = pageTwo ? "[]" : "[{\"created_at\":\"2026-09-14T00:00:00Z\",\"jurisdiction\":\"us\",\"name\":\"demo\",\"uuid\":\"db-1\",\"version\":\"1\"}]";
            return Response(HttpStatusCode.OK, "{\"success\":true,\"result\":" + result + ",\"result_info\":{\"count\":1,\"page\":1,\"per_page\":1,\"total_count\":1}}");
        }
        if (request.Method == HttpMethod.Get && path.EndsWith("/d1/database/db-1", StringComparison.Ordinal))
            return Response(HttpStatusCode.OK, "{\"success\":true,\"result\":{\"created_at\":\"2026-09-14T00:00:00Z\",\"file_size\":12,\"jurisdiction\":\"us\",\"name\":\"demo\",\"num_tables\":2,\"read_replication\":{\"mode\":\"auto\"},\"uuid\":\"db-1\",\"version\":\"1\"}}");
        if (request.Method == HttpMethod.Delete)
            return Response(HttpStatusCode.OK, "{\"success\":true,\"result\":null}");
        if (request.Method == HttpMethod.Post)
            return Response(HttpStatusCode.OK, "{\"success\":true,\"result\":{\"name\":\"created\",\"uuid\":\"db-new\",\"version\":\"1\"}}");
        if (request.Method == HttpMethod.Put)
            return Response(HttpStatusCode.OK, "{\"success\":true,\"result\":{\"name\":\"updated\",\"uuid\":\"db-1\",\"version\":\"2\"}}");
        if (request.Method == HttpMethod.Patch)
            return Response(HttpStatusCode.OK, "{\"success\":true,\"result\":{\"name\":\"patched\",\"uuid\":\"db-1\",\"version\":\"3\"}}");
        return Response(HttpStatusCode.NotFound, "{\"success\":false,\"errors\":[{\"code\":404,\"message\":\"not found\"}],\"messages\":[],\"result\":null}", "p33-ray-404");
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
$expectedHostSmaPath = Join-Path $PSHOME 'System.Management.Automation.dll'
if ([IO.Path]::GetFullPath($hostSmaPath) -ne [IO.Path]::GetFullPath($expectedHostSmaPath)) {
    throw "PowerShell runtime SMA was not loaded from the current host: $hostSmaPath"
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

foreach ($name in @('Get-CfD1Database','New-CfD1Database','Remove-CfD1Database','Set-CfD1Database')) {
    $command = Get-Command $name -ErrorAction Stop
    Assert-True ($command.CommandType -eq 'Cmdlet') "D1 public command '$name' is not a cmdlet."
    Assert-True (@(Get-Command $name -All | Where-Object CommandType -eq 'Function').Count -eq 0) "D1 command '$name' is shadowed by a function."
}
$getCommand = Get-Command Get-CfD1Database
$newCommand = Get-Command New-CfD1Database
$removeCommand = Get-Command Remove-CfD1Database
$setCommand = Get-Command Set-CfD1Database
Assert-True (@($getCommand.ParameterSets.Name) -contains 'Get' -and @($getCommand.ParameterSets.Name) -contains 'List') 'D1 Get parameter sets are incomplete.'
Assert-True (@($setCommand.ParameterSets.Name) -contains 'Update' -and @($setCommand.ParameterSets.Name) -contains 'PartialUpdate') 'D1 Set parameter sets are not disambiguated.'
Assert-True ($getCommand.OutputType.Type.FullName -contains 'Cloudflare.PowerShell.CfD1Database') 'D1 Get output is not typed.'
Assert-True ($newCommand.OutputType.Type.FullName -contains 'Cloudflare.PowerShell.CfD1Database') 'D1 New output is not typed.'
Assert-True (@($removeCommand.OutputType).Count -eq 0) 'D1 Remove incorrectly advertises output.'
Assert-True ([System.Management.Automation.CommandMetadata]::new($newCommand).SupportsShouldProcess) 'D1 New ShouldProcess metadata is missing.'
Assert-True ([System.Management.Automation.CommandMetadata]::new($removeCommand).SupportsShouldProcess) 'D1 Remove ShouldProcess metadata is missing.'
Assert-True ([System.Management.Automation.CommandMetadata]::new($setCommand).SupportsShouldProcess) 'D1 Set ShouldProcess metadata is missing.'
Assert-True ($getCommand.Parameters['DatabaseId'].ParameterType -eq [string]) 'D1 database id was not projected as string.'

$artifact = Get-Content -Raw (Join-Path $ProjectRoot 'artifacts/p3.3/CmdletModel.json') | ConvertFrom-Json
$runtimeOperations = @([Cloudflare.PowerShell.CfD1DatabaseRuntimeMetadata]::Operations)
Assert-True ($runtimeOperations.Count -eq 6) 'D1 runtime metadata does not contain six operations.'
Assert-True ((@($runtimeOperations | ForEach-Object OperationId | Sort-Object) -join '|') -eq (@($artifact.cmdlets | ForEach-Object operations | ForEach-Object operationId | Sort-Object) -join '|')) 'D1 runtime operation ids drifted from canonical artifact.'
Write-Output 'PASS P3.3 D1 generated cmdlet metadata and runtime parity'

$base = @{ BaseUrl = 'https://mock.test/client/v4/'; Token = 'token'; Handler = [P33D1MockHandler]::new() }
[P33D1MockHandler]::Reset()
$list = @(& $getCommand -AccountId account -PerPage 1 @base)
Assert-True ($list.Count -eq 1 -and $list[0] -is [Cloudflare.PowerShell.CfD1Database] -and $list[0].Name -eq 'demo') 'D1 list did not emit typed output.'
Assert-True ([P33D1MockHandler]::Requests.Count -eq 2) 'D1 list did not use shared pagination.'
Assert-True ([P33D1MockHandler]::Requests[0].Method -eq [System.Net.Http.HttpMethod]::Get -and [P33D1MockHandler]::Requests[0].RequestUri.AbsolutePath -eq '/client/v4/accounts/account/d1/database') 'D1 list method/path drifted.'
Assert-True ([P33D1MockHandler]::Requests[0].RequestUri.Query -match 'page=1' -and [P33D1MockHandler]::Requests[0].RequestUri.Query -match 'per_page=1') 'D1 list pagination query drifted.'
Assert-True ([P33D1MockHandler]::Requests[0].Headers.Authorization.ToString() -eq 'Bearer token') 'D1 list authentication header is missing.'
Write-Output 'PASS P3.3 D1 list paging, account path, auth, and typed output'

[P33D1MockHandler]::Reset()
$database = & $getCommand -AccountId account -DatabaseId db-1 -Fields @('uuid','name') @base
Assert-True ($database.Uuid -eq 'db-1' -and $database.ReadReplication.Mode -eq 'auto') 'D1 get typed response did not deserialize.'
Assert-True ([P33D1MockHandler]::Requests[0].RequestUri.AbsolutePath -eq '/client/v4/accounts/account/d1/database/db-1' -and [P33D1MockHandler]::Requests[0].RequestUri.Query -match 'fields=uuid' -and [P33D1MockHandler]::Requests[0].RequestUri.Query -match 'fields=name') 'D1 get request binding drifted.'
Write-Output 'PASS P3.3 D1 get and query binding'

$createBody = [Cloudflare.PowerShell.CfD1DatabaseCreateRequest]::new()
$createBody.Name = 'newdb'
$createBody.Jurisdiction = 'us'
$createBody.ReadReplication = [Cloudflare.PowerShell.CfD1ReadReplicationDetails]::new()
$createBody.ReadReplication.Mode = 'auto'
[P33D1MockHandler]::Reset()
$created = & $newCommand -AccountId account -Database $createBody @base -Confirm:$false
$createJson = [System.Text.Json.Nodes.JsonNode]::Parse([P33D1MockHandler]::Bodies[0])
Assert-True ($created.Uuid -eq 'db-new' -and [P33D1MockHandler]::Requests[0].Method -eq [System.Net.Http.HttpMethod]::Post) 'D1 create method or typed output drifted.'
Assert-True ($createJson['name'].ToString() -eq 'newdb' -and $createJson['jurisdiction'].ToString() -eq 'us' -and $createJson['read_replication']['mode'].ToString() -eq 'auto') 'D1 create JSON body drifted.'
Write-Output 'PASS P3.3 D1 create JSON body and typed output'

[P33D1MockHandler]::Reset()
& $newCommand -AccountId account -Database $createBody @base -WhatIf
Assert-True ([P33D1MockHandler]::Requests.Count -eq 0) 'D1 create WhatIf sent an HTTP request.'

$updateBody = [Cloudflare.PowerShell.CfD1DatabaseUpdateRequest]::new()
$updateBody.ReadReplication = [Cloudflare.PowerShell.CfD1ReadReplicationDetails]::new()
$updateBody.ReadReplication.Mode = 'disabled'
[P33D1MockHandler]::Reset()
$updated = & $setCommand -AccountId account -DatabaseId db-1 -Database $updateBody @base -Confirm:$false
Assert-True ($updated.Name -eq 'updated' -and [P33D1MockHandler]::Requests[0].Method -eq [System.Net.Http.HttpMethod]::Put -and [P33D1MockHandler]::Bodies[0] -match 'read_replication') 'D1 PUT body dispatch drifted.'

$partialBody = [Cloudflare.PowerShell.CfD1DatabasePartialUpdateRequest]::new()
[P33D1MockHandler]::Reset()
$patched = & $setCommand -AccountId account -DatabaseId db-1 -PartialDatabase $partialBody @base -Confirm:$false
$patchJson = [System.Text.Json.Nodes.JsonNode]::Parse([P33D1MockHandler]::Bodies[0])
Assert-True ($patched.Name -eq 'patched' -and [P33D1MockHandler]::Requests[0].Method -eq [System.Net.Http.HttpMethod]::Patch -and $patchJson.GetValueKind().ToString() -eq 'Object') 'D1 PATCH body dispatch drifted.'
Write-Output 'PASS P3.3 D1 PUT/PATCH body presence and typed output'

[P33D1MockHandler]::Reset()
$removed = @(& $removeCommand -AccountId account -DatabaseId db-1 @base -Confirm:$false)
Assert-True ($removed.Count -eq 0 -and [P33D1MockHandler]::Requests[0].Method -eq [System.Net.Http.HttpMethod]::Delete -and [P33D1MockHandler]::Bodies[0] -eq '') 'D1 delete output or request body drifted.'
Write-Output 'PASS P3.3 D1 delete and no-output contract'

[P33D1MockHandler]::Reset()
[P33D1MockHandler]::FailMode = 'error'
try {
    & $getCommand -AccountId account -Name fail @base -ErrorAction Stop | Out-Null
    throw 'Expected D1 generated error.'
}
catch {
    $exception = $_.Exception
    while ($exception -and $exception -isnot [Cloudflare.PowerShell.CloudflareApiException] -and $exception.InnerException) { $exception = $exception.InnerException }
    Assert-True ($exception -is [Cloudflare.PowerShell.CloudflareApiException] -and $exception.RequestId -eq 'p33-ray-1' -and $exception.Errors[0].Code -eq 1001) 'D1 error metadata did not retain shared runtime error mapping.'
}
Write-Output 'PASS P3.3 D1 error mapping'
}
finally {
    Remove-Module -Name 'Cloudflare.PowerShell' -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $p33StagingRoot) {
        try {
            Remove-Item -LiteralPath $p33StagingRoot -Recurse -Force -ErrorAction Stop
        }
        catch {
            # PowerShell keeps a loaded module assembly locked until this
            # process exits. Defer deletion to a hidden helper that waits for
            # this exact test process, so the staging directory is still
            # removed without touching the repository module.
            $cleanupPath = $p33StagingRoot.Replace("'", "''")
            $cleanupCommand = "while (Get-Process -Id $PID -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 250 }; Remove-Item -LiteralPath '$cleanupPath' -Recurse -Force -ErrorAction SilentlyContinue"
            Start-Process -FilePath (Get-Command pwsh).Source -WindowStyle Hidden -ArgumentList @('-NoLogo', '-NoProfile', '-Command', $cleanupCommand) | Out-Null
        }
    }
}
