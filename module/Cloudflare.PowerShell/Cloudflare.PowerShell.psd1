@{
    RootModule = 'Cloudflare.PowerShell.psm1'
    ModuleVersion = '0.1.0'
    GUID = 'f8e512fb-2a88-4c1d-a3d7-8dcfdf5c6f77'
    Author = 'Cloudflare PowerShell P1'
    Description = 'P1 DNS vertical slice prototype.'
    PowerShellVersion = '7.6'
    RequiredAssemblies = @('Cloudflare.PowerShell.dll')
    FunctionsToExport = @()
    CmdletsToExport = @('Get-CfZone', 'Get-CfDnsRecord', 'New-CfDnsRecord', 'Remove-CfDnsRecord', 'Set-CfDnsRecord', 'Get-CfD1Database', 'New-CfD1Database', 'Remove-CfD1Database', 'Set-CfD1Database', 'Get-CfHealthCheck', 'New-CfHealthCheck', 'Remove-CfHealthCheck', 'Set-CfHealthCheck')
    VariablesToExport = @()
    AliasesToExport = @()
}
