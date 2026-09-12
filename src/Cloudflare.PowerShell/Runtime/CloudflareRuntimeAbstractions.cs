using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Cloudflare.PowerShell;

public sealed class CloudflareRequest
{
    public CloudflareRequest(
        HttpMethod method,
        Uri requestUri,
        IReadOnlyDictionary<string, string>? headers = null,
        Func<HttpContent?>? contentFactory = null,
        bool isReplayable = true,
        bool? isRetrySafe = null)
    {
        Method = method;
        RequestUri = requestUri;
        Headers = headers ?? new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        ContentFactory = contentFactory ?? (() => null);
        IsReplayable = isReplayable;
        IsRetrySafe = isRetrySafe ?? (method == HttpMethod.Get || method == HttpMethod.Head || method == HttpMethod.Options);
    }

    public HttpMethod Method { get; }
    public Uri RequestUri { get; }
    public IReadOnlyDictionary<string, string> Headers { get; }
    public Func<HttpContent?> ContentFactory { get; }
    public bool IsReplayable { get; }
    public bool IsRetrySafe { get; }
}

public sealed class CloudflareResponse : IAsyncDisposable
{
    private readonly HttpResponseMessage _response;

    public CloudflareResponse(HttpResponseMessage response)
    {
        _response = response;
    }

    public HttpStatusCode StatusCode => _response.StatusCode;
    public bool IsSuccessStatusCode => _response.IsSuccessStatusCode;
    public Uri? RequestUri => _response.RequestMessage?.RequestUri;
    public IEnumerable<KeyValuePair<string, IEnumerable<string>>> Headers => _response.Headers.Concat(_response.Content.Headers);

    public Task<string> ReadAsStringAsync(CancellationToken cancellationToken = default)
        => _response.Content.ReadAsStringAsync(cancellationToken);

    public Task<byte[]> ReadAsByteArrayAsync(CancellationToken cancellationToken = default)
        => _response.Content.ReadAsByteArrayAsync(cancellationToken);

    public Task<Stream> ReadAsStreamAsync(CancellationToken cancellationToken = default)
        => _response.Content.ReadAsStreamAsync(cancellationToken);

    public CloudflareResponseMetadata Metadata(Uri requestUri)
    {
        var headers = Headers
            .GroupBy(x => x.Key, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(x => x.Key, x => x.SelectMany(y => y.Value), StringComparer.OrdinalIgnoreCase);
        return new CloudflareResponseMetadata(
            StatusCode,
            _response.RequestMessage?.Method.Method ?? string.Empty,
            RequestUri ?? requestUri,
            headers);
    }

    public ValueTask DisposeAsync()
    {
        _response.Dispose();
        return ValueTask.CompletedTask;
    }
}

public interface ICloudflareTransport
{
    Task<CloudflareResponse> SendAsync(CloudflareRequest request, CancellationToken cancellationToken = default);
}

public sealed class HttpClientTransport : ICloudflareTransport, IDisposable
{
    private readonly HttpClient _httpClient;
    private readonly bool _ownsClient;

    public HttpClientTransport(HttpClient httpClient, bool ownsClient = false)
    {
        _httpClient = httpClient;
        _ownsClient = ownsClient;
    }

    public async Task<CloudflareResponse> SendAsync(CloudflareRequest request, CancellationToken cancellationToken = default)
    {
        using var message = new HttpRequestMessage(request.Method, request.RequestUri);
        foreach (var header in request.Headers)
            message.Headers.TryAddWithoutValidation(header.Key, header.Value);
        message.Content = request.ContentFactory();
        var response = await _httpClient.SendAsync(message, HttpCompletionOption.ResponseHeadersRead, cancellationToken).ConfigureAwait(false);
        return new CloudflareResponse(response);
    }

    public void Dispose()
    {
        if (_ownsClient) _httpClient.Dispose();
    }
}

public interface IAuthenticationContext
{
    void Apply(IDictionary<string, string> headers);
}

public sealed class ApiTokenAuthenticationContext : IAuthenticationContext
{
    public ApiTokenAuthenticationContext(string apiToken)
    {
        if (string.IsNullOrWhiteSpace(apiToken)) throw new ArgumentException("API token is required.", nameof(apiToken));
        ApiToken = apiToken;
    }

