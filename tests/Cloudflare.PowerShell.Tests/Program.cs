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
    ("stable error contract", TestErrors),
    ("generated metadata adapter contract", TestGeneratedMetadataAdapter),
    ("generic JSON dispatcher", TestGenericJsonDispatcher),
    ("raw text dispatcher", TestRawTextDispatcher),
    ("binary dispatcher and stream ownership", TestBinaryDispatcher),
    ("multipart dispatcher", TestMultipartDispatcher),
    ("normalized pagination envelope and cursor paths", TestNormalizedPaginationResponseAdapter),
    ("pagination strategies", TestPaginationStrategies),
    ("retry policy and headers", TestRetryPolicy),
    ("non-replayable request is not retried", TestNonReplayableRequest),
    ("multipart stream ownership", TestMultipartStreamOwnership)
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

static void TestGenericJsonDispatcher()
{
    var handler = new SequenceHandler(Json(HttpStatusCode.OK, "{\"success\":true,\"result\":{\"id\":\"r1\",\"type\":\"A\",\"name\":\"example.com\"}}"));
    using var http = new HttpClient(handler);
    using var transport = new HttpClientTransport(http);
    var dispatcher = new CloudflareRuntimeDispatcher(
        new Uri("https://mock.test/client/v4/"),
        transport,
        new ApiTokenAuthenticationContext("token"));
    var metadata = new RuntimeOperationMetadata
    {
        OperationId = "dns-record-get",
        Method = HttpMethod.Get,
        PathTemplate = "zones/{zoneId}/dns_records/{recordId}",
        Parameters =
        [
            new RuntimeParameterMetadata { Name = "zoneId", Location = "path", Required = true },
            new RuntimeParameterMetadata { Name = "recordId", Location = "path", Required = true },
            new RuntimeParameterMetadata { Name = "include", Location = "query" }
        ],
        ResponseRepresentations =
        [
            new RuntimeResponseRepresentation { StatusCode = 200, ContentType = "application/json", EnvelopePolicy = "CloudflareResult", ParsingMode = "Json" }
        ]
    };
    var record = dispatcher.ExecuteAsync<CfDnsRecord>(metadata, new BoundParameters(new Dictionary<string, object?>
    {
        ["zoneId"] = "zone id",
        ["recordId"] = "record",
        ["include"] = "comments"
    })).GetAwaiter().GetResult();
    Equal("r1", record!.Id);
    Equal("/client/v4/zones/zone%20id/dns_records/record?include=comments", handler.Requests[0].RequestUri!.PathAndQuery);
    Equal("Bearer", handler.Requests[0].Headers.Authorization!.Scheme);
}

static void TestRawTextDispatcher()
{
    var handler = new SequenceHandler(new HttpResponseMessage(HttpStatusCode.OK)
    {
        Content = new StringContent("$ORIGIN example.com.", Encoding.UTF8, "text/plain")
    });
    using var http = new HttpClient(handler);
    using var transport = new HttpClientTransport(http);
    var dispatcher = new CloudflareRuntimeDispatcher(new Uri("https://mock.test/"), transport);
    var metadata = new RuntimeOperationMetadata
    {
        OperationId = "dns-export",
        Method = HttpMethod.Get,
        PathTemplate = "zones/{zoneId}/dns_records/export",
        Parameters = [new RuntimeParameterMetadata { Name = "zoneId", Location = "path", Required = true }],
        ResponseRepresentations = [new RuntimeResponseRepresentation { StatusCode = 200, ContentType = "text/plain", ParsingMode = "RawText" }]
    };
    var text = dispatcher.ExecuteAsync<string>(metadata, new BoundParameters(new Dictionary<string, object?> { ["zoneId"] = "zone" })).GetAwaiter().GetResult();
    Equal("$ORIGIN example.com.", text);
}

