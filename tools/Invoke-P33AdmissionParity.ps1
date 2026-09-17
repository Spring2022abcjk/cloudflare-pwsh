[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$PolicyPath = (Join-Path $ProjectRoot 'overrides/public-admission-policy.json'),
    [string]$AssemblyPath = (Join-Path $ProjectRoot 'src/Cloudflare.PowerShell/bin/Release/net10.0/Cloudflare.PowerShell.dll')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-ConfiguredPath {
    param([Parameter(Mandatory)][string]$Path)
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $script:projectRoot $Path))
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Admission parity input is missing: $Path" }
    return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Get-CmdletNames {
    param([Parameter(Mandatory)][object]$Model)
    $items = if ($null -ne $Model.PSObject.Properties['cmdlets']) { @($Model.cmdlets) } else { @($Model) }
    return @($items | ForEach-Object { [string]$_.cmdletName } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-IdentitySet {
    param([Parameter(Mandatory)][object[]]$Names)
    return @($Names | ForEach-Object { ([string]$_).ToUpperInvariant() } | Sort-Object -Unique)
}

function Assert-ExactSurface {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][object[]]$Expected,
        [Parameter(Mandatory)][object[]]$Actual
    )
    $expectedRaw = @($Expected | ForEach-Object { [string]$_ } | Sort-Object)
    $actualRaw = @($Actual | ForEach-Object { [string]$_ } | Sort-Object)
    if ((Get-IdentitySet $Expected).Count -ne $expectedRaw.Count) { throw "$Label expected surface contains duplicate or case-colliding identities." }
    if ((Get-IdentitySet $Actual).Count -ne $actualRaw.Count) { throw "$Label actual surface contains duplicate or case-colliding identities." }
    $expectedKeys = Get-IdentitySet $Expected
    $actualKeys = Get-IdentitySet $Actual
    if (($expectedKeys -join "`n") -ceq ($actualKeys -join "`n")) { return }
    $missing = @($expectedRaw | Where-Object { $_ -notin $actualRaw })
    $extra = @($actualRaw | Where-Object { $_ -notin $expectedRaw })
    throw "$Label mismatch. Missing: [$($missing -join ', ')]; extra: [$($extra -join ', ')]"
}

function Get-ManifestCmdletNames {
    param([Parameter(Mandatory)][string]$Path)
    $manifest = Import-PowerShellDataFile -LiteralPath $Path
    $names = @($manifest.CmdletsToExport | ForEach-Object { [string]$_ })
    if ($names -contains '*') { throw "Module manifest uses wildcard CmdletsToExport: $Path" }
    return $names
}

function Get-ScriptCmdletNames {
    param([Parameter(Mandatory)][string]$Path)
    $text = Get-Content -Raw -LiteralPath $Path
    $exports = [regex]::Matches($text, '(?is)Export-ModuleMember\s+-Function\s+@\(\s*\)\s+-Cmdlet\s+@\((?<body>.*?)\)')
    if ($exports.Count -ne 1) { throw "Module script does not have one static Export-ModuleMember cmdlet list: $Path" }
    $body = $exports[0].Groups['body'].Value
    $names = [Collections.Generic.List[string]]::new()
    foreach ($match in [regex]::Matches($body, "'([^']+)'") ) { $names.Add($match.Groups[1].Value) }
    foreach ($match in [regex]::Matches($body, '"([^"]+)"') ) { $names.Add($match.Groups[1].Value) }
    return @($names)
}

function Get-GeneratedSourceCmdletNames {
    param([Parameter(Mandatory)][string[]]$Paths)
    $verbMap = @{
        Get = 'Get'
        New = 'New'
        Remove = 'Remove'
        Set = 'Set'
    }
    $names = [Collections.Generic.List[string]]::new()
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Generated public source is missing: $path" }
        $text = Get-Content -Raw -LiteralPath $path
        foreach ($match in [regex]::Matches($text, '\[Cmdlet\(\s*Verbs(?:Common|Data)\.(?<verb>\w+)\s*,\s*"(?<noun>[^"]+)"')) {
            $verb = [string]$match.Groups['verb'].Value
            if (-not $verbMap.ContainsKey($verb)) { throw "Generated public source uses an unsupported PowerShell verb '$verb': $path" }
            $names.Add("$($verbMap[$verb])-$($match.Groups['noun'].Value)")
        }
    }
    return @($names)
}

function Get-HelpCmdletNames {
    param([Parameter(Mandatory)][string]$Path)
    $text = Get-Content -Raw -LiteralPath $Path
    return @([regex]::Matches($text, '<command:name>(?<name>[^<]+)</command:name>') | ForEach-Object { $_.Groups['name'].Value })
}