    public string ApiToken { get; }

    public void Apply(IDictionary<string, string> headers)
        => headers["Authorization"] = "Bearer " + ApiToken;
}

public sealed class BoundParameters
{
    private readonly IReadOnlyDictionary<string, object?> _values;

    public BoundParameters(IReadOnlyDictionary<string, object?> values)
    {
        _values = values;
    }

    public bool TryGetValue(string name, out object? value) => _values.TryGetValue(name, out value);
    public object? this[string name] => _values.TryGetValue(name, out var value) ? value : null;
    public IReadOnlyDictionary<string, object?> Values => _values;
}

public sealed class RuntimeParameterMetadata
{
    public string Name { get; init; } = string.Empty;
    public string Location { get; init; } = "query";
    public bool Required { get; init; }
}

public sealed class RuntimeMultipartPart
{
    public string ParameterName { get; init; } = string.Empty;
    public string PartName { get; init; } = string.Empty;
    public string ContentType { get; init; } = "text/plain";
    public string Format { get; init; } = "string";
    public bool Required { get; init; }
}

public sealed class RuntimeRequestRepresentation
{
    public string ContentType { get; init; } = string.Empty;
    public string BodyParameterName { get; init; } = "body";
    public IReadOnlyList<RuntimeMultipartPart> Parts { get; init; } = [];
}

public sealed class RuntimeResponseRepresentation
{
    public int? StatusCode { get; init; }
    public string ContentType { get; init; } = string.Empty;
    public string EnvelopePolicy { get; init; } = "Raw";
    public string ParsingMode { get; init; } = "Json";
}

public sealed class RuntimeOperationMetadata
{
    public string OperationId { get; init; } = string.Empty;
    public HttpMethod Method { get; init; } = HttpMethod.Get;
    public string PathTemplate { get; init; } = string.Empty;
    public IReadOnlyList<RuntimeParameterMetadata> Parameters { get; init; } = [];
    public IReadOnlyList<RuntimeRequestRepresentation> RequestRepresentations { get; init; } = [];
    public IReadOnlyList<RuntimeResponseRepresentation> ResponseRepresentations { get; init; } = [];
    public RuntimeIdempotencyMetadata? Idempotency { get; init; }
}

public sealed record SerializedRequestContent(Func<HttpContent?> Factory, bool IsReplayable);

public interface ICloudflareRequestSerializer
{
    bool CanSerialize(string contentType);
    SerializedRequestContent Serialize(RuntimeRequestRepresentation representation, BoundParameters parameters);
}

public sealed class JsonRequestSerializer : ICloudflareRequestSerializer
{
    private static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web);

    public bool CanSerialize(string contentType) => contentType.Equals("application/json", StringComparison.OrdinalIgnoreCase);

    public SerializedRequestContent Serialize(RuntimeRequestRepresentation representation, BoundParameters parameters)
    {
        var value = parameters[representation.BodyParameterName];
        var json = JsonSerializer.Serialize(value, Options);
        return new SerializedRequestContent(
            () => new StringContent(json, Encoding.UTF8, representation.ContentType),
            true);
    }
}

public sealed class MultipartRequestSerializer : ICloudflareRequestSerializer
{
    public bool CanSerialize(string contentType) => contentType.Equals("multipart/form-data", StringComparison.OrdinalIgnoreCase);

    public SerializedRequestContent Serialize(RuntimeRequestRepresentation representation, BoundParameters parameters)
    {
        var replayable = representation.Parts.All(part => IsReplayable(parameters[part.ParameterName]));
        return new SerializedRequestContent(
            () => CreateContent(representation, parameters),
            replayable);
    }