static void TestBinaryDispatcher()
{
    var handler = new SequenceHandler(new HttpResponseMessage(HttpStatusCode.OK)
    {
        Content = new ByteArrayContent([0, 1, 2, 255])
    });
    handler.Responses[0].Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/octet-stream");
    using var http = new HttpClient(handler);
    using var transport = new HttpClientTransport(http);
    var dispatcher = new CloudflareRuntimeDispatcher(new Uri("https://mock.test/"), transport);
    var metadata = new RuntimeOperationMetadata
    {
        OperationId = "download",
        Method = HttpMethod.Get,
        PathTemplate = "download",
        ResponseRepresentations = [new RuntimeResponseRepresentation { StatusCode = 200, ContentType = "application/octet-stream", ParsingMode = "Binary" }]
    };
    using var stream = dispatcher.ExecuteAsync<Stream>(metadata, new BoundParameters(new Dictionary<string, object?>())).GetAwaiter().GetResult()!;
    var bytes = new byte[4];
    Equal(4, stream.Read(bytes, 0, bytes.Length));
    Equal("0,1,2,255", string.Join(',', bytes));
}

static void TestMultipartDispatcher()
{
    var handler = new SequenceHandler(new HttpResponseMessage(HttpStatusCode.NoContent));
    using var http = new HttpClient(handler);
    using var transport = new HttpClientTransport(http);
    var dispatcher = new CloudflareRuntimeDispatcher(new Uri("https://mock.test/"), transport);
    var metadata = new RuntimeOperationMetadata
    {
        OperationId = "upload",
        Method = HttpMethod.Post,
        PathTemplate = "accounts/{accountId}/upload",
        Parameters = [new RuntimeParameterMetadata { Name = "accountId", Location = "path", Required = true }],
        RequestRepresentations =
        [
            new RuntimeRequestRepresentation
            {
                ContentType = "multipart/form-data",
                Parts =
                [
                    new RuntimeMultipartPart { ParameterName = "name", PartName = "name", ContentType = "text/plain", Format = "string", Required = true },
                    new RuntimeMultipartPart { ParameterName = "file", PartName = "file", ContentType = "application/octet-stream", Format = "binary", Required = true }
                ]
            }
        ],
        ResponseRepresentations = [new RuntimeResponseRepresentation { StatusCode = 204, ParsingMode = "NoContent" }]
    };
    dispatcher.ExecuteAsync<JsonNode?>(metadata, new BoundParameters(new Dictionary<string, object?>
    {
        ["accountId"] = "account",
        ["name"] = "fixture.bin",
        ["file"] = new byte[] { 1, 2, 3 }
    })).GetAwaiter().GetResult();
    True(handler.Requests[0].ContentType!.StartsWith("multipart/form-data; boundary=", StringComparison.OrdinalIgnoreCase));
    var multipartBody = handler.Requests[0].Body!;
    True(multipartBody.Contains("name=name", StringComparison.Ordinal));
    True(multipartBody.Contains("name=file", StringComparison.Ordinal));
    True(multipartBody.Contains("application/octet-stream", StringComparison.Ordinal));
    True(handler.Requests[0].RawBody!.AsSpan().IndexOf(new byte[] { 1, 2, 3 }) >= 0);
}

