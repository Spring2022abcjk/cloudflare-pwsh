[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ModulePath,
    [switch]$Child
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ModulePath).Path)
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repoPrefix = $repoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar

if (-not $Child) {
    $workingDirectory = Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p34-smoke-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $workingDirectory | Out-Null
    try {
        & pwsh -NoLogo -NoProfile -WorkingDirectory $workingDirectory -File $PSCommandPath -ModulePath $modulePath -Child | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "P3.4 package smoke child process failed with exit code $LASTEXITCODE." }
        Write-Output 'PASS P3.4 package smoke isolated child process'
    } finally {
        if (Test-Path -LiteralPath $workingDirectory) { Remove-Item -LiteralPath $workingDirectory -Recurse -Force -ErrorAction SilentlyContinue }
    }
    return
}

$currentDirectory = [IO.Path]::GetFullPath((Get-Location).Path)
if ($currentDirectory.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Package smoke child working directory is inside the repository: $currentDirectory" }
$modulePathEntries = @($env:PSModulePath -split [IO.Path]::PathSeparator | Where-Object {
    if ([string]::IsNullOrWhiteSpace($_)) { return $false }
    $candidate = [IO.Path]::GetFullPath($_)
    return -not $candidate.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)
})
$env:PSModulePath = [string]::Join([IO.Path]::PathSeparator, $modulePathEntries)
if (@(Get-Module -Name Cloudflare.PowerShell).Count -ne 0) { throw 'Package smoke child already has Cloudflare.PowerShell loaded.' }
$sourcePayloadRoots = @(
    [IO.Path]::GetFullPath((Join-Path $repoRoot 'src')),
    [IO.Path]::GetFullPath((Join-Path $repoRoot 'module')),
    [IO.Path]::GetFullPath((Join-Path $repoRoot 'bin'))
) | ForEach-Object { $_.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar }
$preloadedSourceAssemblies = @([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object {
    if ([string]::IsNullOrWhiteSpace($_.Location)) { return $false }
    $location = [IO.Path]::GetFullPath($_.Location)
    @($sourcePayloadRoots | Where-Object { $location.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
})
if ($preloadedSourceAssemblies.Count -ne 0) { throw 'Package smoke child preloaded an assembly from the repository source payload.' }

$manifestPath = Join-Path $modulePath 'Cloudflare.PowerShell.psd1'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Package module manifest is missing: $manifestPath" }
$manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
$expectedFiles = @('Cloudflare.PowerShell-help.xml', 'Cloudflare.PowerShell.psd1', 'Cloudflare.PowerShell.psm1', 'Cloudflare.PowerShell.dll')
$actualFiles = @(Get-ChildItem -LiteralPath $modulePath -File | ForEach-Object Name | Sort-Object)
if (($actualFiles -join '|') -cne (($expectedFiles | Sort-Object) -join '|')) { throw "Package module has unexpected files: $($actualFiles -join ', ')" }
if ([string]$manifest.ModuleVersion -ne '0.1.0') { throw "Package smoke expected module version 0.1.0; found '$($manifest.ModuleVersion)'." }
if ([string]$manifest.PowerShellVersion -ne '7.6') { throw "Package smoke expected PowerShellVersion 7.6; found '$($manifest.PowerShellVersion)'." }
if ($PSVersionTable.PSVersion -lt [version]'7.6.0') { throw "Package smoke requires PowerShell 7.6+; current host is $($PSVersionTable.PSVersion)." }

Import-Module -Name $manifestPath -Force
$loaded = Get-Module -Name Cloudflare.PowerShell | Where-Object { [IO.Path]::GetFullPath($_.ModuleBase) -ceq [IO.Path]::GetFullPath($modulePath) } | Select-Object -First 1
if ($null -eq $loaded) { throw 'Package module was not loaded from the candidate module path.' }
$expectedCmdlets = @('Get-CfZone', 'Get-CfDnsRecord', 'New-CfDnsRecord', 'Remove-CfDnsRecord', 'Set-CfDnsRecord')
foreach ($name in $expectedCmdlets) {
    $command = Get-Command $name -ErrorAction Stop
    if ($command.CommandType -ne 'Cmdlet') { throw "Package command '$name' did not load as a cmdlet." }
}
$actualCmdlets = @(Get-Command -Module $loaded.Name -CommandType Cmdlet | ForEach-Object Name | Sort-Object)
if (($actualCmdlets -join '|') -cne (($expectedCmdlets | Sort-Object) -join '|')) {
    throw "Package public cmdlet surface mismatch. Expected: $($expectedCmdlets -join ', '); actual: $($actualCmdlets -join ', ')."
}
foreach ($name in @('Get-CfD1Database', 'Get-CfHealthCheck')) {
    if ($null -ne (Get-Command -Module $loaded.Name -Name $name -ErrorAction SilentlyContinue)) {
        throw "Bounded test-only cmdlet '$name' was exported by the package candidate."
    }
}
$help = Get-Help Get-CfDnsRecord -ErrorAction Stop
if ([string]::IsNullOrWhiteSpace([string]$help.Synopsis) -and [string]::IsNullOrWhiteSpace([string]$help.Description)) { throw 'Package help discovery returned no representative help text.' }
$assembly = [Cloudflare.PowerShell.CfDnsRecordRuntimeMetadata].Assembly
$expectedAssemblyPath = Join-Path $modulePath 'Cloudflare.PowerShell.dll'
if ([IO.Path]::GetFullPath($assembly.Location) -cne [IO.Path]::GetFullPath($expectedAssemblyPath)) { throw "Generated metadata assembly was not loaded from the package candidate: $($assembly.Location)" }
if ([Cloudflare.PowerShell.CfDnsRecordRuntimeMetadata]::Operations.Count -ne 6) { throw 'Package generated runtime metadata did not load the six DNS operations.' }

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public sealed class P34PackageMockHandler : HttpMessageHandler
{
    public static List<HttpRequestMessage> Requests { get; } = new();
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Requests.Add(request);
        var pageTwo = request.RequestUri?.Query.Contains("page=2", StringComparison.Ordinal) == true;
        var result = pageTwo ? "[]" : "[{\"id\":\"candidate-record\",\"name\":\"example.com\",\"type\":\"A\",\"content\":\"198.51.100.4\"}]";
        var body = "{\"success\":true,\"result\":" + result + ",\"result_info\":{\"page\":1,\"total_pages\":2}}";
        return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(body, Encoding.UTF8, "application/json") });
    }
}
'@
$handler = [P34PackageMockHandler]::new()
$records = @(Get-CfDnsRecord -ZoneId zone -BaseUrl 'https://mock.test/client/v4/' -Token token -Handler $handler)
if ($records.Count -ne 1 -or [string]$records[0].Id -cne 'candidate-record') { throw 'Package mock smoke did not execute the staged generated cmdlet.' }
if ([P34PackageMockHandler]::Requests.Count -ne 2) { throw 'Package mock smoke did not exercise the shared pagination path.' }
if ([P34PackageMockHandler]::Requests[0].RequestUri.AbsolutePath -cne '/client/v4/zones/zone/dns_records') { throw 'Package mock smoke sent an unexpected request path.' }
Write-Output "PASS P3.4 package import commands help metadata assembly and mock smoke module=$modulePath"
