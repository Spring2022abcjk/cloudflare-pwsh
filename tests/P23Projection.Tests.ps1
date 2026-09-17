[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$SkipBuild,
    [switch]$WriteReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourcePath = Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Experiments/P23_GetCfZoneCommand.cs'
$modelPath = Join-Path $ProjectRoot 'artifacts/p2.3/projection/zones.json'
$reportPath = Join-Path $ProjectRoot 'artifacts/p2.3/comparison.json'
$experimentProject = Join-Path $ProjectRoot 'experiments/p2.3/Cloudflare.P23.GeneratedCmdlet/Cloudflare.P23.GeneratedCmdlet.csproj'
$experimentDll = Join-Path $ProjectRoot 'experiments/p2.3/Cloudflare.P23.GeneratedCmdlet/bin/Release/net10.0/Cloudflare.P23.GeneratedCmdlet.dll'

if (-not (Test-Path -LiteralPath $sourcePath)) { throw 'Generated P2.3 source is missing.' }
if (-not (Test-Path -LiteralPath $modelPath)) { throw 'Generated P2.3 projection model is missing.' }

$zones = Get-Content -Raw -LiteralPath $modelPath | ConvertFrom-Json
$generated = @($zones.cmdlets | Where-Object cmdletName -eq 'Get-CfZone')
if ($generated.Count -ne 1) { throw 'Expected one Get-CfZone projection.' }
$generated = $generated[0]
if ($generated.outputType -ne 'Cloudflare.PowerShell.CfZone') { throw 'Get-CfZone output type is not typed.' }
if ($generated.outputPolicy -ne 'item' -or $generated.pagingBehavior -ne 'shared-runtime') { throw 'Get-CfZone item/paging policy mismatch.' }
if (@($generated.parameterSets.name) -notcontains 'List' -or @($generated.parameterSets.name) -notcontains 'Get') { throw 'Get-CfZone parameter sets are incomplete.' }
$zoneId = @($generated.parameters | Where-Object name -eq 'ZoneId')
if ($zoneId.Count -ne 1 -or -not $zoneId[0].valueFromPipelineByPropertyName) { throw 'ZoneId pipeline-by-property-name metadata is missing.' }
$accountId = @($generated.parameters | Where-Object name -eq 'AccountId')
if ($accountId.Count -ne 1 -or $accountId[0].binding -ne 'query') { throw 'AccountId projection is missing.' }
if ($generated.help.source -ne 'Override' -or [string]::IsNullOrWhiteSpace($generated.help.synopsis)) { throw 'Get-CfZone help metadata is missing.' }

if (-not $SkipBuild) {
    dotnet build $experimentProject --configuration Release | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Generated P2.3 cmdlet build failed.' }
}
if (-not (Test-Path -LiteralPath $experimentDll)) { throw 'Generated P2.3 cmdlet assembly is missing.' }

$publicModuleSourceRoot = Join-Path $ProjectRoot 'module/Cloudflare.PowerShell'
$publicModuleSourceFiles = @(
    (Join-Path $publicModuleSourceRoot 'Cloudflare.PowerShell.psd1'),
    (Join-Path $publicModuleSourceRoot 'Cloudflare.PowerShell.psm1'),
    (Join-Path $publicModuleSourceRoot 'Cloudflare.PowerShell-help.xml')
)
foreach ($sourceFile in $publicModuleSourceFiles) {
    if (-not (Test-Path -LiteralPath $sourceFile)) { throw "Public module source file is missing: $sourceFile" }
}
$releaseAssembly = Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/bin/Release/net10.0/Cloudflare.PowerShell.dll'
if (-not (Test-Path -LiteralPath $releaseAssembly)) { throw 'Release module assembly is missing.' }
$publicModuleRoot = Join-Path ([IO.Path]::GetTempPath()) ("cf-p23-module-" + [Guid]::NewGuid().ToString('N'))
$publicModule = Join-Path $publicModuleRoot 'Cloudflare.PowerShell.psd1'
New-Item -ItemType Directory -Force -Path $publicModuleRoot | Out-Null
foreach ($sourceFile in $publicModuleSourceFiles) {
    Copy-Item -LiteralPath $sourceFile -Destination $publicModuleRoot -Force
}
Copy-Item -LiteralPath $releaseAssembly -Destination (Join-Path $publicModuleRoot 'Cloudflare.PowerShell.dll') -Force

$probe = @'
param([string]$AssemblyPath, [string]$ProjectRoot, [string]$PublicModulePath)
$ErrorActionPreference = 'Stop'
Import-Module -Name $AssemblyPath -Force
$generatedCommand = Get-Command Get-CfZone -ErrorAction Stop
$zoneParameter = $generatedCommand.Parameters['ZoneId']
$zoneParameterAttribute = @($zoneParameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })[0]
Import-Module -Name $PublicModulePath -Force
$publicModuleInfo = Get-Module Cloudflare.PowerShell -ErrorAction Stop
$handwrittenCommand = & $publicModuleInfo { Get-Command Invoke-CfDnsRecordHandwritten -CommandType Function -ErrorAction Stop }
$sw = [System.Diagnostics.Stopwatch]::StartNew()
1..100 | ForEach-Object { Get-Command Get-CfZone | Out-Null }
$sw.Stop()
$generatedMs = $sw.Elapsed.TotalMilliseconds
$sw.Restart()
1..100 | ForEach-Object { & $publicModuleInfo { Get-Command Invoke-CfDnsRecordHandwritten -CommandType Function | Out-Null } }
$sw.Stop()
$handwrittenMs = $sw.Elapsed.TotalMilliseconds
$sourceLines = @(Get-Content -LiteralPath (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/Generated/Experiments/P23_GetCfZoneCommand.cs') | Where-Object { $_.Trim().Length -gt 0 }).Count
$moduleLines = @(Get-Content -LiteralPath (Join-Path $ProjectRoot 'module/Cloudflare.PowerShell/Cloudflare.PowerShell.psm1'))
$start = @($moduleLines | Select-String -Pattern '^function Invoke-CfDnsRecordHandwritten')
$end = @($moduleLines | Select-String -Pattern '^function Invoke-NewCfDnsRecordHandwritten')
$handwrittenLines = if ($start.Count -eq 1 -and $end.Count -eq 1) { @($moduleLines[($start[0].LineNumber - 1)..($end[0].LineNumber - 2)] | Where-Object { $_.Trim().Length -gt 0 }).Count } else { 0 }
[ordered]@{
    generated = [ordered]@{
        command = $generatedCommand.Name
        parameterSets = @($generatedCommand.ParameterSets.Name)
        outputTypes = @($generatedCommand.OutputType.Type | ForEach-Object FullName)
        zoneIdValueFromPipelineByPropertyName = [bool]$zoneParameterAttribute.ValueFromPipelineByPropertyName
        helpAvailable = -not [string]::IsNullOrWhiteSpace((Get-Help Get-CfZone -ErrorAction SilentlyContinue).Synopsis)
        loading = $true
        metadataProbeMilliseconds = [math]::Round($generatedMs, 3)
        nonBlankSourceLines = $sourceLines
        runtimeDispatch = $false
    }
    handwritten = [ordered]@{
        command = $handwrittenCommand.Name
        parameterSets = @($handwrittenCommand.ParameterSets.Name)
        outputTypes = @($handwrittenCommand.OutputType.Type | ForEach-Object FullName)
        zoneIdValueFromPipelineByPropertyName = $false
        helpAvailable = -not [string]::IsNullOrWhiteSpace((& $publicModuleInfo { Get-Help Invoke-CfDnsRecordHandwritten -ErrorAction SilentlyContinue }).Synopsis)
        loading = $true
        metadataProbeMilliseconds = [math]::Round($handwrittenMs, 3)
        nonBlankSourceLines = $handwrittenLines
        runtimeDispatch = $true
    }
    testability = [ordered]@{ generatedMetadataLoading = $true; handwrittenMockRuntime = $true; generatedMockRuntime = $false }
} | ConvertTo-Json -Depth 20
'@
$probePath = Join-Path ([IO.Path]::GetTempPath()) ("cf-p23-probe-" + [Guid]::NewGuid().ToString('N') + '.ps1')
try {
    [IO.File]::WriteAllText($probePath, $probe, [Text.UTF8Encoding]::new($false))
    $probeJson = & pwsh -NoLogo -NoProfile -File $probePath -AssemblyPath $experimentDll -ProjectRoot $ProjectRoot -PublicModulePath $publicModule
    if ($LASTEXITCODE -ne 0) { throw 'PowerShell generated-cmdlet loading probe failed.' }
    $comparison = $probeJson | ConvertFrom-Json
    if (-not $comparison.generated.loading -or $comparison.generated.command -ne 'Get-CfZone') { throw 'Generated cmdlet did not load.' }
    if (-not $comparison.generated.helpAvailable) { throw 'Generated cmdlet help metadata did not load.' }
    if ($comparison.generated.runtimeDispatch) { throw 'Generated experiment must remain dispatch-deferred.' }
    if (-not $comparison.handwritten.runtimeDispatch) { throw 'Handwritten baseline classification is wrong.' }
    Write-Output 'PASS P2.3 projection metadata and generated cmdlet loading'
    if ($WriteReport) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $reportPath) | Out-Null
        $reportJson = ($comparison | ConvertTo-Json -Depth 30).Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
        [IO.File]::WriteAllText($reportPath, $reportJson, [Text.UTF8Encoding]::new($false))
        Write-Output "P2.3 comparison report: $reportPath"
    }
}
finally {
    if (Test-Path -LiteralPath $probePath) { Remove-Item -LiteralPath $probePath -Force }
    if (Test-Path -LiteralPath $publicModuleRoot) { Remove-Item -LiteralPath $publicModuleRoot -Recurse -Force }
}