static void TestPaginationStrategies()
{
    var executor = new CloudflarePaginationExecutor();
    var pages = new List<int>();
    var arrayItems = Collect(executor.ExecuteAsync(
        (parameters, _) =>
        {
            var page = Convert.ToInt32(parameters["page"]);
            pages.Add(page);
            return Task.FromResult(new RuntimePage<int> { Items = page switch { 1 => [1, 2], 2 => [3], _ => [] } });
        },
        new Dictionary<string, object?>(),
        new RuntimePaginationMetadata { Strategy = "V4PagePaginationArray", RequestFields = ["page"] }));
    Equal("1,2,3", string.Join(',', arrayItems));
    Equal("1,2,3", string.Join(',', pages));

    var boundedCalls = 0;
    var boundedItems = Collect(executor.ExecuteAsync(
        (_, _) =>
        {
            boundedCalls++;
            return Task.FromResult(new RuntimePage<int> { Items = [boundedCalls], CurrentPage = boundedCalls, TotalPages = 2 });
        },
        new Dictionary<string, object?>(),
        new RuntimePaginationMetadata { Strategy = "V4PagePagination", RequestFields = ["page"] }));
    Equal("1,2", string.Join(',', boundedItems));
    Equal(2, boundedCalls);

    foreach (var strategy in new[] { "CursorPagination", "CursorPaginationAfter", "CursorLimitPagination" })
    {
        var cursors = new List<string>();
        var cursorItems = Collect(executor.ExecuteAsync(
            (parameters, _) =>
            {
                var field = strategy == "CursorPaginationAfter" ? "after" : "cursor";
                var cursor = parameters.TryGetValue(field, out var value) ? value?.ToString() : null;
                cursors.Add(cursor ?? "initial");
                return Task.FromResult(cursor switch
                {
                    null => new RuntimePage<int> { Items = [1], NextCursor = "c1" },
                    "c1" => new RuntimePage<int> { Items = [2], NextCursor = "c2" },
                    _ => new RuntimePage<int> { Items = [3] }
                });
            },
            new Dictionary<string, object?>(),
            new RuntimePaginationMetadata { Strategy = strategy, RequestFields = [strategy == "CursorPaginationAfter" ? "after" : "cursor"] }));
        Equal("1,2,3", string.Join(',', cursorItems));
        Equal("initial,c1,c2", string.Join(',', cursors));
    }

    var singleCalls = 0;
    var singleItems = Collect(executor.ExecuteAsync<int>(
        (_, _) => { singleCalls++; return Task.FromResult(new RuntimePage<int> { Items = [42] }); },
        new Dictionary<string, object?>(),
        new RuntimePaginationMetadata { Strategy = "SinglePage" }));
    Equal("42", string.Join(',', singleItems));
    Equal(1, singleCalls);

    var repeated = executor.ExecuteAsync(
        (_, _) => Task.FromResult(new RuntimePage<int> { Items = [1], NextCursor = "same" }),
        new Dictionary<string, object?>(),
        new RuntimePaginationMetadata { Strategy = "CursorPagination", RequestFields = ["cursor"] });
    try { _ = Collect(repeated); throw new InvalidOperationException("expected repeated cursor error"); }
    catch (InvalidOperationException ex) { True(ex.Message.Contains("repeated", StringComparison.OrdinalIgnoreCase)); }

    var cancellation = new CancellationTokenSource();
    cancellation.Cancel();
    var canceled = executor.ExecuteAsync(
        (_, _) => Task.FromResult(new RuntimePage<int> { Items = [1] }),
        new Dictionary<string, object?>(),
        new RuntimePaginationMetadata { Strategy = "V4PagePaginationArray", RequestFields = ["page"] },
        cancellation.Token);
    try { _ = Collect(canceled); throw new InvalidOperationException("expected cancellation"); }
    catch (OperationCanceledException) { }

    var laterPageFailure = executor.ExecuteAsync(
        (parameters, _) =>
        {
            if (Convert.ToInt32(parameters["page"]) == 2) throw new InvalidOperationException("later page failed");
            return Task.FromResult(new RuntimePage<int> { Items = [1] });
        },
        new Dictionary<string, object?>(),
        new RuntimePaginationMetadata { Strategy = "V4PagePaginationArray", RequestFields = ["page"] });
    try { _ = Collect(laterPageFailure); throw new InvalidOperationException("expected later-page error"); }
    catch (InvalidOperationException ex) { True(ex.Message.Contains("later page", StringComparison.Ordinal)); }
}

