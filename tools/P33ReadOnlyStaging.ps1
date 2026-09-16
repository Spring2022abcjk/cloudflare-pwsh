[CmdletBinding()]
param([switch]$Library)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-P33RequiredInputPaths {
    param([Parameter(Mandatory)][string]$ProjectRoot)

    # This is the P3.3 declaration, not a copy of the P3.2 declaration. Files
    # emitted by the D1 fixture/projector/generator are intentionally absent:
    # they must be rebuilt in the isolated staging root.
    return @(
        'Cloudflare.P1.sln',
        'artifacts/p2.3/projection/d1-database.json',
        'artifacts/p3.3/coverage-baseline.json',
        'artifacts/p3.3/coverage-baseline.md',
        'module/Cloudflare.PowerShell/Cloudflare.PowerShell.psd1',
        'module/Cloudflare.PowerShell/Cloudflare.PowerShell.psm1',
        'overrides/api-corrections.json',
        'overrides/powershell-projection.json',
        'overrides/powershell-p33-d1-projection.json',
        'ref/api-schemas/openapi.json',
        'tests/P33Coverage.Tests.ps1',
        'tests/P33D1Projection.Tests.ps1',
        'tests/P33D1Smoke.ps1',
        'tools/Generate-P32Source.ps1',
        'tools/Generate-P33D1Fixture.ps1',
        'tools/Generate-P33D1Source.ps1',
        'tools/Invoke-P33D1Compatibility.ps1',
        'tools/P32Hash.ps1',
        'tools/P33ModelSchemaParity.ps1',
        'tools/Project-P32Projection.ps1',
        'tools/Project-P33D1Projection.ps1',
        'tools/ReadOnlyStaging.ps1',
        'tools/templates/P32RepresentativeCmdlets.cs.tmpl',

        # The solution uses SDK source discovery. Keep this list explicit so a
        # newly added unrelated source file cannot silently enter staging.
        'src/Cloudflare.Normalization/ApiCorrectionEngine.cs',
        'src/Cloudflare.Normalization/Cloudflare.Normalization.csproj',
        'src/Cloudflare.Normalization/Compatibility/ApiChange.cs',
        'src/Cloudflare.Normalization/Compatibility/CompatibilityEngine.cs',
        'src/Cloudflare.Normalization/Compatibility/CompatibilityReportFormatter.cs',
        'src/Cloudflare.Normalization/Compatibility/PowerShellNameCanonicalizer.cs',
        'src/Cloudflare.Normalization/Compatibility/ProjectionCompatibility.cs',
        'src/Cloudflare.Normalization/Compatibility/ProjectionModelBuilder.cs',
        'src/Cloudflare.Normalization/HandwrittenFixtureLoader.cs',
        'src/Cloudflare.Normalization/NormalizedModel.cs',
        'src/Cloudflare.Normalization/OpenApiLoader.cs',
        'src/Cloudflare.Normalization/OpenApiNormalizer.cs',
        'src/Cloudflare.Normalization/SemanticComparer.cs',
        'src/Cloudflare.PowerShell/Cloudflare.PowerShell.csproj',
        'src/Cloudflare.PowerShell/Generated/Cmdlets/P32RepresentativeCmdlets.cs',
        'src/Cloudflare.PowerShell/Generated/Metadata/CfDnsRecordOperationMetadata.cs',
        'src/Cloudflare.PowerShell/Generated/Metadata/CfDnsRecordRuntimeMetadata.cs',
        'src/Cloudflare.PowerShell/Generated/Metadata/CfZoneOperationMetadata.cs',
        'src/Cloudflare.PowerShell/Generated/Metadata/CfZoneRuntimeMetadata.cs',
        'src/Cloudflare.PowerShell/Generated/Metadata/P21_ai_search_jobsProjection.cs',
        'src/Cloudflare.PowerShell/Generated/Metadata/P21_d1_databaseProjection.cs',
        'src/Cloudflare.PowerShell/Generated/Metadata/P21_zonesProjection.cs',
        'src/Cloudflare.PowerShell/Generated/Metadata/P32CmdletHelpMetadata.cs',
        'src/Cloudflare.PowerShell/Generated/Metadata/Projection_Get_CfDnsRecord.cs',
        'src/Cloudflare.PowerShell/Generated/Metadata/Projection_New_CfDnsRecord.cs',
        'src/Cloudflare.PowerShell/Generated/Metadata/Projection_Remove_CfDnsRecord.cs',
        'src/Cloudflare.PowerShell/Generated/Metadata/Projection_Set_CfDnsRecord.cs',
        'src/Cloudflare.PowerShell/Generated/Models/CfDnsRecordModels.cs',
        'src/Cloudflare.PowerShell/Generated/Models/CfZoneModels.cs',
        'src/Cloudflare.PowerShell/Runtime/CloudflareCmdletBase.cs',
        'src/Cloudflare.PowerShell/Runtime/CloudflarePagination.cs',
        'src/Cloudflare.PowerShell/Runtime/CloudflareRetry.cs',
        'src/Cloudflare.PowerShell/Runtime/CloudflareRuntime.cs',
        'src/Cloudflare.PowerShell/Runtime/CloudflareRuntimeAbstractions.cs',
        'src/Cloudflare.PowerShell/Runtime/GeneratedOperationMetadataAdapter.cs',
        'tests/Cloudflare.Normalization.Tests/Cloudflare.Normalization.Tests.csproj',
        'tests/Cloudflare.Normalization.Tests/Program.cs',
        'tests/Cloudflare.P2.Tests/Cloudflare.P2.Tests.csproj',
        'tests/Cloudflare.P2.Tests/Program.cs',
        'tests/Cloudflare.P22.Tests/Cloudflare.P22.Tests.csproj',
        'tests/Cloudflare.P22.Tests/Program.cs',
        'tests/Cloudflare.P24.Tests/Cloudflare.P24.Tests.csproj',
        'tests/Cloudflare.P24.Tests/Program.cs',
        'tests/Cloudflare.PowerShell.Tests/Cloudflare.PowerShell.Tests.csproj',
        'tests/Cloudflare.PowerShell.Tests/Program.cs'
    ) | Sort-Object -Unique
}

function Get-P33D2RequiredInputPaths {
    param([Parameter(Mandatory)][string]$ProjectRoot)

    # D2 starts from the D1 declaration because the isolated solution must
    # rebuild the existing public surface before adding healthchecks. D2
    # outputs (fixture, artifacts, generated source/models/metadata) are not
    # inputs here; each is recreated in the isolated root.
    $d1 = @(Get-P33RequiredInputPaths -ProjectRoot $ProjectRoot)
    $d2 = @(
        'artifacts/p3.2/CmdletModel.json',
        'overrides/powershell-p33-d2-healthchecks-projection.json',
        'tests/P33D2Projection.Tests.ps1',
        'tests/P33D2Smoke.ps1',
        'tools/Generate-P33D2HealthchecksFixture.ps1',
        'tools/Generate-P33D2Source.ps1',
        'tools/Invoke-P33D2Compatibility.ps1',
        'tools/Invoke-P33D2ReadOnlyTests.ps1',
        'tools/Project-P33D2Projection.ps1'
    )
    return @($d1 + $d2 | Sort-Object -Unique)
}
