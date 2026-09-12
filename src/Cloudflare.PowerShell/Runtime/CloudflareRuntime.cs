using System.Net;
using System.Net.Http.Headers;
using System.Runtime.CompilerServices;
using System.Text;
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
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        PropertyNameCaseInsensitive = true
    };

    private readonly HttpClient _httpClient;
    private readonly bool _ownsClient;
    private readonly JsonSerializerOptions _jsonOptions;
    private readonly CloudflareRuntimeDispatcher _dispatcher;

    public CloudflareClient(CloudflareClientOptions options, HttpClient? httpClient = null)
    {
        _jsonOptions = JsonOptions;
        _httpClient = httpClient ?? new HttpClient(options.Handler ?? new HttpClientHandler());
        _ownsClient = httpClient is null;
        _httpClient.BaseAddress = options.BaseUri;
        if (!string.IsNullOrWhiteSpace(options.BearerToken))
            _httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", options.BearerToken);
        _dispatcher = new CloudflareRuntimeDispatcher(
            options.BaseUri,
            new HttpClientTransport(_httpClient),
            string.IsNullOrWhiteSpace(options.BearerToken) ? null : new ApiTokenAuthenticationContext(options.BearerToken));
    }

    public async IAsyncEnumerable<CfDnsRecord> ListDnsRecordsAsync(
        string zoneId,
        IReadOnlyDictionary<string, object?>? query = null,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var page = 1;
        while (true)
        {
            var values = new Dictionary<string, object?>(StringComparer.Ordinal);
            if (query is not null)
                foreach (var item in query) values[item.Key] = item.Value;
            values["page"] = page;

            var suffix = QuerySerializer.Serialize(values);
            var path = $"zones/{Uri.EscapeDataString(zoneId)}/dns_records{suffix}";
            var result = await SendAsync<List<CfDnsRecord>>(HttpMethod.Get, path, null, cancellationToken).ConfigureAwait(false);
            var records = result ?? [];
            foreach (var record in records) yield return record;
            if (records.Count == 0) yield break;
            page++;
        }
    }

    public Task<CfDnsRecord> GetDnsRecordAsync(string zoneId, string recordId, IReadOnlyDictionary<string, object?>? query = null, CancellationToken cancellationToken = default)
        => SendAsync<CfDnsRecord>(HttpMethod.Get, BuildRecordPath(zoneId, recordId) + QuerySerializer.Serialize(query), null, cancellationToken);

    public Task<CfDnsRecord> CreateDnsRecordAsync(string zoneId, JsonNode body, IReadOnlyDictionary<string, object?>? query = null, CancellationToken cancellationToken = default)
        => SendAsync<CfDnsRecord>(HttpMethod.Post, $"zones/{Uri.EscapeDataString(zoneId)}/dns_records" + QuerySerializer.Serialize(query), body, cancellationToken);

    public Task<CfDnsRecord> UpdateDnsRecordAsync(string zoneId, string recordId, JsonNode body, CancellationToken cancellationToken = default)
        => SendAsync<CfDnsRecord>(HttpMethod.Put, BuildRecordPath(zoneId, recordId), body, cancellationToken);

    public Task<CfDnsRecord> EditDnsRecordAsync(string zoneId, string recordId, JsonNode body, CancellationToken cancellationToken = default)
        => SendAsync<CfDnsRecord>(HttpMethod.Patch, BuildRecordPath(zoneId, recordId), body, cancellationToken);

    public async Task DeleteDnsRecordAsync(string zoneId, string recordId, CancellationToken cancellationToken = default)
        => await _dispatcher.ExecuteAsync<JsonNode>(
            DeleteDnsRecordMetadata,
            new BoundParameters(new Dictionary<string, object?> { ["zoneId"] = zoneId, ["recordId"] = recordId }),
            cancellationToken).ConfigureAwait(false);

    private static RuntimeOperationMetadata DeleteDnsRecordMetadata { get; } = new()
    {
        OperationId = "dns-records-for-a-zone-delete-dns-record",
        Method = HttpMethod.Delete,
        PathTemplate = "zones/{zoneId}/dns_records/{recordId}",
        Parameters =
        [
            new RuntimeParameterMetadata { Name = "zoneId", Location = "path", Required = true },
            new RuntimeParameterMetadata { Name = "recordId", Location = "path", Required = true }
        ],
        ResponseRepresentations =
        [
            new RuntimeResponseRepresentation { StatusCode = 200, ContentType = "application/json", EnvelopePolicy = "CloudflareResult", ParsingMode = "Json" },
            new RuntimeResponseRepresentation { StatusCode = 204, ParsingMode = "NoContent" }
        ]
    };

    private static string BuildRecordPath(string zoneId, string recordId)
        => $"zones/{Uri.EscapeDataString(zoneId)}/dns_records/{Uri.EscapeDataString(recordId)}";

    private async Task<T> SendAsync<T>(HttpMethod method, string relativePath, JsonNode? body, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(method, relativePath);
        if (body is not null)
            request.Content = new StringContent(body.ToJsonString(_jsonOptions), Encoding.UTF8, "application/json");

        HttpResponseMessage response;
        string rawBody;
        try
        {
            response = await _httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken).ConfigureAwait(false);
            rawBody = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            var metadata = new CloudflareResponseMetadata(0, method.Method, new Uri(_httpClient.BaseAddress!, relativePath), new Dictionary<string, IEnumerable<string>>());
            throw new CloudflareApiException(0, [], string.Empty, metadata, ex);
        }

        var metadataHeaders = response.Headers.Concat(response.Content.Headers)
            .GroupBy(h => h.Key, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.SelectMany(h => h.Value), StringComparer.OrdinalIgnoreCase);
        var metadataResponse = new CloudflareResponseMetadata(response.StatusCode, method.Method, response.RequestMessage?.RequestUri ?? new Uri(_httpClient.BaseAddress!, relativePath), metadataHeaders);

        if (!response.IsSuccessStatusCode)
        {
            var errors = TryReadErrors(rawBody);
            throw new CloudflareApiException(response.StatusCode, errors, rawBody, metadataResponse);
        }

        if (response.StatusCode == HttpStatusCode.NoContent || string.IsNullOrWhiteSpace(rawBody))
            return default!;

        try
        {
            var envelope = JsonSerializer.Deserialize<CloudflareEnvelope<T>>(rawBody, _jsonOptions);
            if (envelope is not null && envelope.Result is not null)
                return (T)(object)envelope.Result;
            return JsonSerializer.Deserialize<T>(rawBody, _jsonOptions)!;
        }
        catch (JsonException ex)
        {
            throw new CloudflareApiException(response.StatusCode, [], rawBody, metadataResponse, ex);
        }
    }

    private static IReadOnlyList<CloudflareError> TryReadErrors(string body)
    {
        try
        {
            var envelope = JsonSerializer.Deserialize<CloudflareEnvelope<JsonElement>>(body, JsonOptions);
            return envelope?.Errors ?? [];
        }
        catch (JsonException) { return []; }
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