static void TestGeneratedMetadataAdapter()
{
    Equal(6, CfDnsRecordRuntimeMetadata.Operations.Count);
    var generatedGet = CfDnsRecordRuntimeMetadata.Get(
        CfDnsRecordOperationMetadata.Operation_dns_records_Get_dns_records_for_a_zone_dns_record_details);
    var generatedRuntime = GeneratedOperationMetadataAdapter.ToRuntime(generatedGet);
    Equal(HttpMethod.Get, generatedRuntime.Method);
    Equal("/zones/{zone_id}/dns_records/{dns_record_id}", generatedRuntime.PathTemplate);
    Equal("path", generatedRuntime.Parameters[0].Location);
    Equal("query", generatedRuntime.Parameters[2].Location);

    var handler = new SequenceHandler(Json(HttpStatusCode.OK, "{\"success\":true,\"result\":{\"id\":\"generated\"}}"));
    using var http = new HttpClient(handler);
    using var transport = new HttpClientTransport(http);
    var dispatcher = new CloudflareRuntimeDispatcher(
        new Uri("https://mock.test/client/v4/"), transport, new ApiTokenAuthenticationContext("token"));
    var record = dispatcher.ExecuteAsync<CfDnsRecord>(generatedRuntime, new BoundParameters(new Dictionary<string, object?>
    {
        ["zone_id"] = "zone",
        ["dns_record_id"] = "record",
        ["include_shadow_metadata"] = true
    })).GetAwaiter().GetResult();
    Equal("generated", record!.Id);
    Equal("/client/v4/zones/zone/dns_records/record?include_shadow_metadata=True", handler.Requests[0].RequestUri!.PathAndQuery);
    Equal("Bearer", handler.Requests[0].Headers.Authorization!.Scheme);

    var generatedList = CfDnsRecordRuntimeMetadata.Get(
        CfDnsRecordOperationMetadata.Operation_dns_records_List_dns_records_for_a_zone_list_dns_records);
    var pagination = GeneratedOperationMetadataAdapter.ToRuntimePagination(generatedList)!;
    Equal("V4PagePaginationArray", pagination.Strategy);
    Equal("result", pagination.ResultPath);
    Equal("result_info.total_pages", pagination.TotalPagesPath);

    var multipartHandler = new SequenceHandler(new HttpResponseMessage(HttpStatusCode.NoContent));
    using var multipartHttp = new HttpClient(multipartHandler);
    using var multipartTransport = new HttpClientTransport(multipartHttp);
    var generatedMultipart = new GeneratedOperationMetadata
    {
        OperationId = "generated-upload",
        Method = "POST",
        PathTemplate = "/accounts/{account_id}/uploads",
        Parameters =
        [
            new GeneratedParameterMetadata { Name = "account_id", Location = "path", Required = true },
            new GeneratedParameterMetadata { Name = "X-Upload-Mode", Location = "header" },
            new GeneratedParameterMetadata { Name = "kind", Location = "query" }
        ],
        RequestRepresentations =
        [
            new GeneratedRequestRepresentationMetadata
            {
                ContentType = "multipart/form-data",
                Parts =
                [
                    new GeneratedMultipartPartMetadata { ParameterName = "name", PartName = "name", ContentType = "text/plain", Format = "string", Required = true },
                    new GeneratedMultipartPartMetadata { ParameterName = "file", PartName = "file", ContentType = "application/octet-stream", Format = "binary", Required = true }
                ]
            }
        ],
        ResponseRepresentations = [new GeneratedResponseRepresentationMetadata { StatusCode = 204, ParsingMode = "NoContent" }]
    };
    var multipartRuntime = GeneratedOperationMetadataAdapter.ToRuntime(generatedMultipart);
    var multipartDispatcher = new CloudflareRuntimeDispatcher(new Uri("https://mock.test/"), multipartTransport);
    multipartDispatcher.ExecuteAsync<JsonNode?>(multipartRuntime, new BoundParameters(new Dictionary<string, object?>
    {
        ["account_id"] = "account",
        ["X-Upload-Mode"] = "safe",
        ["kind"] = "dns",
        ["name"] = "fixture.bin",
        ["file"] = new byte[] { 1, 2, 3 }
    })).GetAwaiter().GetResult();
    Equal("/accounts/account/uploads?kind=dns", multipartHandler.Requests[0].RequestUri!.PathAndQuery);
    Equal("safe", multipartHandler.Requests[0].Headers.GetValues("X-Upload-Mode").Single());
    True(multipartHandler.Requests[0].ContentType!.StartsWith("multipart/form-data; boundary=", StringComparison.OrdinalIgnoreCase));
    True(multipartHandler.Requests[0].Body!.Contains("name=name", StringComparison.Ordinal));
    True(multipartHandler.Requests[0].Body!.Contains("name=file", StringComparison.Ordinal));
    True(multipartHandler.Requests[0].RawBody!.AsSpan().IndexOf(new byte[] { 1, 2, 3 }) >= 0);
}

