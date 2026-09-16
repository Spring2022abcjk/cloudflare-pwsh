[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ReportPath,
    [string]$PolicyPath = (Join-Path $ProjectRoot 'build/p34-compatibility-policy.json'),
    [string]$OutputPath = (Join-Path $ProjectRoot 'artifacts/p34/compatibility-gate.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path)
function Resolve-P34Path {
    param([Parameter(Mandatory)][string]$Path)
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $root $Path))
}
function Get-P34Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    return ((Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash).ToLowerInvariant()
}

$policyPath = Resolve-P34Path $PolicyPath
if (-not (Test-Path -LiteralPath $policyPath -PathType Leaf)) { throw "P3.4 compatibility policy is missing: $policyPath" }
$policy = Get-Content -Raw -LiteralPath $policyPath | ConvertFrom-Json
if ([int]$policy.version -ne 1 -or [string]$policy.stage -cne 'P3.4') { throw 'P3.4 compatibility policy version/stage is unsupported.' }
$schemaManifestPath = Resolve-P34Path 'build/pinned-schema.json'
if (-not (Test-Path -LiteralPath $schemaManifestPath -PathType Leaf)) { throw "P3.4 pinned schema manifest is missing: $schemaManifestPath" }
$schemaManifest = Get-Content -Raw -LiteralPath $schemaManifestPath | ConvertFrom-Json
foreach ($field in @('revision', 'sourceRevision', 'sourcePath', 'sha256')) {
    if ([string]::IsNullOrWhiteSpace([string]$schemaManifest.$field)) { throw "P3.4 pinned schema manifest is missing '$field'." }
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $manifestPath = Resolve-P34Path 'fixtures/p2.4/openapi-previous-revision.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "P2.4 revision manifest is missing: $manifestPath" }
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    $artifactRoot = Resolve-P34Path 'artifacts/compatibility'
    $candidates = @()
    foreach ($candidate in @(Get-ChildItem -LiteralPath $artifactRoot -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        try { $value = Get-Content -Raw -LiteralPath $candidate.FullName | ConvertFrom-Json } catch { continue }
        if ([string]$value.stage -ceq 'P2.4' -and [string]$value.newSourceRevision -ceq [string]$manifest.currentRevision) { $candidates += $candidate.FullName }
    }
    if ($candidates.Count -ne 1) { throw "Could not resolve exactly one P2.4 compatibility report for revision '$($manifest.currentRevision)'; found $($candidates.Count)." }
    $ReportPath = $candidates[0]
}
$reportPath = Resolve-P34Path $ReportPath
$outputPath = Resolve-P34Path $OutputPath
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw "P2.4 compatibility report is missing: $reportPath" }
$report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
if ([string]$report.stage -cne 'P2.4' -or $null -eq $report.changes -or $null -eq $report.severitySummary) { throw 'P2.4 compatibility report has an unsupported schema.' }
if ([string]$report.newSourceRevision -cne [string]$schemaManifest.revision) {
    throw "P2.4 compatibility report revision '$($report.newSourceRevision)' does not match pinned schema revision '$($schemaManifest.revision)'."
}

