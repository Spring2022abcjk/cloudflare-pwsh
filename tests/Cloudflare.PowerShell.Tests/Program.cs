using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;
using Cloudflare.PowerShell;

var tests = new (string Name, Action Run)[]
{
    ("query serialization", TestQuerySerialization),
    ("list pagination and envelope", TestListPagination),
    ("create request and discriminator", TestCreate),
    ("delete has no body", TestDelete),
    ("put and patch bindings", TestPutPatch),
    ("omitted versus explicit null", TestPresence),
    ("presence-aware optional and typed union", TestOptionalAndUnion),
    ("stable error contract", TestErrors)
};

var failures = new List<string>();
foreach (var test in tests)
{
    try { test.Run(); Console.WriteLine($"PASS {test.Name}"); }
    catch (Exception ex) { failures.Add($"FAIL {test.Name}: {ex.Message}"); }
}

if (failures.Count > 0)
{
    foreach (var failure in failures) Console.Error.WriteLine(failure);
    return 1;
}

Console.WriteLine($"PASS total={tests.Length}");
return 0;

static void TestQuerySerialization()
{
    var query = new Dictionary<string, object?>
    {
        ["z"] = "last",
        ["tag"] = new[] { "A", "B" },
        ["match"] = new Dictionary<string, object?> { ["exact"] = "example.com" },
        ["omitted"] = null
    };
    Equal("?match.exact=example.com&tag=A&tag=B&z=last", QuerySerializer.Serialize(query));
}

static void TestListPagination()
{
    var handler = new SequenceHandler(
        Json(HttpStatusCode.OK, "{\"success\":true,\"result\":[{\"id\":\"1\",\"name\":\"a\",\"type\":\"A\"}],\"result_info\":{\"page\":1}}"),
        Json(HttpStatusCode.OK, "{\"success\":true,\"result\":[{\"id\":\"2\",\"name\":\"b\",\"type\":\"MX\"}],\"result_info\":{\"page\":2}}"),
        Json(HttpStatusCode.OK, "{\"success\":true,\"result\":[],\"result_info\":{\"page\":3}}"));
    using var http = new HttpClient(handler);
    using var client = new CloudflareClient(new CloudflareClientOptions { BaseUri = new Uri("https://mock.test/client/v4/"), BearerToken = "token" }, http);
    var records = new List<CfDnsRecord>();
    var async = client.ListDnsRecordsAsync("zone id", new Dictionary<string, object?>
    {
        ["match"] = new Dictionary<string, object?> { ["exact"] = "example.com" },
        ["tag"] = new[] { "one", "two" },
        ["optional"] = null
    });
    var enumerator = async.GetAsyncEnumerator();
    try { while (enumerator.MoveNextAsync().GetAwaiter().GetResult()) records.Add(enumerator.Current); }
    finally { enumerator.DisposeAsync().GetAwaiter().GetResult(); }
    Equal(2, records.Count);
    Equal(3, handler.Requests.Count);
    Equal("/client/v4/zones/zone%20id/dns_records?match.exact=example.com&page=1&tag=one&tag=two", handler.Requests[0].RequestUri!.PathAndQuery);
    Equal("Bearer", handler.Requests[0].Headers.Authorization!.Scheme);
}

static void TestCreate()
{
    var handler = new SequenceHandler(Json(HttpStatusCode.OK, "{\"success\":true,\"result\":{\"id\":\"r1\",\"type\":\"A\",\"content\":\"198.51.100.4\"}}"));
    using var http = new HttpClient(handler);
    using var client = new CloudflareClient(new CloudflareClientOptions { BaseUri = new Uri("https://mock.test/client/v4/"), BearerToken = "token" }, http);
    var body = new JsonObject { ["name"] = "www.example.com", ["ttl"] = 300, ["type"] = "A", ["content"] = "198.51.100.4" };
    var record = client.CreateDnsRecordAsync("zone", body).GetAwaiter().GetResult();
    Equal("r1", record.Id);
    Equal(HttpMethod.Post, handler.Requests[0].Method);
    Equal("{\"name\":\"www.example.com\",\"ttl\":300,\"type\":\"A\",\"content\":\"198.51.100.4\"}", handler.Requests[0].Body);
}

static void TestDelete()
{
    var handler = new SequenceHandler(Json(HttpStatusCode.OK, "{\"success\":true,\"result\":{}}"));
    using var http = new HttpClient(handler);
    using var client = new CloudflareClient(new CloudflareClientOptions { BaseUri = new Uri("https://mock.test/client/v4/"), BearerToken = "token" }, http);
    client.DeleteDnsRecordAsync("zone", "record").GetAwaiter().GetResult();
    Equal(HttpMethod.Delete, handler.Requests[0].Method);
    Equal(null, handler.Requests[0].Body);
    Equal("/client/v4/zones/zone/dns_records/record", handler.Requests[0].RequestUri!.PathAndQuery);
}