static void TestNormalizedPaginationResponseAdapter()
{
    var metadata = new RuntimePaginationMetadata
    {
        Strategy = "CursorPaginationAfter",
        ResponseFields = ["data.items", "data.page_info"]
    };
    var page = CloudflarePaginationResponseAdapter.FromJson<CfDnsRecord>(
        JsonNode.Parse("{\"data\":{\"items\":[{\"id\":\"r1\",\"type\":\"A\"}],\"page_info\":{\"has_more\":true,\"cursor\":\"next-1\",\"page\":2,\"total_pages\":4}}}"),
        metadata);
    Equal(1, page.Items.Count);
    Equal("r1", page.Items[0].Id);
    Equal(2, page.CurrentPage);
    Equal(4, page.TotalPages);
    Equal("next-1", page.NextCursor);
    Equal(true, page.HasMore);

    var nestedCursor = CloudflarePaginationResponseAdapter.FromJson<CfDnsRecord>(
        JsonNode.Parse("{\"result\":[{\"id\":\"r1\"}],\"result_info\":{\"cursors\":{\"after\":\"next-1\"}}}"),
        new RuntimePaginationMetadata { ResponseFields = ["result", "result_info.cursors.after"] });
    Equal("next-1", nestedCursor.NextCursor);

    var afterValues = new List<string>();
    var cursorMetadata = new RuntimePaginationMetadata
    {
        Strategy = "CursorPaginationAfter",
        RequestFields = ["after"],
        ResponseFields = ["result", "result_info.cursors.after"]
    };
    var cursorItems = Collect(new CloudflarePaginationExecutor().ExecuteAsync(
        (parameters, _) =>
        {
            var after = parameters.TryGetValue("after", out var value) ? value?.ToString() : null;
            afterValues.Add(after ?? "initial");
            var body = after is null
                ? "{\"result\":[{\"id\":\"r1\"}],\"result_info\":{\"cursors\":{\"after\":\"next-1\"}}}"
                : "{\"result\":[{\"id\":\"r2\"}],\"result_info\":{\"cursors\":{}}}";
            return Task.FromResult(CloudflarePaginationResponseAdapter.FromJson<CfDnsRecord>(JsonNode.Parse(body), cursorMetadata));
        },
        new Dictionary<string, object?>(),
        cursorMetadata));
    Equal("r1,r2", string.Join(',', cursorItems.Select(x => x.Id)));
    Equal("initial,next-1", string.Join(',', afterValues));

    var empty = CloudflarePaginationResponseAdapter.FromJson<CfDnsRecord>(
        JsonNode.Parse("{\"result\":[],\"result_info\":{\"page\":3}}"),
        new RuntimePaginationMetadata { ResponseFields = ["result", "result_info"] });
    Equal(0, empty.Items.Count);
    Equal(3, empty.CurrentPage);

    var handler = new SequenceHandler(
        Json(HttpStatusCode.OK, "{\"success\":true,\"result\":[{\"id\":\"r1\"}],\"result_info\":{\"page\":1}}"),
        Json(HttpStatusCode.OK, "{\"success\":true,\"result\":[],\"result_info\":{\"page\":2}}"));
    using var http = new HttpClient(handler);
    using var transport = new HttpClientTransport(http);
    var dispatcher = new CloudflareRuntimeDispatcher(new Uri("https://mock.test/"), transport);
    var operation = new RuntimeOperationMetadata
    {
        OperationId = "normalized-list",
        Method = HttpMethod.Get,
        PathTemplate = "records",
        Parameters = [new RuntimeParameterMetadata { Name = "page", Location = "query" }],
        ResponseRepresentations = [new RuntimeResponseRepresentation { StatusCode = 200, ContentType = "application/json", EnvelopePolicy = "CloudflareResult", ParsingMode = "Json" }]
    };
    var pagination = new RuntimePaginationMetadata
    {
        Strategy = "V4PagePaginationArray",
        RequestFields = ["page"],
        ResponseFields = ["result", "result_info"],
        ResultPath = "result",
        PageInfoPath = "result_info",
        CurrentPagePath = "result_info.page"
    };
    var items = Collect(dispatcher.ExecutePagedAsync<CfDnsRecord>(operation, new BoundParameters(new Dictionary<string, object?>()), pagination));
    Equal("r1", items.Single().Id);
    Equal(2, handler.Requests.Count);
    True(handler.Requests[0].RequestUri!.Query.Contains("page=1", StringComparison.Ordinal));
    True(handler.Requests[1].RequestUri!.Query.Contains("page=2", StringComparison.Ordinal));
}