$impactNames = @('None', 'NonBreaking', 'Behavioral', 'PotentiallyBreaking', 'Breaking')
$schemaChangeKinds = @(
    'PropertyAdded', 'PropertyRemoved', 'PropertyBecameRequired', 'PropertyBecameOptional',
    'PropertyTypeChanged', 'NullableChanged', 'ReadOnlyChanged', 'WriteOnlyChanged',
    'EnumValueAdded', 'EnumValueRemoved', 'UnionVariantAdded',
    'UnionVariantRemoved', 'DiscriminatorAdded', 'DiscriminatorRemoved',
    'DiscriminatorPropertyChanged', 'DiscriminatorValueChanged', 'SchemaTypeChanged',
    'SchemaAdded', 'SchemaRemoved', 'SchemaCompositionChanged'
)
$projectionChangeKinds = @(
    'CmdletAdded', 'CmdletRemoved', 'PowerShellParameterAdded', 'PowerShellParameterRemoved',
    'PowerShellParameterBecameMandatory', 'PowerShellParameterSetChanged',
    'PipelineBindingChanged', 'OutputTypeChanged', 'ShouldProcessChanged',
    'ConfirmImpactChanged', 'PagingBehaviorChanged', 'PowerShellNameCollision'
)
$operationChangeKinds = @(
    'OperationAdded', 'OperationRemoved', 'HttpMethodChanged', 'PathChanged',
    'ResourcePathChanged', 'SemanticKindChanged', 'ScopeBindingAdded',
    'ScopeBindingRemoved', 'ScopeBindingRoleChanged', 'PrimaryResourceIdChanged',
    'PaginationAdded', 'PaginationRemoved', 'PaginationStrategyChanged',
    'RequestPagingFieldChanged', 'ResponsePagingFieldChanged', 'StopRuleChanged',
    'NextPageRuleChanged', 'RequestBodyRequiredChanged', 'RequestBodyPresenceChanged',
    'RequestContentTypeAdded', 'RequestContentTypeRemoved', 'RequestSchemaChanged',
    'ParameterAdded', 'ParameterRemoved', 'ParameterBecameRequired',
    'ParameterBecameOptional', 'ParameterTypeChanged', 'ParameterLocationChanged',
    'ParameterSerializationChanged', 'ParameterNullabilityChanged', 'DefaultChanged',
    'SuccessStatusAdded', 'SuccessStatusRemoved', 'ResponseContentTypeAdded',
    'ResponseContentTypeRemoved', 'EnvelopePolicyChanged', 'ParsingModeChanged',
    'ResultSchemaChanged', 'ErrorResponseChanged'
)
$canonicalFields = @('kind', 'resourcePath', 'operationId', 'schemaName', 'path', 'oldValue', 'newValue', 'apiImpact', 'sdkImpact', 'powerShellImpact')
function Get-P34Field {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) { return '' }
    return [string]$Object.PSObject.Properties[$Name].Value
}
function Get-P34IdentityContract {
    param([Parameter(Mandatory)]$Change)
    $kind = Get-P34Field $Change 'kind'
    if ($kind -eq 'DefaultChanged' -and -not [string]::IsNullOrWhiteSpace((Get-P34Field $Change 'schemaName'))) {
        return [ordered]@{ required = @('schemaName', 'path', 'oldValue', 'newValue'); empty = @('resourcePath', 'operationId') }
    }
    if ($schemaChangeKinds -contains $kind) {
        return [ordered]@{ required = @('schemaName', 'path', 'oldValue', 'newValue'); empty = @('resourcePath', 'operationId') }
    }
    if ($projectionChangeKinds -contains $kind) {
        return [ordered]@{ required = @('operationId', 'path', 'oldValue', 'newValue'); empty = @('resourcePath', 'schemaName') }
    }
    if ($operationChangeKinds -contains $kind) {
        return [ordered]@{ required = @('operationId', 'path', 'oldValue', 'newValue'); empty = @('schemaName') }
    }
    throw "Compatibility change kind '$kind' has no canonical identity contract."
}
function Assert-P34ChangeContract {
    param([Parameter(Mandatory)]$Change, [Parameter(Mandatory)][string]$Label)
    $kind = Get-P34Field $Change 'kind'
    if ([string]::IsNullOrWhiteSpace($kind)) { throw "$Label is missing 'kind'." }
    $contract = Get-P34IdentityContract $Change
    foreach ($field in $contract.required) {
        if ([string]::IsNullOrWhiteSpace((Get-P34Field $Change $field))) { throw "$Label is missing canonical identity field '$field'." }
    }
    foreach ($field in $contract.empty) {
        if (-not [string]::IsNullOrWhiteSpace((Get-P34Field $Change $field))) { throw "$Label has an unexpected canonical identity field '$field' for kind '$kind'." }
    }
    foreach ($field in @('apiImpact', 'sdkImpact', 'powerShellImpact')) {
        $impact = Get-P34Field $Change $field
        if ([string]::IsNullOrWhiteSpace($impact)) { throw "$Label is missing '$field'." }
        if ($impactNames -notcontains $impact) { throw "$Label has an invalid $field value '$impact'." }
    }
}
function Get-P34ChangeKey {
    param([Parameter(Mandatory)]$Change)
    $canonical = [ordered]@{}
    foreach ($field in $canonicalFields) { $canonical[$field] = Get-P34Field $Change $field }
    return ($canonical | ConvertTo-Json -Compress -Depth 10)
}

$approvals = @($policy.approvedChanges)
$approvalByKey = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
foreach ($approval in $approvals) {
    Assert-P34ChangeContract $approval 'Compatibility allowlist entry'
    $key = Get-P34ChangeKey $approval
    if ($approvalByKey.ContainsKey($key)) { throw "Compatibility allowlist contains a duplicate canonical entry: $key" }
    $approvalByKey[$key] = $approval
}

