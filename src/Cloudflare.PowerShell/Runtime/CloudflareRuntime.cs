using System.Net;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace Cloudflare.PowerShell;

public sealed record CloudflareError(int Code, string Message);

public sealed record CloudflareResponseMetadata(
    HttpStatusCode StatusCode,
    string Method,
    Uri RequestUri,
    IReadOnlyDictionary<string, IEnumerable<string>> Headers);

public sealed class CloudflareApiException : Exception
{
    public CloudflareApiException(
        HttpStatusCode statusCode,
        IReadOnlyList<CloudflareError> errors,
        string rawBody,
        CloudflareResponseMetadata metadata,
        Exception? innerException = null,
        int retryCount = 0)
        : base(BuildMessage(statusCode, errors), innerException)
    {
        StatusCode = statusCode;
        Errors = errors;
        RawBody = rawBody;
        Metadata = metadata;
        RequestId = FindRequestId(metadata.Headers);
        RetryCount = retryCount;
        FullyQualifiedErrorId = $"Cloudflare.Api.{(int)statusCode}";
    }

    public HttpStatusCode StatusCode { get; }
    public IReadOnlyList<CloudflareError> Errors { get; }
    public string RawBody { get; }
    public CloudflareResponseMetadata Metadata { get; }
    public string? RequestId { get; }
    public int RetryCount { get; }
    public string FullyQualifiedErrorId { get; }

    private static string BuildMessage(HttpStatusCode statusCode, IReadOnlyList<CloudflareError> errors)
    {
        var detail = errors.Count == 0 ? "Cloudflare request failed." : string.Join("; ", errors.Select(e => $"[{e.Code}] {e.Message}"));
        return $"Cloudflare API returned {(int)statusCode} ({statusCode}): {detail}";
    }

    private static string? FindRequestId(IReadOnlyDictionary<string, IEnumerable<string>> headers)
    {
        foreach (var name in new[] { "CF-Ray", "X-Request-ID", "Request-ID" })
            if (headers.TryGetValue(name, out var values)) return values.FirstOrDefault();
        return null;
    }
}

public sealed class CloudflareEnvelope<T>
{
    [JsonPropertyName("success")]
    public bool? Success { get; set; }

    [JsonPropertyName("result")]
    public T? Result { get; set; }

    [JsonPropertyName("errors")]
    public List<CloudflareError> Errors { get; set; } = [];

    [JsonPropertyName("messages")]
    public List<JsonElement> Messages { get; set; } = [];
}

public sealed class CloudflarePageInfo
{
    [JsonPropertyName("page")]
    public int Page { get; set; }

    [JsonPropertyName("per_page")]
    public int PerPage { get; set; }

    [JsonPropertyName("count")]
    public int Count { get; set; }

    [JsonPropertyName("total_count")]
    public int TotalCount { get; set; }

    [JsonPropertyName("total_pages")]
    public int TotalPages { get; set; }
}

public sealed class CloudflarePage<T>
{
    [JsonPropertyName("result")]
    public List<T> Result { get; set; } = [];

    [JsonPropertyName("result_info")]
    public CloudflarePageInfo? ResultInfo { get; set; }
}

public sealed class CloudflareClientOptions
{
    public Uri BaseUri { get; init; } = new("https://api.cloudflare.com/client/v4/");
    public string? BearerToken { get; init; }
    public HttpMessageHandler? Handler { get; init; }
}

public sealed class CloudflareClient : IDisposable
{
    private readonly HttpClient _httpClient;
    private readonly bool _ownsClient;
    private readonly CloudflareRuntimeDispatcher _dispatcher;

    internal CloudflareRuntimeDispatcher Dispatcher => _dispatcher;

    public CloudflareClient(CloudflareClientOptions options, HttpClient? httpClient = null)
    {
        _httpClient = httpClient ?? new HttpClient(options.Handler ?? new HttpClientHandler());
        _ownsClient = httpClient is null;
        _httpClient.BaseAddress = options.BaseUri;
        _dispatcher = new CloudflareRuntimeDispatcher(
            options.BaseUri,
            new HttpClientTransport(_httpClient),
            string.IsNullOrWhiteSpace(options.BearerToken) ? null : new ApiTokenAuthenticationContext(options.BearerToken));
    }