static void TestRetryPolicy()
{
    var policy = new ExponentialBackoffRetryPolicy(new RetryPolicyOptions
    {
        MaxRetries = 2,
        BaseDelay = TimeSpan.Zero,
        MaxDelay = TimeSpan.FromSeconds(10),
        JitterRatio = 0,
        JitterSample = () => 0
    });
    var handler = new SequenceHandler(
        Json(HttpStatusCode.InternalServerError, "{\"success\":false,\"errors\":[{\"code\":1,\"message\":\"retry\"}]}"),
        Json((HttpStatusCode)429, "{\"success\":false,\"errors\":[{\"code\":2,\"message\":\"retry\"}]}"),
        Json(HttpStatusCode.OK, "{\"success\":true,\"result\":{\"id\":\"done\"}}"));
    using var http = new HttpClient(handler);
    using var transport = new HttpClientTransport(http);
    var dispatcher = new CloudflareRuntimeDispatcher(new Uri("https://mock.test/"), transport, retryPolicy: policy);
    var metadata = new RuntimeOperationMetadata
    {
        OperationId = "retryable-get",
        Method = HttpMethod.Get,
        PathTemplate = "records/1",
        ResponseRepresentations = [new RuntimeResponseRepresentation { StatusCode = 200, ContentType = "application/json", EnvelopePolicy = "CloudflareResult", ParsingMode = "Json" }]
    };
    var record = dispatcher.ExecuteAsync<CfDnsRecord>(metadata, new BoundParameters(new Dictionary<string, object?>())).GetAwaiter().GetResult();
    Equal("done", record!.Id);
    Equal(3, handler.Requests.Count);

    var mutationHandler = new SequenceHandler(Json(HttpStatusCode.InternalServerError, "{\"success\":false,\"errors\":[{\"code\":1,\"message\":\"not safe\"}]}"));
    using var mutationHttp = new HttpClient(mutationHandler);
    using var mutationTransport = new HttpClientTransport(mutationHttp);
    var mutationDispatcher = new CloudflareRuntimeDispatcher(new Uri("https://mock.test/"), mutationTransport, retryPolicy: policy);
    var mutationMetadata = new RuntimeOperationMetadata
    {
        OperationId = "mutation",
        Method = HttpMethod.Post,
        PathTemplate = "records",
        ResponseRepresentations = [new RuntimeResponseRepresentation { StatusCode = 200, ContentType = "application/json", ParsingMode = "Json" }]
    };
    try { mutationDispatcher.ExecuteAsync<JsonNode>(mutationMetadata, new BoundParameters(new Dictionary<string, object?>())).GetAwaiter().GetResult(); throw new InvalidOperationException("expected mutation error"); }
    catch (CloudflareApiException) { Equal(1, mutationHandler.Requests.Count); }

    var idempotentHandler = new SequenceHandler(
        Json(HttpStatusCode.InternalServerError, "{\"success\":false,\"errors\":[{\"code\":1,\"message\":\"retry\"}]}"),
        Json(HttpStatusCode.OK, "{\"id\":\"done\"}"));
    using var idempotentHttp = new HttpClient(idempotentHandler);
    using var idempotentTransport = new HttpClientTransport(idempotentHttp);
    var idempotentDispatcher = new CloudflareRuntimeDispatcher(new Uri("https://mock.test/"), idempotentTransport, retryPolicy: policy);
    var idempotentMetadata = new RuntimeOperationMetadata
    {
        OperationId = "idempotent-mutation",
        Method = HttpMethod.Post,
        PathTemplate = "records",
        Idempotency = new RuntimeIdempotencyMetadata { Supported = true, KeyParameterName = "idempotencyKey", RetrySafeWhenKeyPresent = true },
        ResponseRepresentations = [new RuntimeResponseRepresentation { StatusCode = 200, ContentType = "application/json", ParsingMode = "Json" }]
    };
    var idempotentResult = idempotentDispatcher.ExecuteAsync<JsonNode>(idempotentMetadata, new BoundParameters(new Dictionary<string, object?> { ["idempotencyKey"] = "key-1" })).GetAwaiter().GetResult();
    Equal("done", idempotentResult!["id"]!.GetValue<string>());
    Equal(2, idempotentHandler.Requests.Count);
    Equal("key-1", idempotentHandler.Requests[0].Headers.GetValues("Idempotency-Key").Single());

    var responseMessage = new HttpResponseMessage(HttpStatusCode.TooManyRequests);
    responseMessage.Headers.TryAddWithoutValidation("retry-after-ms", "17");
    var retryAfterMsResponse = new CloudflareResponse(responseMessage);
    Equal(17d, policy.GetDelay(retryAfterMsResponse, 0).TotalMilliseconds);
    retryAfterMsResponse.DisposeAsync().AsTask().GetAwaiter().GetResult();

    foreach (var status in new[] { 408, 409, 429, 500, 503 })
    {
        var retryResponse = new CloudflareResponse(new HttpResponseMessage((HttpStatusCode)status));
        True(policy.ShouldRetry(new CloudflareRequest(HttpMethod.Get, new Uri("https://mock.test/")), retryResponse, null, 0));
        retryResponse.DisposeAsync().AsTask().GetAwaiter().GetResult();
    }
    var overrideFalseMessage = new HttpResponseMessage(HttpStatusCode.ServiceUnavailable);
    overrideFalseMessage.Headers.TryAddWithoutValidation("x-should-retry", "false");
    var overrideFalseResponse = new CloudflareResponse(overrideFalseMessage);
    True(!policy.ShouldRetry(new CloudflareRequest(HttpMethod.Get, new Uri("https://mock.test/")), overrideFalseResponse, null, 0));
    overrideFalseResponse.DisposeAsync().AsTask().GetAwaiter().GetResult();
    var overrideTrueMessage = new HttpResponseMessage(HttpStatusCode.BadRequest);
    overrideTrueMessage.Headers.TryAddWithoutValidation("x-should-retry", "true");
    var overrideTrueResponse = new CloudflareResponse(overrideTrueMessage);
    True(policy.ShouldRetry(new CloudflareRequest(HttpMethod.Get, new Uri("https://mock.test/")), overrideTrueResponse, null, 0));
    overrideTrueResponse.DisposeAsync().AsTask().GetAwaiter().GetResult();
    var retryAfterSecondsMessage = new HttpResponseMessage(HttpStatusCode.TooManyRequests);
    retryAfterSecondsMessage.Headers.TryAddWithoutValidation("Retry-After", "2");
    var retryAfterSecondsResponse = new CloudflareResponse(retryAfterSecondsMessage);
    Equal(2000d, policy.GetDelay(retryAfterSecondsResponse, 0).TotalMilliseconds);
    retryAfterSecondsResponse.DisposeAsync().AsTask().GetAwaiter().GetResult();
}