$approved = [Collections.Generic.List[string]]::new()
$violations = [Collections.Generic.List[object]]::new()
$reportByKey = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
foreach ($change in @($report.changes)) {
    Assert-P34ChangeContract $change 'Compatibility change'
    $key = Get-P34ChangeKey $change
    if ($reportByKey.ContainsKey($key)) {
        $violations.Add([pscustomobject]@{ category = 'DuplicateReportChange'; key = $key; path = Get-P34Field $change 'path' })
    } else {
        $reportByKey[$key] = $change
    }
}
$seenApprovalKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($key in @($reportByKey.Keys | Sort-Object)) {
    $change = $reportByKey[$key]
    $isApproved = $approvalByKey.ContainsKey($key)
    if ($isApproved) {
        [void]$seenApprovalKeys.Add($key)
        $approved.Add($key)
    }
    $impacts = @((Get-P34Field $change 'apiImpact'), (Get-P34Field $change 'sdkImpact'), (Get-P34Field $change 'powerShellImpact'))
    if ($impacts -contains 'Unknown') {
        $violations.Add([pscustomobject]@{ category = 'UnknownImpact'; key = $key; path = Get-P34Field $change 'path' })
    } elseif (-not $isApproved -and $impacts -contains 'Breaking') {
        $violations.Add([pscustomobject]@{ category = 'UnexpectedBreaking'; key = $key; path = Get-P34Field $change 'path' })
    } elseif (-not $isApproved -and $impacts -contains 'PotentiallyBreaking') {
        $violations.Add([pscustomobject]@{ category = 'ManualReviewRequired'; key = $key; path = Get-P34Field $change 'path' })
    }
}

$unusedApprovals = @($approvalByKey.Keys | Where-Object { -not $seenApprovalKeys.Contains($_) } | Sort-Object)
foreach ($key in $unusedApprovals) { $violations.Add([pscustomobject]@{ category = 'UnusedAllowlistEntry'; key = $key; path = '' }) }
$approved = @($approved | Sort-Object)
$violations = @($violations | Sort-Object category, key)
$summary = [ordered]@{
    schemaVersion = 1
    stage = 'P3.4'
    gateName = 'P3.4.CompatibilityGate'
    gateType = 'Compatibility'
    status = if ($violations.Count -eq 0) { 'Passed' } else { 'Failed' }
    policyIdentity = [ordered]@{
        path = [IO.Path]::GetRelativePath($root, $policyPath).Replace('\', '/')
        sha256 = Get-P34Sha256 $policyPath
    }
    inputReportIdentity = [ordered]@{
        fileName = [IO.Path]::GetFileName($reportPath)
        sha256 = Get-P34Sha256 $reportPath
    }
    schemaIdentity = [ordered]@{
        revision = [string]$schemaManifest.revision
        sourceRevision = [string]$schemaManifest.sourceRevision
        sourcePath = [string]$schemaManifest.sourcePath
        sha256 = [string]$schemaManifest.sha256
    }
    comparisonIdentity = [ordered]@{
        oldRevision = [string]$report.oldSourceRevision
        newRevision = [string]$report.newSourceRevision
    }
    reportPath = [IO.Path]::GetRelativePath($root, $reportPath).Replace('\', '/')
    policyPath = [IO.Path]::GetRelativePath($root, $policyPath).Replace('\', '/')
    changeCount = @($report.changes).Count
    approvedChangeCount = $approved.Count
    approvedChanges = $approved
    violations = $violations
    policy = [ordered]@{
        unknownImpact = [string]$policy.rules.unknownImpact
        unexpectedBreaking = [string]$policy.rules.unexpectedBreaking
        unexpectedPotentiallyBreaking = [string]$policy.rules.unexpectedPotentiallyBreaking
    }
}
$outputDirectory = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$json = $summary | ConvertTo-Json -Depth 20
$normalized = $json.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
[IO.File]::WriteAllText($outputPath, $normalized, [Text.UTF8Encoding]::new($false))
if ($violations.Count -ne 0) { throw "P3.4 compatibility gate failed with $($violations.Count) violation(s); see $outputPath." }
Write-Output "PASS P3.4 compatibility gate changes=$(@($report.changes).Count) approved=$($approved.Count) -> $outputPath"
