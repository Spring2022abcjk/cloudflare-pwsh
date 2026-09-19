[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)

function Assert-P42 {
    param([bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

try {
    $workflowFiles = @(Get-ChildItem -LiteralPath (Join-Path $root '.github/workflows') -Filter '*.yml' -File)
    Assert-P42 ($workflowFiles.Count -gt 0) 'P4.2 security review found no workflow files.'
    foreach ($workflowFile in $workflowFiles) {
        $workflow = Get-Content -Raw -LiteralPath $workflowFile.FullName
        Assert-P42 ($workflow -notmatch '(?m)^\s*pull_request_target\s*:') "Unsafe pull_request_target trigger found in $($workflowFile.Name)."
        Assert-P42 ($workflow -match '(?m)^permissions:\s*\r?\n\s+contents:\s+read\s*$') "Workflow $($workflowFile.Name) must grant only contents: read at the top level."
        Assert-P42 ($workflow -notmatch '(?im)\b(contents|actions|packages|id-token):\s*write\b') "Workflow $($workflowFile.Name) contains an unexpected write permission."
        Assert-P42 ($workflow -notmatch '(?i)\b(secrets\.|CF_API_TOKEN|CLOUDFLARE_API_TOKEN|NUGET_API_KEY|NUGET_AUTH_TOKEN|GALLERY_API_KEY|SIGNING_KEY)\b') "Workflow $($workflowFile.Name) references a release or live-account secret."
        $externalUses = [regex]::Matches($workflow, '(?m)^\s*uses:\s*actions/[^@\s]+@(?<ref>[^\s#]+)(?<comment>\s+#\s+v[^\r\n]+)?')
        foreach ($match in $externalUses) {
            $ref = [string]$match.Groups['ref'].Value
            Assert-P42 ($ref -cmatch '^[0-9a-f]{40}$') "Action ref '$ref' in $($workflowFile.Name) is not a full lowercase commit SHA."
            Assert-P42 ($match.Groups['comment'].Success -and [string]$match.Groups['comment'].Value -cmatch '#\s+v[0-9]+\.[0-9]+\.[0-9]+') "Pinned action in $($workflowFile.Name) is missing a readable version comment."
        }
        $floating = [regex]::Matches($workflow, '(?m)^\s*uses:\s*actions/[^@\s]+@(?<ref>[^\s#]+)') | Where-Object { [string]$_.Groups['ref'].Value -notmatch '^[0-9a-f]{40}$' }
        Assert-P42 (@($floating).Count -eq 0) "Workflow $($workflowFile.Name) still contains a floating actions/* reference."
        if ($workflowFile.Name -ceq 'p34-ci.yml') {
            Assert-P42 ($workflow -match '(?m)^\s*pull_request\s*:') 'P3.4 CI must retain pull_request coverage.'
            Assert-P42 ($workflow -match '(?m)^\s*workflow_dispatch\s*:') 'P3.4 CI must retain workflow_dispatch coverage.'
            Assert-P42 ($workflow -match 'release-preflight') 'P3.4 CI must run the P4.2 release preflight before packaging.'
            Assert-P42 ($workflow -match '--locked-mode') 'P3.4 CI restore must use NuGet locked mode.'
            $checkoutCount = @([regex]::Matches($workflow, 'actions/checkout@[0-9a-f]{40}')).Count
            $credentialCount = @([regex]::Matches($workflow, 'persist-credentials:\s*false')).Count
            Assert-P42 ($checkoutCount -eq $credentialCount) "P3.4 CI checkout credential persistence is not disabled for every checkout ($checkoutCount/$credentialCount)."
        }
    }

    $action = Get-Content -Raw -LiteralPath (Join-Path $root '.github/actions/p34-windows-baseline/action.yml')
    Assert-P42 ($action -match 'actions/setup-dotnet@[0-9a-f]{40}\s+#\s+v4\.3\.1') 'Composite baseline action is not pinned to the reviewed setup-dotnet commit.'
    Assert-P42 ($action -match 'dotnet-version:\s*10\.0\.400') 'Composite baseline action must install the reviewed .NET SDK feature band.'
    Assert-P42 ($action -match 'powershell-msi-sha256:') 'Composite baseline action must expose the PowerShell MSI hash input.'
    Assert-P42 ($action -match 'Get-FileHash\s+-Algorithm\s+SHA256') 'Composite baseline action must verify a downloaded PowerShell MSI hash.'
    Assert-P42 ($action -notmatch 'uses:\s*actions/[^@\s]+@(?![0-9a-f]{40}\b)') 'Composite baseline action contains a floating external action ref.'

    $global = Get-Content -Raw -LiteralPath (Join-Path $root 'global.json') | ConvertFrom-Json
    Assert-P42 ([string]$global.sdk.version -ceq '10.0.400') 'global.json SDK version is not the reviewed .NET 10 SDK.'
    Assert-P42 ([string]$global.sdk.rollForward -ceq 'latestPatch') 'global.json must allow only same-feature-band patch roll-forward.'
    Assert-P42 ($global.sdk.allowPrerelease -eq $false) 'global.json must reject prerelease SDKs.'

    foreach ($project in @(Get-ChildItem -LiteralPath $root -Recurse -Filter '*.csproj' -File)) {
        $lockPath = Join-Path $project.DirectoryName 'packages.lock.json'
        Assert-P42 (Test-Path -LiteralPath $lockPath -PathType Leaf) "NuGet lock file is missing for $($project.FullName)."
    }
    $galleryScript = Join-Path $root 'tools/Test-P42GalleryPreflight.ps1'
    Assert-P42 (Test-Path -LiteralPath $galleryScript -PathType Leaf) 'Gallery preflight tool is missing.'
    Write-Output 'PASS P4.2 workflow pinning, least privilege, secret boundary, host pin, and restore-lock checks'
}
catch {
    Write-Error "P4.2 security tests failed: $($_.Exception.Message)"
    exit 1
}