    public IAsyncEnumerable<CfDnsRecord> ListDnsRecordsAsync(
        string zoneId,
        IReadOnlyDictionary<string, object?>? query = null,
        CancellationToken cancellationToken = default)
    {
        var values = new Dictionary<string, object?>(StringComparer.Ordinal) { ["zone_id"] = zoneId };
        if (query is not null)
            foreach (var item in query) values[item.Key] = item.Value;

        var operation = GeneratedOperationMetadataAdapter.ToRuntime(CfDnsRecordRuntimeMetadata.Get(
            CfDnsRecordOperationMetadata.Operation_dns_records_List_dns_records_for_a_zone_list_dns_records));
        var pagination = GeneratedOperationMetadataAdapter.ToRuntimePagination(CfDnsRecordRuntimeMetadata.Get(
            CfDnsRecordOperationMetadata.Operation_dns_records_List_dns_records_for_a_zone_list_dns_records))
            ?? throw new InvalidOperationException("Generated list operation is missing pagination metadata.");
        return new CloudflareTaskBackedAsyncEnumerable<CfDnsRecord>(_dispatcher.ExecutePagedAsync<CfDnsRecord>(
            operation, new BoundParameters(values), pagination, cancellationToken));
    }

    public IAsyncEnumerable<CfZone> ListZonesAsync(
        IReadOnlyDictionary<string, object?>? query = null,
        CancellationToken cancellationToken = default)
    {
        var values = new Dictionary<string, object?>(StringComparer.Ordinal);
        if (query is not null)
            foreach (var item in query) values[item.Key] = item.Value;

        var metadata = CfZoneRuntimeMetadata.Get(CfZoneOperationMetadata.Operation_zones_List_zones_get);
        var operation = GeneratedOperationMetadataAdapter.ToRuntime(metadata);
        var pagination = GeneratedOperationMetadataAdapter.ToRuntimePagination(metadata)
            ?? throw new InvalidOperationException("Generated zone list operation is missing pagination metadata.");
        return new CloudflareTaskBackedAsyncEnumerable<CfZone>(_dispatcher.ExecutePagedAsync<CfZone>(
            operation, new BoundParameters(values), pagination, cancellationToken));
    }

    public async Task<CfZone> GetZoneAsync(
        string zoneId,
        CancellationToken cancellationToken = default)
    {
        var metadata = CfZoneRuntimeMetadata.Get(CfZoneOperationMetadata.Operation_zones_Get_zones_0_get);
        var operation = GeneratedOperationMetadataAdapter.ToRuntime(metadata);
        return (await _dispatcher.ExecuteAsync<CfZone>(
            operation,
            new BoundParameters(new Dictionary<string, object?> { ["zone_id"] = zoneId }),
            cancellationToken).ConfigureAwait(false))!;
    }

    public async Task<CfDnsRecord> GetDnsRecordAsync(string zoneId, string recordId, IReadOnlyDictionary<string, object?>? query = null, CancellationToken cancellationToken = default)
    {
        var values = new Dictionary<string, object?>(StringComparer.Ordinal) { ["zone_id"] = zoneId, ["dns_record_id"] = recordId };
        if (query is not null)
            foreach (var item in query) values[item.Key] = item.Value;
        var operation = GeneratedOperationMetadataAdapter.ToRuntime(CfDnsRecordRuntimeMetadata.Get(
            CfDnsRecordOperationMetadata.Operation_dns_records_Get_dns_records_for_a_zone_dns_record_details));
        return (await _dispatcher.ExecuteAsync<CfDnsRecord>(operation, new BoundParameters(values), cancellationToken).ConfigureAwait(false))!;
    }