static void TestNonReplayableRequest()
{
    var handler = new SequenceHandler(Json(HttpStatusCode.InternalServerError, "{\"success\":false,\"errors\":[{\"code\":1,\"message\":\"no retry\"}]}"));
    using var http = new HttpClient(handler);
    using var transport = new HttpClientTransport(http);
    var policy = new ExponentialBackoffRetryPolicy(new RetryPolicyOptions { BaseDelay = TimeSpan.Zero, MaxDelay = TimeSpan.Zero, JitterRatio = 0 });
    var dispatcher = new CloudflareRuntimeDispatcher(new Uri("https://mock.test/"), transport, retryPolicy: policy);
    var metadata = new RuntimeOperationMetadata
    {
        OperationId = "upload",
        Method = HttpMethod.Post,
        PathTemplate = "upload",
        RequestRepresentations = [new RuntimeRequestRepresentation { ContentType = "multipart/form-data", Parts = [new RuntimeMultipartPart { ParameterName = "file", PartName = "file", ContentType = "application/octet-stream", Format = "binary", Required = true }] }],
        ResponseRepresentations = [new RuntimeResponseRepresentation { StatusCode = 200, ContentType = "application/json", ParsingMode = "Json" }]
    };
    try
    {
        dispatcher.ExecuteAsync<JsonNode>(metadata, new BoundParameters(new Dictionary<string, object?> { ["file"] = new NonSeekableStream([1, 2, 3]) })).GetAwaiter().GetResult();
        throw new InvalidOperationException("expected HTTP error");
    }
    catch (CloudflareApiException ex)
    {
        Equal(1, handler.Requests.Count);
        Equal(0, ex.RetryCount);
    }
}

