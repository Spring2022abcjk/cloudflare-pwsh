@{
    RootModule = 'Cloudflare.PowerShell.psm1'
    ModuleVersion = '0.1.0'
    GUID = 'f8e512fb-2a88-4c1d-a3d7-8dcfdf5c6f77'
    Author = 'Cloudflare PowerShell P1'
    Description = 'Windows-first Cloudflare PowerShell SDK prototype with deterministic schema, generation, compatibility, and package validation.'
    PowerShellVersion = '7.6'
    CompatiblePSEditions = @('Core')
    RequiredAssemblies = @('Cloudflare.PowerShell.dll')
    FunctionsToExport = @()
    CmdletsToExport = @('Get-CfZone', 'Get-CfDnsRecord', 'New-CfDnsRecord', 'Remove-CfDnsRecord', 'Set-CfDnsRecord')
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            ProjectUri = 'https://github.com/Spring2022abcjk/cloudflare-pwsh'
            Tags = @('Cloudflare', 'PowerShell', 'PowerShellCore', 'Windows', 'SDK')
            ReleaseNotes = 'P4.2 release/security candidate: pinned GitHub Actions, locked dependencies, schema and package provenance checks, and deterministic local validation. This candidate is not published.'
        }
    }
}
