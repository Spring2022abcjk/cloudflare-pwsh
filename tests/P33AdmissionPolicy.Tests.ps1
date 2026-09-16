[CmdletBinding()]
param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

$policy = Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'overrides/public-admission-policy.json') | ConvertFrom-Json
$report = Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'artifacts/coverage/after-global-coverage.json') | ConvertFrom-Json
$gateIds = @($policy.gates | ForEach-Object id)
$requiredGateIds = @(
    'normalization.valid', 'correction.unambiguous', 'projection.deterministic',
    'projection.no-name-collision', 'projection.parameter-sets-distinguishable',
    'runtime.capability', 'model.typed-supported', 'compatibility.visible',
    'public.naming.accepted', 'mutation.safety-resolved', 'policy.explicit-admission'
)
Assert-True ($policy.automaticAdmission -eq $false) 'public admission must remain explicit-only.'
Assert-True (($gateIds -join '|') -ceq ($requiredGateIds -join '|')) 'public admission gate order or membership drifted.'
Assert-True (@($policy.nonAdmissionRules).Count -ge 3) 'public admission non-admission rules are incomplete.'

$publicRows = @($report.operations | Where-Object currentPublicSurface)
Assert-True ($publicRows.Count -eq 8) 'public surface count drifted.'
foreach ($row in $publicRows) {
    Assert-True ([string]$row.classification -in @('Supported', 'SupportedWithOverride')) "public row '$($row.operationId)' is not admitted by a supported classification."
    Assert-True ([string]$row.projectionStatus -ne 'Conflict') "public row '$($row.operationId)' retains a projection conflict."
    Assert-True ([string]$row.currentPublicCmdlet -ne '') "public row '$($row.operationId)' has no current cmdlet."
    Assert-True (@($row.missingCapabilities).Count -eq 0) "public row '$($row.operationId)' has unresolved missing capabilities."
}
$candidateRows = @($report.operations | Where-Object { -not $_.currentPublicSurface })
Assert-True (@($candidateRows | Where-Object classification -in @('Supported', 'SupportedWithOverride')).Count -eq 0) 'non-public operations were auto-admitted.'
Assert-True (@($report.operations | Where-Object projectionResolution -in @('ScopeKey', 'HttpMethod') | Where-Object currentPublicSurface).Count -eq 0) 'generic projection resolution crossed the public admission boundary.'

Write-Output 'PASS P3.3 explicit public admission gates and non-admission boundary'