    private static HttpContent CreateContent(RuntimeRequestRepresentation representation, BoundParameters parameters)
    {
        var multipart = new MultipartFormDataContent();
        foreach (var part in representation.Parts)
        {
            var value = parameters[part.ParameterName];
            if (value is null)
            {
                if (part.Required) throw new InvalidOperationException($"Required multipart part '{part.PartName}' is missing.");
                continue;
            }

            HttpContent content = value switch
            {
                byte[] bytes => new ByteArrayContent(bytes),
                Stream stream => CreateStreamContent(stream),
                _ => new StringContent(Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture) ?? string.Empty, Encoding.UTF8)
            };
            content.Headers.ContentType = new MediaTypeHeaderValue(part.ContentType);
            multipart.Add(content, part.PartName);
        }
        return multipart;
    }

    private static HttpContent CreateStreamContent(Stream stream)
    {
        if (stream.CanSeek) stream.Position = 0;
        return new StreamContent(new NonDisposingStream(stream));
    }

    private static bool IsReplayable(object? value)
        => value is null or byte[] or string or not Stream;

    private sealed class NonDisposingStream : Stream
    {
        private readonly Stream _inner;

        public NonDisposingStream(Stream inner) => _inner = inner;

        public override bool CanRead => _inner.CanRead;
        public override bool CanSeek => _inner.CanSeek;
        public override bool CanWrite => _inner.CanWrite;
        public override long Length => _inner.Length;
        public override long Position { get => _inner.Position; set => _inner.Position = value; }
        public override void Flush() => _inner.Flush();
        public override Task FlushAsync(CancellationToken cancellationToken) => _inner.FlushAsync(cancellationToken);
        public override int Read(byte[] buffer, int offset, int count) => _inner.Read(buffer, offset, count);
        public override int Read(Span<byte> buffer) => _inner.Read(buffer);
        public override Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken) => _inner.ReadAsync(buffer, offset, count, cancellationToken);
        public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default) => _inner.ReadAsync(buffer, cancellationToken);
        public override long Seek(long offset, SeekOrigin origin) => _inner.Seek(offset, origin);
        public override void SetLength(long value) => _inner.SetLength(value);
        public override void Write(byte[] buffer, int offset, int count) => _inner.Write(buffer, offset, count);
        public override void Write(ReadOnlySpan<byte> buffer) => _inner.Write(buffer);
        public override Task WriteAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken) => _inner.WriteAsync(buffer, offset, count, cancellationToken);
        public override ValueTask WriteAsync(ReadOnlyMemory<byte> buffer, CancellationToken cancellationToken = default) => _inner.WriteAsync(buffer, cancellationToken);

        protected override void Dispose(bool disposing)
        {
            // The caller owns the supplied stream; disposing request content must
            // not close it.
            base.Dispose(disposing);
        }

        public override ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }
}

public interface ICloudflareRetryPolicy
{
    bool ShouldRetry(CloudflareRequest request, CloudflareResponse? response, Exception? exception, int retryCount);
    TimeSpan GetDelay(CloudflareResponse? response, int retryCount);
}

public sealed class NoRetryPolicy : ICloudflareRetryPolicy
{
    public bool ShouldRetry(CloudflareRequest request, CloudflareResponse? response, Exception? exception, int retryCount) => false;
    public TimeSpan GetDelay(CloudflareResponse? response, int retryCount) => TimeSpan.Zero;
}

public interface ICloudflareResponseParser
{
    bool CanParse(RuntimeResponseRepresentation representation);
    Task<object?> ParseAsync(Type targetType, CloudflareRequest request, CloudflareResponse response, RuntimeResponseRepresentation representation, CancellationToken cancellationToken = default);
}

public sealed class NoContentResponseParser : ICloudflareResponseParser
{
    public bool CanParse(RuntimeResponseRepresentation representation)
        => representation.ParsingMode.Equals("NoContent", StringComparison.OrdinalIgnoreCase);

    public Task<object?> ParseAsync(Type targetType, CloudflareRequest request, CloudflareResponse response, RuntimeResponseRepresentation representation, CancellationToken cancellationToken = default)
        => Task.FromResult<object?>(null);
}

public sealed class RawTextResponseParser : ICloudflareResponseParser
{
    public bool CanParse(RuntimeResponseRepresentation representation)
        => representation.ParsingMode.Equals("RawText", StringComparison.OrdinalIgnoreCase)
           || representation.ParsingMode.Equals("Text", StringComparison.OrdinalIgnoreCase);