    public async Task<CfDnsRecord> CreateDnsRecordAsync(string zoneId, JsonNode body, IReadOnlyDictionary<string, object?>? query = null, CancellationToken cancellationToken = default)
    {
        var values = new Dictionary<string, object?>(StringComparer.Ordinal) { ["zone_id"] = zoneId, ["body"] = body };
        if (query is not null)
            foreach (var item in query) values[item.Key] = item.Value;
        var operation = GeneratedOperationMetadataAdapter.ToRuntime(CfDnsRecordRuntimeMetadata.Get(
            CfDnsRecordOperationMetadata.Operation_dns_records_Create_dns_records_for_a_zone_create_dns_record));
        return (await _dispatcher.ExecuteAsync<CfDnsRecord>(operation, new BoundParameters(values), cancellationToken).ConfigureAwait(false))!;
    }

    public async Task<CfDnsRecord> UpdateDnsRecordAsync(string zoneId, string recordId, JsonNode body, CancellationToken cancellationToken = default)
    {
        var operation = GeneratedOperationMetadataAdapter.ToRuntime(CfDnsRecordRuntimeMetadata.Get(
            CfDnsRecordOperationMetadata.Operation_dns_records_Update_dns_records_for_a_zone_update_dns_record));
        return (await _dispatcher.ExecuteAsync<CfDnsRecord>(
            operation,
            new BoundParameters(new Dictionary<string, object?> { ["zone_id"] = zoneId, ["dns_record_id"] = recordId, ["body"] = body }),
            cancellationToken).ConfigureAwait(false))!;
    }

    public async Task<CfDnsRecord> EditDnsRecordAsync(string zoneId, string recordId, JsonNode body, CancellationToken cancellationToken = default)
    {
        var operation = GeneratedOperationMetadataAdapter.ToRuntime(CfDnsRecordRuntimeMetadata.Get(
            CfDnsRecordOperationMetadata.Operation_dns_records_Edit_dns_records_for_a_zone_patch_dns_record));
        return (await _dispatcher.ExecuteAsync<CfDnsRecord>(
            operation,
            new BoundParameters(new Dictionary<string, object?> { ["zone_id"] = zoneId, ["dns_record_id"] = recordId, ["body"] = body }),
            cancellationToken).ConfigureAwait(false))!;
    }

    public async Task DeleteDnsRecordAsync(string zoneId, string recordId, CancellationToken cancellationToken = default)
    {
        var operation = GeneratedOperationMetadataAdapter.ToRuntime(CfDnsRecordRuntimeMetadata.Get(
            CfDnsRecordOperationMetadata.Operation_dns_records_Delete_dns_records_for_a_zone_delete_dns_record));
        await _dispatcher.ExecuteAsync<JsonNode>(
            operation,
            new BoundParameters(new Dictionary<string, object?> { ["zone_id"] = zoneId, ["dns_record_id"] = recordId }),
            cancellationToken).ConfigureAwait(false);
    }

    public void Dispose()
    {
        if (_ownsClient) _httpClient.Dispose();
    }
}

public static class QuerySerializer
{
    public static string Serialize(IReadOnlyDictionary<string, object?>? values)
    {
        if (values is null || values.Count == 0) return string.Empty;
        var parts = new List<string>();
        foreach (var pair in values.OrderBy(x => x.Key, StringComparer.Ordinal))
            Append(parts, pair.Key, pair.Value);
        return parts.Count == 0 ? string.Empty : "?" + string.Join("&", parts);
    }

    private static void Append(List<string> parts, string key, object? value)
    {
        if (value is null) return;
        if (value is string text) { parts.Add(Encode(key) + "=" + Encode(text)); return; }
        if (value is IEnumerable<string> strings) { foreach (var item in strings) Append(parts, key, item); return; }
        if (value is System.Collections.IDictionary dictionary)
        {
            foreach (System.Collections.DictionaryEntry item in dictionary)
                Append(parts, key + "." + item.Key, item.Value);
            return;
        }
        if (value is JsonObject jsonObject)
        {
            foreach (var item in jsonObject) Append(parts, key + "." + item.Key, item.Value);
            return;
        }
        if (value is System.Collections.IEnumerable enumerable and not byte[])
        {
            foreach (var item in enumerable) Append(parts, key, item);
            return;
        }
        parts.Add(Encode(key) + "=" + Encode(Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture) ?? string.Empty));
    }

    private static string Encode(string value) => Uri.EscapeDataString(value);
}