static void TestPutPatch()
{
    var handler = new SequenceHandler(
        Json(HttpStatusCode.OK, "{\"result\":{\"id\":\"put\"}}"),
        Json(HttpStatusCode.OK, "{\"result\":{\"id\":\"patch\"}}"));
    using var http = new HttpClient(handler);
    using var client = new CloudflareClient(new CloudflareClientOptions { BaseUri = new Uri("https://mock.test/client/v4/") }, http);
    var body = new JsonObject { ["name"] = "example.com", ["ttl"] = 60, ["type"] = "A", ["content"] = "198.51.100.4" };
    Equal("put", client.UpdateDnsRecordAsync("z", "r", body).GetAwaiter().GetResult().Id);
    Equal("patch", client.EditDnsRecordAsync("z", "r", body).GetAwaiter().GetResult().Id);
    Equal(HttpMethod.Put, handler.Requests[0].Method);
    Equal(HttpMethod.Patch, handler.Requests[1].Method);
}

static void TestPresence()
{
    var omitted = new JsonObject { ["name"] = "example.com" };
    var explicitNull = new JsonObject { ["name"] = "example.com", ["content"] = null };
    True(!omitted.ContainsKey("content"));
    True(explicitNull.ContainsKey("content"));
    True(explicitNull.ToJsonString().Contains("\"content\":null", StringComparison.Ordinal));
}

static void TestOptionalAndUnion()
{
    var omitted = Optional<string?>.Omitted;
    var explicitNull = Optional<string?>.From(null);
    var value = Optional<string?>.From("value");
    True(!omitted.IsSpecified);
    True(explicitNull.IsSpecified && explicitNull.Value is null);
    True(value.IsSpecified && value.Value == "value");
    static JsonObject SerializeOptional(Optional<string?> optional)
    {
        var json = new JsonObject();
        if (optional.IsSpecified) json["field"] = optional.Value;
        return json;
    }
    True(!SerializeOptional(omitted).ContainsKey("field"));
    True(SerializeOptional(explicitNull).ContainsKey("field") && SerializeOptional(explicitNull)["field"] is null);
    Equal("value", SerializeOptional(value)["field"]!.GetValue<string>());

    var a = new CfARecordInput
    {
        Name = Optional<string?>.From("example.com"),
        Ttl = Optional<int>.From(300),
        Content = Optional<string?>.From("198.51.100.4")
    };
    Equal("A", a.Type);
    var json = a.ToJson().ToJsonString();
    True(json.Contains("\"type\":\"A\"", StringComparison.Ordinal));
    True(!json.Contains("priority", StringComparison.Ordinal));

    var mx = new CfMxRecordInput { Priority = Optional<int>.From(10) };
    Equal("MX", mx.Type);
    True(mx.ToJson().ContainsKey("priority"));

    var variants = new CfDnsRecordInput[] { new CfARecordInput(), new CfMxRecordInput(), new CfCaaRecordInput(), new CfHttpsRecordInput(), new CfSvcbRecordInput() };
    Equal("A,CAA,HTTPS,MX,SVCB", string.Join(',', variants.Select(x => x.Type).OrderBy(x => x, StringComparer.Ordinal)));
}

static void TestErrors()
{
    foreach (var status in new[] { 400, 401, 403, 404, 409, 422, 429, 500, 503 })
    {
        var handler = new SequenceHandler(Json((HttpStatusCode)status, "{\"success\":false,\"errors\":[{\"code\":1001,\"message\":\"bad request\"}]}"));
        using var http = new HttpClient(handler);
        using var client = new CloudflareClient(new CloudflareClientOptions { BaseUri = new Uri("https://mock.test/") }, http);
        try { client.GetDnsRecordAsync("z", "r").GetAwaiter().GetResult(); throw new InvalidOperationException("expected error"); }
        catch (CloudflareApiException ex)
        {
            Equal(status, (int)ex.StatusCode);
            Equal("Cloudflare.Api." + status, ex.FullyQualifiedErrorId);
            Equal(1001, ex.Errors[0].Code);
            Equal("bad request", ex.Errors[0].Message);
            True(ex.RawBody.Contains("errors", StringComparison.Ordinal));
        }
    }

    var transport = new SequenceHandler(new HttpRequestException("offline"));
    using var transportHttp = new HttpClient(transport);
    using var transportClient = new CloudflareClient(new CloudflareClientOptions { BaseUri = new Uri("https://mock.test/") }, transportHttp);
    try { transportClient.GetDnsRecordAsync("z", "r").GetAwaiter().GetResult(); throw new InvalidOperationException("expected transport error"); }
    catch (CloudflareApiException ex) { Equal(0, (int)ex.StatusCode); True(ex.InnerException is HttpRequestException); }
}

static HttpResponseMessage Json(HttpStatusCode status, string body)
{
    return new HttpResponseMessage(status) { Content = new StringContent(body, Encoding.UTF8, "application/json") };
}

static void Equal<T>(T expected, T actual)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual)) throw new InvalidOperationException($"expected '{expected}', got '{actual}'");
}

static void True(bool value)
{
    if (!value) throw new InvalidOperationException("assertion failed");
}

sealed class SequenceHandler : HttpMessageHandler
{
    private readonly Queue<object> _responses;
    public List<CapturedRequest> Requests { get; } = [];
    public SequenceHandler(params object[] responses) => _responses = new Queue<object>(responses);

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var body = request.Content is null ? null : await request.Content.ReadAsStringAsync(cancellationToken);
        Requests.Add(new CapturedRequest(request.Method, request.RequestUri, request.Headers, body));
        var next = _responses.Dequeue();
        if (next is Exception exception) throw exception;
        return (HttpResponseMessage)next;
    }
}

sealed record CapturedRequest(HttpMethod Method, Uri? RequestUri, HttpRequestHeaders Headers, string? Body);