    public async Task<object?> ParseAsync(Type targetType, CloudflareRequest request, CloudflareResponse response, RuntimeResponseRepresentation representation, CancellationToken cancellationToken = default)
        => await response.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
}

public sealed class BinaryResponseParser : ICloudflareResponseParser
{
    public bool CanParse(RuntimeResponseRepresentation representation)
        => representation.ParsingMode.Equals("Binary", StringComparison.OrdinalIgnoreCase);

    public async Task<object?> ParseAsync(Type targetType, CloudflareRequest request, CloudflareResponse response, RuntimeResponseRepresentation representation, CancellationToken cancellationToken = default)
        => new CloudflareResponseStream(await response.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false), response);
}

public sealed class JsonResponseParser : ICloudflareResponseParser
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true
    };

    public bool CanParse(RuntimeResponseRepresentation representation)
        => representation.ParsingMode.Equals("Json", StringComparison.OrdinalIgnoreCase);

    public async Task<object?> ParseAsync(Type targetType, CloudflareRequest request, CloudflareResponse response, RuntimeResponseRepresentation representation, CancellationToken cancellationToken = default)
    {
        var rawBody = await response.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(rawBody)) return null;
        if (representation.EnvelopePolicy.Equals("CloudflareResult", StringComparison.OrdinalIgnoreCase))
        {
            var envelopeType = typeof(CloudflareEnvelope<>).MakeGenericType(targetType);
            var envelope = JsonSerializer.Deserialize(rawBody, envelopeType, JsonOptions);
            var result = envelopeType.GetProperty(nameof(CloudflareEnvelope<object>.Result))?.GetValue(envelope);
            if (result is not null) return result;
        }
        return JsonSerializer.Deserialize(rawBody, targetType, JsonOptions);
    }
}

