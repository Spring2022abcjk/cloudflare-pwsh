Set-StrictMode -Version Latest

$generatedAssemblyPath = Join-Path $PSScriptRoot 'Cloudflare.PowerShell.dll'
if (Test-Path -LiteralPath $generatedAssemblyPath) {
    Import-Module -Name $generatedAssemblyPath -Force
}

function New-CfClient {
    param([string]$BaseUrl, [string]$Token, [System.Net.Http.HttpMessageHandler]$Handler)
    $options = [Cloudflare.PowerShell.CloudflareClientOptions]@{
        BaseUri = [Uri]$BaseUrl
        BearerToken = $Token
        Handler = $Handler
    }
    return [Cloudflare.PowerShell.CloudflareClient]::new($options)
}

function ConvertTo-CfQueryDictionary {
    param([hashtable]$Values)
    $result = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($key in $Values.Keys) { $result[$key] = $Values[$key] }
    return $result
}

function New-CfApiErrorRecord {
    param(
        [Parameter(Mandatory)][Cloudflare.PowerShell.CloudflareApiException]$Exception,
        [Parameter()][object]$TargetObject
    )
    $status = [int]$Exception.StatusCode
    $category = switch ($status) {
        400 { [System.Management.Automation.ErrorCategory]::InvalidArgument; break }
        401 { [System.Management.Automation.ErrorCategory]::SecurityError; break }
        403 { [System.Management.Automation.ErrorCategory]::SecurityError; break }
        404 { [System.Management.Automation.ErrorCategory]::ObjectNotFound; break }
        408 { [System.Management.Automation.ErrorCategory]::ResourceUnavailable; break }
        429 { [System.Management.Automation.ErrorCategory]::ResourceUnavailable; break }
        default { [System.Management.Automation.ErrorCategory]::InvalidOperation }
    }
    return [System.Management.Automation.ErrorRecord]::new(
        $Exception,
        $Exception.FullyQualifiedErrorId,
        $category,
        $TargetObject)
}

