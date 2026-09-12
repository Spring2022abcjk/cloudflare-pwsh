Set-StrictMode -Version Latest

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

function Get-CfDnsRecord {
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
        $record = New-CfApiErrorRecord $exception $ZoneId
        $PSCmdlet.ThrowTerminatingError($record)
    } finally { $client.Dispose() }
}

function New-CfDnsRecord {
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
        $query = @{ include_shadow_metadata = $IncludeShadowMetadata }
        $client.CreateDnsRecordAsync($ZoneId, $body, (ConvertTo-CfQueryDictionary $query), [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
    } catch [Cloudflare.PowerShell.CloudflareApiException] {
        $exception = $_.Exception
        $record = New-CfApiErrorRecord $exception $ZoneId
        $PSCmdlet.ThrowTerminatingError($record)
    } finally { $client.Dispose() }
}

function Remove-CfDnsRecord {
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
        $record = New-CfApiErrorRecord $exception $RecordId
        $PSCmdlet.ThrowTerminatingError($record)
    } finally { $client.Dispose() }
}

function Set-CfDnsRecord {
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
        $record = New-CfApiErrorRecord $exception $RecordId
        $PSCmdlet.ThrowTerminatingError($record)
    } finally { $client.Dispose() }
}