static void TestMultipartStreamOwnership()
{
    var handler = new SequenceHandler(Json(HttpStatusCode.InternalServerError, "{\"success\":false,\"errors\":[{\"code\":1,\"message\":\"no retry\"}]}"));
    using var http = new HttpClient(handler);
    using var transport = new HttpClientTransport(http);
    var policy = new ExponentialBackoffRetryPolicy(new RetryPolicyOptions { BaseDelay = TimeSpan.Zero, MaxDelay = TimeSpan.Zero, JitterRatio = 0 });
    var dispatcher = new CloudflareRuntimeDispatcher(new Uri("https://mock.test/"), transport, retryPolicy: policy);
    var metadata = new RuntimeOperationMetadata
    {
        OperationId = "idempotent-upload",
        Method = HttpMethod.Post,
        PathTemplate = "upload",
        Idempotency = new RuntimeIdempotencyMetadata { Supported = true, KeyParameterName = "idempotencyKey", RetrySafeWhenKeyPresent = true },
        RequestRepresentations = [new RuntimeRequestRepresentation { ContentType = "multipart/form-data", Parts = [new RuntimeMultipartPart { ParameterName = "file", PartName = "file", ContentType = "application/octet-stream", Format = "binary", Required = true }] }],
        ResponseRepresentations = [new RuntimeResponseRepresentation { StatusCode = 200, ContentType = "application/json", ParsingMode = "Json" }]
    };
    var stream = new TrackingStream([1, 2, 3]);
    try
    {
        dispatcher.ExecuteAsync<JsonNode>(metadata, new BoundParameters(new Dictionary<string, object?> { ["idempotencyKey"] = "key-1", ["file"] = stream })).GetAwaiter().GetResult();
        throw new InvalidOperationException("expected HTTP error");
    }
    catch (CloudflareApiException ex)
    {
        Equal(1, handler.Requests.Count);
        Equal(0, ex.RetryCount);
        True(!stream.WasDisposed);
    }
    stream.Dispose();
}

static List<T> Collect<T>(IAsyncEnumerable<T> source)
{
    var values = new List<T>();
    var enumerator = source.GetAsyncEnumerator();
    try { while (enumerator.MoveNextAsync().GetAwaiter().GetResult()) values.Add(enumerator.Current); }
    finally { enumerator.DisposeAsync().GetAwaiter().GetResult(); }
    return values;
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
    public List<HttpResponseMessage> Responses { get; } = [];
    public List<CapturedRequest> Requests { get; } = [];
    public SequenceHandler(params object[] responses)
    {
        _responses = new Queue<object>(responses);
        Responses.AddRange(responses.OfType<HttpResponseMessage>());
    }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var rawBody = request.Content is null ? null : await request.Content.ReadAsByteArrayAsync(cancellationToken);
        var body = rawBody is null ? null : Encoding.UTF8.GetString(rawBody);
        Requests.Add(new CapturedRequest(request.Method, request.RequestUri, request.Headers, body, request.Content?.Headers.ContentType?.ToString(), rawBody));
        var next = _responses.Dequeue();
        if (next is Exception exception) throw exception;
        return (HttpResponseMessage)next;
    }
}

sealed record CapturedRequest(HttpMethod Method, Uri? RequestUri, HttpRequestHeaders Headers, string? Body, string? ContentType, byte[]? RawBody);

sealed class NonSeekableStream : MemoryStream
{
    public NonSeekableStream(byte[] buffer) : base(buffer, writable: false) { }
    public override bool CanSeek => false;
}

sealed class TrackingStream : MemoryStream
{
    public TrackingStream(byte[] buffer) : base(buffer, writable: false) { }
    public bool WasDisposed { get; private set; }
    protected override void Dispose(bool disposing)
    {
        WasDisposed = true;
        base.Dispose(disposing);
    }
}