public sealed class CloudflareRuntimeDispatcher
{
    private static readonly JsonSerializerOptions ErrorJsonOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true
    };

    private readonly Uri _baseUri;
    private readonly ICloudflareTransport _transport;
    private readonly IAuthenticationContext? _authentication;
    private readonly IReadOnlyList<ICloudflareRequestSerializer> _serializers;
    private readonly IReadOnlyList<ICloudflareResponseParser> _parsers;
    private readonly CloudflarePaginationExecutor _pagination;
    private readonly ICloudflareRetryPolicy _retryPolicy;

    public CloudflareRuntimeDispatcher(
        Uri baseUri,
        ICloudflareTransport transport,
        IAuthenticationContext? authentication = null,
        IEnumerable<ICloudflareRequestSerializer>? serializers = null,
        IEnumerable<ICloudflareResponseParser>? parsers = null,
        CloudflarePaginationExecutor? pagination = null,
        ICloudflareRetryPolicy? retryPolicy = null)
    {
        _baseUri = baseUri;
        _transport = transport;
        _authentication = authentication;
        _serializers = serializers?.ToList() ?? [new JsonRequestSerializer(), new MultipartRequestSerializer()];
        _parsers = parsers?.ToList() ?? [new NoContentResponseParser(), new RawTextResponseParser(), new BinaryResponseParser(), new JsonResponseParser()];
        _pagination = pagination ?? new CloudflarePaginationExecutor();
        _retryPolicy = retryPolicy ?? new NoRetryPolicy();
    }

    public IAsyncEnumerable<TItem> ExecutePagedAsync<TResponse, TItem>(
        RuntimeOperationMetadata metadata,
        BoundParameters parameters,
        RuntimePaginationMetadata pagination,
        Func<TResponse, RuntimePage<TItem>> pageAdapter,
        CancellationToken cancellationToken = default)
    {
        async Task<RuntimePage<TItem>> FetchPage(IReadOnlyDictionary<string, object?> pageParameters, CancellationToken token)
        {
            var response = await ExecuteAsync<TResponse>(metadata, new BoundParameters(pageParameters), token).ConfigureAwait(false);
            return pageAdapter(response!);
        }

        return _pagination.ExecuteAsync(FetchPage, parameters.Values, pagination, cancellationToken);
    }

    public IAsyncEnumerable<TItem> ExecutePagedAsync<TItem>(
        RuntimeOperationMetadata metadata,
        BoundParameters parameters,
        RuntimePaginationMetadata pagination,
        CancellationToken cancellationToken = default)
    {
        async Task<RuntimePage<TItem>> FetchPage(IReadOnlyDictionary<string, object?> pageParameters, CancellationToken token)
        {
            var response = await ExecuteRawJsonAsync(metadata, new BoundParameters(pageParameters), token).ConfigureAwait(false);
            return CloudflarePaginationResponseAdapter.FromJson<TItem>(response, pagination);
        }

        return _pagination.ExecuteAsync(FetchPage, parameters.Values, pagination, cancellationToken);
    }

    public Task<T?> ExecuteAsync<T>(RuntimeOperationMetadata metadata, BoundParameters parameters, CancellationToken cancellationToken = default)
        => ExecuteAsyncCore<T>(metadata, parameters, cancellationToken, preserveJsonEnvelope: false);

    private Task<JsonNode?> ExecuteRawJsonAsync(RuntimeOperationMetadata metadata, BoundParameters parameters, CancellationToken cancellationToken)
        => ExecuteAsyncCore<JsonNode>(metadata, parameters, cancellationToken, preserveJsonEnvelope: true);

    private async Task<T?> ExecuteAsyncCore<T>(RuntimeOperationMetadata metadata, BoundParameters parameters, CancellationToken cancellationToken, bool preserveJsonEnvelope)
    {
        CloudflareRequest request;
        try
        {
            request = BuildRequest(metadata, parameters);
        }
        catch (Exception ex) when (ex is ArgumentException or FormatException or InvalidOperationException or NotSupportedException or JsonException)
        {
            throw CreateConstructionException(metadata, ex);
        }
        var retryCount = 0;
        while (true)
        {
            CloudflareResponse? response = null;
            try
            {
                response = await _transport.SendAsync(request, cancellationToken).ConfigureAwait(false);
                if (_retryPolicy.ShouldRetry(request, response, null, retryCount) && request.IsReplayable)
                {
                    var delay = _retryPolicy.GetDelay(response, retryCount);
                    await response.DisposeAsync().ConfigureAwait(false);
                    response = null;
                    await Task.Delay(delay, cancellationToken).ConfigureAwait(false);
                    retryCount++;
                    continue;
                }

                var result = await ParseResponseAsync<T>(request, response, metadata, retryCount, cancellationToken, preserveJsonEnvelope).ConfigureAwait(false);
                if (result is CloudflareResponseStream) response = null;
                return result;
            }
            catch (Exception ex) when (ex is HttpRequestException or IOException or TaskCanceledException)
            {
                if (cancellationToken.IsCancellationRequested) throw;
                if (_retryPolicy.ShouldRetry(request, response, ex, retryCount) && request.IsReplayable)
                {
                    var delay = _retryPolicy.GetDelay(response, retryCount);
                    if (response is not null) await response.DisposeAsync().ConfigureAwait(false);
                    response = null;
                    await Task.Delay(delay, cancellationToken).ConfigureAwait(false);
                    retryCount++;
                    continue;
                }

                var requestMetadata = new CloudflareResponseMetadata((HttpStatusCode)0, request.Method.Method, request.RequestUri, new Dictionary<string, IEnumerable<string>>());
                throw new CloudflareApiException((HttpStatusCode)0, [], string.Empty, requestMetadata, ex, retryCount);
            }
            catch (Exception ex) when (ex is ArgumentException or FormatException or InvalidOperationException or NotSupportedException or JsonException or IOException)
            {
                throw CreateConstructionException(request, ex, retryCount);
            }
            finally
            {
                if (response is not null) await response.DisposeAsync().ConfigureAwait(false);
            }
        }
    }

    private CloudflareApiException CreateConstructionException(RuntimeOperationMetadata metadata, Exception exception)
    {
        var uri = new Uri(_baseUri, metadata.PathTemplate.TrimStart('/'));
        var requestMetadata = new CloudflareResponseMetadata((HttpStatusCode)0, metadata.Method.Method, uri, new Dictionary<string, IEnumerable<string>>());
        return new CloudflareApiException((HttpStatusCode)0, [], string.Empty, requestMetadata, exception);
    }

    private static CloudflareApiException CreateConstructionException(CloudflareRequest request, Exception exception, int retryCount)
    {
        var requestMetadata = new CloudflareResponseMetadata((HttpStatusCode)0, request.Method.Method, request.RequestUri, new Dictionary<string, IEnumerable<string>>());
        return new CloudflareApiException((HttpStatusCode)0, [], string.Empty, requestMetadata, exception, retryCount);
    }

    private CloudflareRequest BuildRequest(RuntimeOperationMetadata metadata, BoundParameters parameters)
    {
        var path = metadata.PathTemplate;
        var query = new Dictionary<string, object?>(StringComparer.Ordinal);
        var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var parameter in metadata.Parameters)
        {
            var value = parameters[parameter.Name];
            if (parameter.Required && value is null)
                throw new ArgumentException($"Required parameter '{parameter.Name}' is missing.", parameter.Name);
            if (value is null) continue;

            switch (parameter.Location.ToLowerInvariant())
            {
                case "path":
                    path = path.Replace("{" + parameter.Name + "}", Uri.EscapeDataString(Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture) ?? string.Empty), StringComparison.Ordinal);
                    break;
                case "header":
                    headers[parameter.Name] = Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture) ?? string.Empty;
                    break;
                default:
                    query[parameter.Name] = value;
                    break;
            }
        }

        _authentication?.Apply(headers);
        var retrySafe = metadata.Method == HttpMethod.Get || metadata.Method == HttpMethod.Head || metadata.Method == HttpMethod.Options;
        if (metadata.Idempotency is { Supported: true } idempotency)
        {
            if (idempotency.AutoGenerate)
                throw new NotSupportedException("Automatic idempotency-key generation is not enabled without an explicit operation policy.");
            if (!string.IsNullOrWhiteSpace(idempotency.KeyParameterName) && parameters[idempotency.KeyParameterName] is { } key)
            {
                headers[idempotency.HeaderName] = Convert.ToString(key, System.Globalization.CultureInfo.InvariantCulture) ?? string.Empty;
                retrySafe = idempotency.RetrySafeWhenKeyPresent;
            }
        }
        var representation = metadata.RequestRepresentations.FirstOrDefault();
        var serialized = representation is null
            ? new SerializedRequestContent(() => null, true)
            : FindSerializer(representation.ContentType).Serialize(representation, parameters);
        var uri = new Uri(_baseUri, path.TrimStart('/') + QuerySerializer.Serialize(query));
        return new CloudflareRequest(metadata.Method, uri, headers, serialized.Factory, serialized.IsReplayable, retrySafe);
    }

    private ICloudflareRequestSerializer FindSerializer(string contentType)
        => _serializers.FirstOrDefault(serializer => serializer.CanSerialize(contentType))
           ?? throw new NotSupportedException($"No request serializer is registered for '{contentType}'.");

    private async Task<T?> ParseResponseAsync<T>(CloudflareRequest request, CloudflareResponse response, RuntimeOperationMetadata metadata, int retryCount, CancellationToken cancellationToken, bool preserveJsonEnvelope)
    {
        var representation = SelectResponseRepresentation(response, metadata.ResponseRepresentations);
        try
        {
            if (!response.IsSuccessStatusCode)
            {
                var rawError = await response.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
                throw new CloudflareApiException(response.StatusCode, TryReadErrors(rawError), rawError, response.Metadata(request.RequestUri), retryCount: retryCount);
            }

            if (preserveJsonEnvelope && representation.ParsingMode.Equals("Json", StringComparison.OrdinalIgnoreCase))
            {
                representation = new RuntimeResponseRepresentation
                {
                    StatusCode = representation.StatusCode,
                    ContentType = representation.ContentType,
                    EnvelopePolicy = "Raw",
                    ParsingMode = representation.ParsingMode
                };
            }

            var parser = _parsers.FirstOrDefault(x => x.CanParse(representation))
                ?? throw new NotSupportedException($"No response parser is registered for '{representation.ParsingMode}'.");
            return (T?)await parser.ParseAsync(typeof(T), request, response, representation, cancellationToken).ConfigureAwait(false);
        }
        catch (CloudflareApiException)
        {
            throw;
        }
        catch (Exception ex) when (ex is JsonException or IOException or InvalidOperationException or NotSupportedException)
        {
            string rawBody;
            try { rawBody = await response.ReadAsStringAsync(cancellationToken).ConfigureAwait(false); }
            catch { rawBody = string.Empty; }
            throw new CloudflareApiException(response.StatusCode, [], rawBody, response.Metadata(request.RequestUri), ex, retryCount);
        }
    }

    private static RuntimeResponseRepresentation SelectResponseRepresentation(CloudflareResponse response, IReadOnlyList<RuntimeResponseRepresentation> representations)
    {
        var byStatus = representations.Where(x => x.StatusCode is null || x.StatusCode == (int)response.StatusCode).ToList();
        var contentType = response.Headers.FirstOrDefault(x => x.Key.Equals("Content-Type", StringComparison.OrdinalIgnoreCase)).Value?.FirstOrDefault()?.Split(';')[0].Trim();
        return byStatus.FirstOrDefault(x => string.IsNullOrWhiteSpace(x.ContentType) || x.ContentType.Equals(contentType, StringComparison.OrdinalIgnoreCase))
            ?? byStatus.FirstOrDefault()
            ?? new RuntimeResponseRepresentation { ParsingMode = "Json" };
    }

    private static IReadOnlyList<CloudflareError> TryReadErrors(string body)
    {
        try
        {
            var envelope = JsonSerializer.Deserialize<CloudflareEnvelope<JsonElement>>(body, ErrorJsonOptions);
            return envelope?.Errors ?? [];
        }
        catch (JsonException) { return []; }
    }
}