$script:projectRoot = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
$policyPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $PolicyPath).Path)
$assemblyPath = Resolve-ConfiguredPath $AssemblyPath
$policy = Read-JsonFile $policyPath
if ($policy.automaticAdmission -ne $false) { throw 'Public admission parity requires automaticAdmission=false.' }
if ($null -eq $policy.PSObject.Properties['canonicalSurface']) { throw 'Public admission policy lacks canonicalSurface paths.' }
$surface = $policy.canonicalSurface

$publicArtifactPath = Resolve-ConfiguredPath ([string]$surface.publicCmdletModelPath)
$coveragePath = Resolve-ConfiguredPath ([string]$surface.coverageReportPath)
$p24SurfacePath = Resolve-ConfiguredPath ([string]$surface.p24CompatibilitySurfacePath)
$manifestPath = Resolve-ConfiguredPath ([string]$surface.moduleManifestPath)
$moduleScriptPath = Resolve-ConfiguredPath ([string]$surface.moduleScriptPath)
$helpPath = Resolve-ConfiguredPath ([string]$surface.generatedHelpPath)
$sourcePaths = @($surface.generatedPublicSourcePaths | ForEach-Object { Resolve-ConfiguredPath ([string]$_) })

$publicArtifact = Read-JsonFile $publicArtifactPath
$admitted = Get-CmdletNames $publicArtifact
if ($admitted.Count -eq 0) { throw 'Canonical public CmdletModel admits no commands.' }

$coverage = Read-JsonFile $coveragePath
$coveragePublic = @($coverage.operations | Where-Object { [bool]$_.currentPublicSurface } | ForEach-Object currentPublicCmdlet | Sort-Object -Unique)
Assert-ExactSurface 'coverage public classification ↔ canonical admission' $admitted $coveragePublic

$p24Surface = Read-JsonFile $p24SurfacePath
Assert-ExactSurface 'P2.4 compatibility surface ↔ canonical admission' $admitted (Get-CmdletNames $p24Surface)
Assert-ExactSurface 'generated public source ↔ canonical admission' $admitted (Get-GeneratedSourceCmdletNames $sourcePaths)
Assert-ExactSurface 'module manifest exports ↔ canonical admission' $admitted (Get-ManifestCmdletNames $manifestPath)
Assert-ExactSurface 'module script exports ↔ canonical admission' $admitted (Get-ScriptCmdletNames $moduleScriptPath)
Assert-ExactSurface 'generated help commands ↔ canonical admission' $admitted (Get-HelpCmdletNames $helpPath)

if (-not (Test-Path -LiteralPath $assemblyPath -PathType Leaf)) { throw "Runtime assembly is missing: $assemblyPath" }
$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ('cloudflare-p33-admission-parity-' + [guid]::NewGuid().ToString('N'))
$stagedModule = Join-Path $stagingRoot 'Cloudflare.PowerShell'
$runtimeModule = $null
try {
    New-Item -ItemType Directory -Force -Path $stagedModule | Out-Null
    Copy-Item -LiteralPath $manifestPath -Destination $stagedModule -Force
    Copy-Item -LiteralPath $moduleScriptPath -Destination $stagedModule -Force
    Copy-Item -LiteralPath $helpPath -Destination $stagedModule -Force
    Copy-Item -LiteralPath $assemblyPath -Destination (Join-Path $stagedModule 'Cloudflare.PowerShell.dll') -Force
    $runtimeModule = Import-Module (Join-Path $stagedModule 'Cloudflare.PowerShell.psd1') -Force -PassThru
    $runtimeExports = @($runtimeModule.ExportedCmdlets.Keys)
    $runtimeCommands = @(Get-Command -Module $runtimeModule.Name -CommandType Cmdlet | ForEach-Object Name)
    Assert-ExactSurface 'runtime module exports ↔ canonical admission' $admitted $runtimeExports
    Assert-ExactSurface 'Get-Command module surface ↔ canonical admission' $admitted $runtimeCommands
}
finally {
    if ($null -ne $runtimeModule) { Remove-Module -ModuleInfo $runtimeModule -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

[ordered]@{
    stage = 'P3.3-public-admission-parity'
    automaticAdmission = [bool]$policy.automaticAdmission
    admittedCmdlets = @($admitted | Sort-Object)
    checkedSurfaces = @('coverage', 'P2.4 compatibility', 'generated public source', 'module manifest', 'module script', 'generated help', 'runtime module', 'Get-Command')
} | ConvertTo-Json -Depth 10
Write-Output 'PASS P3.3 canonical public admission/export/help/runtime parity'