function Invoke-CfDnsRecordHandwritten {
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'List')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Get')]
        [string]$ZoneId,
        [Parameter(Mandatory, Position = 1, ParameterSetName = 'Get')]
        [string]$RecordId,
        [Parameter(ParameterSetName = 'List')][string]$Name,
        [Parameter(ParameterSetName = 'List')][string]$Type,
        [Parameter(ParameterSetName = 'List')][hashtable]$Match,
        [Parameter(ParameterSetName = 'List')][string[]]$Tag,
        [Parameter(ParameterSetName = 'List')][Nullable[int]]$PerPage,
        [Parameter()][bool]$IncludeShadowMetadata = $false,
        [Parameter()][string]$BaseUrl = 'https://api.cloudflare.com/client/v4/',
        [Parameter()][string]$Token = $env:CF_API_TOKEN,
        [Parameter()][System.Net.Http.HttpMessageHandler]$Handler
    )
    $client = New-CfClient $BaseUrl $Token $Handler
    try {
        if ($PSCmdlet.ParameterSetName -eq 'Get') {
            $query = @{}
            if ($PSBoundParameters.ContainsKey('IncludeShadowMetadata')) { $query['include_shadow_metadata'] = $IncludeShadowMetadata }
            $client.GetDnsRecordAsync($ZoneId, $RecordId, (ConvertTo-CfQueryDictionary $query), [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
            return
        }
        $query = @{}
        if ($PSBoundParameters.ContainsKey('Name')) { $query['name'] = $Name }
        if ($PSBoundParameters.ContainsKey('Type')) { $query['type'] = $Type }
        if ($PSBoundParameters.ContainsKey('Match')) { $query['match'] = $Match }
        if ($PSBoundParameters.ContainsKey('Tag')) { $query['tag'] = $Tag }
        if ($PSBoundParameters.ContainsKey('PerPage')) { $query['per_page'] = $PerPage }
        if ($PSBoundParameters.ContainsKey('IncludeShadowMetadata')) { $query['include_shadow_metadata'] = $IncludeShadowMetadata }
        $async = $client.ListDnsRecordsAsync($ZoneId, (ConvertTo-CfQueryDictionary $query), [System.Threading.CancellationToken]::None)
        $enumerator = $async.GetAsyncEnumerator([System.Threading.CancellationToken]::None)
        try {
            while ($enumerator.MoveNextAsync().GetAwaiter().GetResult()) { $enumerator.Current }
        } finally { $enumerator.DisposeAsync().GetAwaiter().GetResult() }
    } catch [Cloudflare.PowerShell.CloudflareApiException] {
        $exception = $_.Exception
        $errorRecord = New-CfApiErrorRecord $exception $ZoneId
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    } finally { $client.Dispose() }
}

function Invoke-NewCfDnsRecordHandwritten {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$ZoneId,
        [Parameter(Mandatory, Position = 1)][Cloudflare.PowerShell.CfDnsRecordInput]$Record,
        [Parameter()][bool]$IncludeShadowMetadata = $false,
        [Parameter()][string]$BaseUrl = 'https://api.cloudflare.com/client/v4/',
        [Parameter()][string]$Token = $env:CF_API_TOKEN,
        [Parameter()][System.Net.Http.HttpMessageHandler]$Handler
    )
    if (-not $PSCmdlet.ShouldProcess($ZoneId, 'Create DNS record')) { return }
    $client = New-CfClient $BaseUrl $Token $Handler
    try {
        $body = $Record.ToJson()
        $query = @{}
        if ($PSBoundParameters.ContainsKey('IncludeShadowMetadata')) { $query['include_shadow_metadata'] = $IncludeShadowMetadata }
        $client.CreateDnsRecordAsync($ZoneId, $body, (ConvertTo-CfQueryDictionary $query), [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
    } catch [Cloudflare.PowerShell.CloudflareApiException] {
        $exception = $_.Exception
        $errorRecord = New-CfApiErrorRecord $exception $ZoneId
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    } finally { $client.Dispose() }
}

function Invoke-RemoveCfDnsRecordHandwritten {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$ZoneId,
        [Parameter(Mandatory, Position = 1)][string]$RecordId,
        [Parameter()][string]$BaseUrl = 'https://api.cloudflare.com/client/v4/',
        [Parameter()][string]$Token = $env:CF_API_TOKEN,
        [Parameter()][System.Net.Http.HttpMessageHandler]$Handler
    )
    if (-not $PSCmdlet.ShouldProcess($RecordId, 'Delete DNS record')) { return }
    $client = New-CfClient $BaseUrl $Token $Handler
    try { [void]$client.DeleteDnsRecordAsync($ZoneId, $RecordId, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult() }
    catch [Cloudflare.PowerShell.CloudflareApiException] {
        $exception = $_.Exception
        $errorRecord = New-CfApiErrorRecord $exception $RecordId
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    } finally { $client.Dispose() }
}

function Invoke-SetCfDnsRecordHandwritten {
    [CmdletBinding(DefaultParameterSetName = 'Replace', SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$ZoneId,
        [Parameter(Mandatory, Position = 1)][string]$RecordId,
        [Parameter(Mandatory, ParameterSetName = 'Replace')][hashtable]$Replace,
        [Parameter(Mandatory, ParameterSetName = 'Edit')][hashtable]$Edit,
        [Parameter()][string]$BaseUrl = 'https://api.cloudflare.com/client/v4/',
        [Parameter()][string]$Token = $env:CF_API_TOKEN,
        [Parameter()][System.Net.Http.HttpMessageHandler]$Handler
    )
    if (-not $PSCmdlet.ShouldProcess($RecordId, "$($PSCmdlet.ParameterSetName) DNS record")) { return }
    $client = New-CfClient $BaseUrl $Token $Handler
    try {
        $source = if ($PSCmdlet.ParameterSetName -eq 'Replace') { $Replace } else { $Edit }
        $body = [System.Text.Json.Nodes.JsonObject]::new()
        foreach ($key in $source.Keys | Sort-Object) { $body[$key] = [System.Text.Json.Nodes.JsonNode]::Parse(($source[$key] | ConvertTo-Json -Compress -Depth 20)) }
        if ($PSCmdlet.ParameterSetName -eq 'Replace') { $client.UpdateDnsRecordAsync($ZoneId, $RecordId, $body, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult() }
        else { $client.EditDnsRecordAsync($ZoneId, $RecordId, $body, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult() }
    } catch [Cloudflare.PowerShell.CloudflareApiException] {
        $exception = $_.Exception
        $errorRecord = New-CfApiErrorRecord $exception $RecordId
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    } finally { $client.Dispose() }
}

function Invoke-CfZoneHandwritten {
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Get', ValueFromPipelineByPropertyName)][string]$ZoneId,
        [Parameter(ParameterSetName = 'List')][string]$AccountId,
        [Parameter(ParameterSetName = 'List')][string]$AccountName,
        [Parameter(ParameterSetName = 'List')][string]$Direction,
        [Parameter(ParameterSetName = 'List')][string]$Match,
        [Parameter(ParameterSetName = 'List')][string]$Name,
        [Parameter(ParameterSetName = 'List')][string]$Order,
        [Parameter(ParameterSetName = 'List')][decimal]$Page,
        [Parameter(ParameterSetName = 'List')][decimal]$PerPage,
        [Parameter(ParameterSetName = 'List')][string]$Status,
        [Parameter(ParameterSetName = 'List')][string[]]$Type,
        [Parameter()][string]$BaseUrl = 'https://api.cloudflare.com/client/v4/',
        [Parameter()][string]$Token = $env:CF_API_TOKEN,
        [Parameter()][System.Net.Http.HttpMessageHandler]$Handler
    )
    $client = New-CfClient $BaseUrl $Token $Handler
    try {
        if ($PSCmdlet.ParameterSetName -eq 'Get') {
            $client.GetZoneAsync($ZoneId, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
            return
        }
        $query = @{}
        foreach ($publicName in @('AccountId','AccountName','Direction','Match','Name','Order','Page','PerPage','Status','Type')) {
            if ($PSBoundParameters.ContainsKey($publicName)) {
                $apiName = switch ($publicName) {
                    'AccountId' { 'account.id' }
                    'AccountName' { 'account.name' }
                    'PerPage' { 'per_page' }
                    default { $publicName.ToLowerInvariant() }
                }
                $query[$apiName] = $PSBoundParameters[$publicName]
            }
        }
        $async = $client.ListZonesAsync((ConvertTo-CfQueryDictionary $query), [System.Threading.CancellationToken]::None)
        $enumerator = $async.GetAsyncEnumerator([System.Threading.CancellationToken]::None)
        try {
            while ($enumerator.MoveNextAsync().GetAwaiter().GetResult()) { $enumerator.Current }
        } finally { $enumerator.DisposeAsync().GetAwaiter().GetResult() }
    } catch [Cloudflare.PowerShell.CloudflareApiException] {
        $exception = $_.Exception
        $target = if ($PSCmdlet.ParameterSetName -eq 'Get') { $ZoneId } else { $null }
        $errorRecord = New-CfApiErrorRecord $exception $target
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    } finally { $client.Dispose() }
}

# P3.2/P3.3 generated commands are the public surface. Handwritten implementations
# remain module-internal parity references during the migration boundary.
Export-ModuleMember -Function @() -Cmdlet @('Get-CfZone', 'Get-CfDnsRecord', 'New-CfDnsRecord', 'Remove-CfDnsRecord', 'Set-CfDnsRecord', 'Get-CfD1Database', 'New-CfD1Database', 'Remove-CfD1Database', 'Set-CfD1Database')