public sealed class CloudflareResponseStream : Stream
{
    private readonly Stream _inner;
    private readonly CloudflareResponse _response;

    public CloudflareResponseStream(Stream inner, CloudflareResponse response)
    {
        _inner = inner;
        _response = response;
    }

    public override bool CanRead => _inner.CanRead;
    public override bool CanSeek => _inner.CanSeek;
    public override bool CanWrite => _inner.CanWrite;
    public override long Length => _inner.Length;
    public override long Position { get => _inner.Position; set => _inner.Position = value; }
    public override void Flush() => _inner.Flush();
    public override Task FlushAsync(CancellationToken cancellationToken) => _inner.FlushAsync(cancellationToken);
    public override int Read(byte[] buffer, int offset, int count) => _inner.Read(buffer, offset, count);
    public override int Read(Span<byte> buffer) => _inner.Read(buffer);
    public override Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken) => _inner.ReadAsync(buffer, offset, count, cancellationToken);
    public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default) => _inner.ReadAsync(buffer, cancellationToken);
    public override long Seek(long offset, SeekOrigin origin) => _inner.Seek(offset, origin);
    public override void SetLength(long value) => _inner.SetLength(value);
    public override void Write(byte[] buffer, int offset, int count) => _inner.Write(buffer, offset, count);
    public override void Write(ReadOnlySpan<byte> buffer) => _inner.Write(buffer);
    public override Task WriteAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken) => _inner.WriteAsync(buffer, offset, count, cancellationToken);
    public override ValueTask WriteAsync(ReadOnlyMemory<byte> buffer, CancellationToken cancellationToken = default) => _inner.WriteAsync(buffer, cancellationToken);

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _inner.Dispose();
            _response.DisposeAsync().AsTask().GetAwaiter().GetResult();
        }
        base.Dispose(disposing);
    }

    public override async ValueTask DisposeAsync()
    {
        await _inner.DisposeAsync().ConfigureAwait(false);
        await _response.DisposeAsync().ConfigureAwait(false);
        GC.SuppressFinalize(this);
    }
}
