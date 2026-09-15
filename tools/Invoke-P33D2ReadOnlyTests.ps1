[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p33-d2-readonly-'+[guid]::NewGuid().ToString('N'))
$initial=$null; $failure=$null
. (Join-Path $root 'tools/ReadOnlyStaging.ps1') -Library
. (Join-Path $root 'tools/P33ReadOnlyStaging.ps1') -Library
function Status { $lines=@(& git -C $root status --short); if($LASTEXITCODE-ne 0){throw 'Could not read worktree status.'}; ($lines|ForEach-Object{[string]$_})-join "`n" }
function Run { param([string]$File,[string[]]$CommandArgs,[string]$Label); & $File @CommandArgs|Out-Host; if($LASTEXITCODE-ne 0){throw "$Label failed with exit code $LASTEXITCODE."} }
function HashParity { param([string[]]$Paths); foreach($relative in $Paths){$a=Join-Path $root $relative;$b=Join-Path $temporary $relative;if(-not(Test-Path -LiteralPath $a -PathType Leaf)-or-not(Test-Path -LiteralPath $b -PathType Leaf)){throw "D2 reproduction file is missing: $relative"};if((Get-FileHash -Algorithm SHA256 $a).Hash -cne (Get-FileHash -Algorithm SHA256 $b).Hash){throw "D2 isolated reproduction drifted: $relative"}} }
try{
    $initial=Status; New-Item -ItemType Directory -Force -Path $temporary|Out-Null
    $required=@(Get-P33D2RequiredInputPaths -ProjectRoot $root); Copy-ReadOnlyStagingFiles -SourceRoot $root -DestinationRoot $temporary -RelativePaths $required; [void](Assert-ReadOnlyStagingInputContract -Root $temporary -ExpectedRelativePaths $required); $diag=Get-ReadOnlyStagingDiagnostics -Root $temporary
    Write-Output "PASS P3.3 D2 explicit isolated staging contract files=$($diag.FileCount), bytes=$($diag.TotalBytes); no VCS/build/cache/log/temp inputs"
    $d1Fixture=Join-Path $temporary 'tools/Generate-P33D1Fixture.ps1';$d1Projector=Join-Path $temporary 'tools/Project-P33D1Projection.ps1';$d1Generator=Join-Path $temporary 'tools/Generate-P33D1Source.ps1'
    Run pwsh @('-NoLogo','-NoProfile','-File',$d1Fixture,'-ProjectRoot',$temporary) 'isolated D1 fixture generation'
    Run pwsh @('-NoLogo','-NoProfile','-File',$d1Projector,'-ProjectRoot',$temporary) 'isolated D1 projection'
    Run pwsh @('-NoLogo','-NoProfile','-File',$d1Generator,'-ProjectRoot',$temporary) 'isolated D1 source generation'
    $d2Fixture=Join-Path $temporary 'tools/Generate-P33D2HealthchecksFixture.ps1';$d2Projector=Join-Path $temporary 'tools/Project-P33D2Projection.ps1';$d2Generator=Join-Path $temporary 'tools/Generate-P33D2Source.ps1'
    Run pwsh @('-NoLogo','-NoProfile','-File',$d2Fixture,'-ProjectRoot',$temporary) 'isolated D2 fixture generation'
    Run pwsh @('-NoLogo','-NoProfile','-File',$d2Projector,'-ProjectRoot',$temporary) 'isolated D2 projection'
    Run pwsh @('-NoLogo','-NoProfile','-File',$d2Generator,'-ProjectRoot',$temporary) 'isolated D2 source generation'
    Run pwsh @('-NoLogo','-NoProfile','-File',$d2Generator,'-ProjectRoot',$temporary,'-ValidateOnly') 'isolated D2 source/model freshness validation'
    Run dotnet @('build',(Join-Path $temporary 'Cloudflare.P1.sln'),'--configuration','Release','--nologo') 'isolated Release build'
    Run pwsh @('-NoLogo','-NoProfile','-File',(Join-Path $temporary 'tests/P33D1Smoke.ps1'),'-ProjectRoot',$temporary) 'isolated D1 mock/runtime smoke'
    Run pwsh @('-NoLogo','-NoProfile','-File',(Join-Path $temporary 'tools/Invoke-P33D1Compatibility.ps1'),'-ProjectRoot',$temporary) 'isolated D1 compatibility'
    Run pwsh @('-NoLogo','-NoProfile','-File',(Join-Path $temporary 'tools/Invoke-P33D2Compatibility.ps1'),'-ProjectRoot',$temporary) 'isolated D2 compatibility'
    Run pwsh @('-NoLogo','-NoProfile','-File',(Join-Path $temporary 'tests/P33D1Projection.Tests.ps1'),'-ProjectRoot',$temporary) 'isolated D1 projection tests'
    Run pwsh @('-NoLogo','-NoProfile','-File',(Join-Path $temporary 'tests/P33D2Projection.Tests.ps1'),'-ProjectRoot',$temporary) 'isolated D2 projection tests'
    Run pwsh @('-NoLogo','-NoProfile','-File',(Join-Path $temporary 'tests/P33D2Smoke.ps1'),'-ProjectRoot',$temporary) 'isolated D2 mock/runtime smoke'
    Run pwsh @('-NoLogo','-NoProfile','-File',(Join-Path $temporary 'tests/P33Coverage.Tests.ps1'),'-ProjectRoot',$temporary) 'isolated P3.3 coverage contract'
    HashParity @('fixtures/p3.3/d1-database/document.json','artifacts/p3.3/CmdletModel.json','fixtures/p3.3/healthchecks/document.json','artifacts/p3.3/healthchecks/CmdletModel.json','artifacts/p3.3/healthchecks/d2-projection-compatibility.json','src/Cloudflare.PowerShell/Generated/Cmdlets/P33D1DatabaseCmdlets.cs','src/Cloudflare.PowerShell/Generated/Cmdlets/P33D2HealthchecksCmdlets.cs','src/Cloudflare.PowerShell/Generated/Metadata/CfHealthCheckOperationMetadata.cs','src/Cloudflare.PowerShell/Generated/Metadata/CfHealthCheckRuntimeMetadata.cs','src/Cloudflare.PowerShell/Generated/Models/CfHealthCheck.cs','src/Cloudflare.PowerShell/Generated/Models/CfHealthCheckRequest.cs','src/Cloudflare.PowerShell/Generated/Models/CfHealthCheckHttpConfig.cs','src/Cloudflare.PowerShell/Generated/Models/CfHealthCheckTcpConfig.cs')
    Write-Output 'PASS P3.3 D2 isolated fixture/projection/source/model/runtime/compatibility reproduction; current worktree was not the build target.'
}catch{$failure=$_.Exception}finally{
    if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue}
    try{$after=Status;if($null-ne$initial-and$after-cne$initial){$message="D2 read-only acceptance changed the worktree unexpectedly. Before:`n$initial`nAfter:`n$after";if($null-eq$failure){$failure=[InvalidOperationException]::new($message)}else{Write-Error $message}}}catch{if($null-eq$failure){$failure=$_.Exception}else{Write-Error $_.Exception.Message}}
}
if($null-ne$failure){Write-Error "P3.3 D2 independent read-only acceptance failed: $($failure.Message)";exit 1}
