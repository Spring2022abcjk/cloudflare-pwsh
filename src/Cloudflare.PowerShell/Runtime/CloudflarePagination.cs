using System.Text.Json;
using System.Text.Json.Nodes;

namespace Cloudflare.PowerShell;

public sealed class RuntimePaginationMetadata
{
    public string Strategy { get; init; } = "SinglePage";
    public IReadOnlyList<string> RequestFields { get; init; } = [];
    public IReadOnlyList<string> ResponseFields { get; init; } = [];
    public string? ResultPath { get; init; }
    public string? PageInfoPath { get; init; }
    public string? CurrentPagePath { get; init; }
    public string? TotalPagesPath { get; init; }
    public string? NextCursorPath { get; init; }
    public string? HasMorePath { get; init; }
    public string NextPageRule { get; init; } = string.Empty;
    public string StopRule { get; init; } = string.Empty;
}

public sealed class RuntimePage<T>
{
    public IReadOnlyList<T> Items { get; init; } = [];
    public int? CurrentPage { get; init; }
    public int? TotalPages { get; init; }
    public string? NextCursor { get; init; }
    public bool? HasMore { get; init; }
}

public delegate Task<RuntimePage<T>> RuntimePageFetcher<T>(IReadOnlyDictionary<string, object?> parameters, CancellationToken cancellationToken);

/// <summary>
/// Bridges compiler-generated async iterators to a Task-backed ValueTask
/// boundary. This keeps exception and disposal behavior reliable for hosts such
/// as PowerShell that invoke ValueTask members through reflection/dynamic calls.
/// </summary>
public sealed class CloudflareTaskBackedAsyncEnumerable<T> : IAsyncEnumerable<T>
{
    private readonly IAsyncEnumerable<T> _inner;

    public CloudflareTaskBackedAsyncEnumerable(IAsyncEnumerable<T> inner) => _inner = inner;

    public IAsyncEnumerator<T> GetAsyncEnumerator(CancellationToken cancellationToken = default)
        => new Enumerator(_inner.GetAsyncEnumerator(cancellationToken));

    private sealed class Enumerator : IAsyncEnumerator<T>
    {
        private readonly IAsyncEnumerator<T> _inner;

        public Enumerator(IAsyncEnumerator<T> inner) => _inner = inner;
        public T Current => _inner.Current;
        public ValueTask<bool> MoveNextAsync() => new(_inner.MoveNextAsync().AsTask());
        public ValueTask DisposeAsync() => new(_inner.DisposeAsync().AsTask());
    }
}

/// <summary>
/// Adapts a normalized response representation into the runtime page contract.
/// The dispatcher remains unaware of pagination fields; normalized metadata tells
/// this adapter where the result and page-info values live.
/// </summary>
public static class CloudflarePaginationResponseAdapter
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true
    };

    public static RuntimePage<T> FromJson<T>(JsonNode? response, RuntimePaginationMetadata metadata)
    {
        if (response is null) return new RuntimePage<T>();

        var resultPath = metadata.ResultPath ?? FindResultPath(metadata.ResponseFields) ?? "result";
        var resultNode = Select(response, resultPath);
        var items = ReadItems<T>(resultNode);

        var pageInfoPath = metadata.PageInfoPath ?? FindPageInfoPath(metadata.ResponseFields) ?? "result_info";
        return new RuntimePage<T>
        {
            Items = items,
            CurrentPage = ReadInt(response, metadata.CurrentPagePath ?? Join(pageInfoPath, "page")),
            TotalPages = ReadInt(response, metadata.TotalPagesPath ?? Join(pageInfoPath, "total_pages")),
            NextCursor = metadata.NextCursorPath is { } nextCursorPath
                ? ReadString(response, nextCursorPath)
                : FindNextCursorPaths(metadata.ResponseFields, pageInfoPath)
                    .Select(path => ReadString(response, path))
                    .FirstOrDefault(value => !string.IsNullOrEmpty(value)),
            HasMore = ReadBool(response, metadata.HasMorePath ?? Join(pageInfoPath, "has_more"))
        };
    }

    private static IReadOnlyList<T> ReadItems<T>(JsonNode? node)
    {
        if (node is null) return [];
        if (node is JsonObject obj)
            node = FindProperty(obj, "items") ?? FindProperty(obj, "data") ?? node;
        if (node is not JsonArray) return [];
        return JsonSerializer.Deserialize<List<T>>(node, JsonOptions) ?? [];
    }

    private static JsonNode? Select(JsonNode node, string field)
    {
        var current = node;
        foreach (var segment in field.Split('.', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            if (current is not JsonObject obj) return null;
            current = FindProperty(obj, segment);
            if (current is null) return null;
        }
        return current;
    }

    private static JsonNode? FindProperty(JsonObject? obj, string name)
        => obj is null ? null : obj.FirstOrDefault(x => x.Key.Equals(name, StringComparison.OrdinalIgnoreCase)).Value;

    private static int? ReadInt(JsonNode node, string path)
        => Select(node, path)?.GetValue<int>();

    private static bool? ReadBool(JsonNode node, string path)
        => Select(node, path)?.GetValue<bool>();

    private static string? ReadString(JsonNode node, string path)
        => Select(node, path)?.GetValue<string>();

    private static string? FindResultPath(IEnumerable<string> fields)
        => fields.FirstOrDefault(field =>
            Leaf(field).Equals("result", StringComparison.OrdinalIgnoreCase)
            || Leaf(field).Equals("items", StringComparison.OrdinalIgnoreCase));

    private static string? FindPageInfoPath(IEnumerable<string> fields)
    {
        foreach (var field in fields)
        {
            var segments = Segments(field);
            var index = Array.FindIndex(segments, x =>
                x.Equals("result_info", StringComparison.OrdinalIgnoreCase)
                || x.Equals("page_info", StringComparison.OrdinalIgnoreCase));
            if (index >= 0) return string.Join('.', segments.Take(index + 1));
        }
        return null;
    }

    private static IEnumerable<string> FindNextCursorPaths(IEnumerable<string> fields, string pageInfoPath)
    {
        var explicitPaths = fields.Where(field =>
            Leaf(field).Equals("next_cursor", StringComparison.OrdinalIgnoreCase)
            || Leaf(field).Equals("cursor", StringComparison.OrdinalIgnoreCase)
            || Leaf(field).Equals("after", StringComparison.OrdinalIgnoreCase));
        return explicitPaths.Concat([
            Join(pageInfoPath, "next_cursor"),
            Join(pageInfoPath, "cursor"),
            Join(pageInfoPath, "after")
        ]).Distinct(StringComparer.OrdinalIgnoreCase);
    }

    private static string Leaf(string path)
        => Segments(path).LastOrDefault() ?? path;

    private static string[] Segments(string path)
        => path.Split('.', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    private static string Join(string? prefix, string suffix)
        => string.IsNullOrWhiteSpace(prefix) ? suffix : prefix + "." + suffix;
}

public interface ICloudflarePaginationStrategy
{
    bool CanHandle(string strategy);
    IAsyncEnumerable<T> ExecuteAsync<T>(RuntimePageFetcher<T> fetchPage, IReadOnlyDictionary<string, object?> parameters, RuntimePaginationMetadata metadata, CancellationToken cancellationToken = default);
}

public sealed class SinglePagePaginationStrategy : ICloudflarePaginationStrategy
{
    public bool CanHandle(string strategy) => strategy.Equals("SinglePage", StringComparison.OrdinalIgnoreCase);

    public async IAsyncEnumerable<T> ExecuteAsync<T>(RuntimePageFetcher<T> fetchPage, IReadOnlyDictionary<string, object?> parameters, RuntimePaginationMetadata metadata, [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var page = await fetchPage(parameters, cancellationToken).ConfigureAwait(false);
        foreach (var item in page.Items) yield return item;
    }
}

public class V4PagePaginationArrayStrategy : ICloudflarePaginationStrategy
{
    public virtual bool CanHandle(string strategy) => strategy.Equals("V4PagePaginationArray", StringComparison.OrdinalIgnoreCase);

    public virtual async IAsyncEnumerable<T> ExecuteAsync<T>(RuntimePageFetcher<T> fetchPage, IReadOnlyDictionary<string, object?> parameters, RuntimePaginationMetadata metadata, [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var pageField = FindField(metadata, "page");
        var pageNumber = 1;
        while (true)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var pageParameters = With(parameters, pageField, pageNumber);
            var page = await fetchPage(pageParameters, cancellationToken).ConfigureAwait(false);
            if (page.Items.Count == 0) yield break;
            foreach (var item in page.Items) yield return item;
            pageNumber++;
        }
    }

    protected static string FindField(RuntimePaginationMetadata metadata, string fallback)
        => metadata.RequestFields.FirstOrDefault(x => x.Equals(fallback, StringComparison.OrdinalIgnoreCase))
           ?? metadata.RequestFields.FirstOrDefault()
           ?? fallback;

    protected static IReadOnlyDictionary<string, object?> With(IReadOnlyDictionary<string, object?> parameters, string key, object value)
    {
        var copy = new Dictionary<string, object?>(parameters, StringComparer.Ordinal);
        copy[key] = value;
        return copy;
    }
}

public sealed class V4PagePaginationStrategy : V4PagePaginationArrayStrategy
{
    public override bool CanHandle(string strategy) => strategy.Equals("V4PagePagination", StringComparison.OrdinalIgnoreCase);

    public override async IAsyncEnumerable<T> ExecuteAsync<T>(RuntimePageFetcher<T> fetchPage, IReadOnlyDictionary<string, object?> parameters, RuntimePaginationMetadata metadata, [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var pageField = FindField(metadata, "page");
        var pageNumber = 1;
        while (true)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var page = await fetchPage(With(parameters, pageField, pageNumber), cancellationToken).ConfigureAwait(false);
            foreach (var item in page.Items) yield return item;
            if (page.HasMore == false || (page.CurrentPage.HasValue && page.TotalPages.HasValue && page.CurrentPage >= page.TotalPages) || page.Items.Count == 0) yield break;
            pageNumber++;
        }
    }
}

public abstract class CursorPaginationStrategyBase : ICloudflarePaginationStrategy
{
    protected abstract string DefaultRequestField { get; }

    public abstract bool CanHandle(string strategy);

    public async IAsyncEnumerable<T> ExecuteAsync<T>(RuntimePageFetcher<T> fetchPage, IReadOnlyDictionary<string, object?> parameters, RuntimePaginationMetadata metadata, [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var cursorField = metadata.RequestFields.FirstOrDefault(x => x.Equals(DefaultRequestField, StringComparison.OrdinalIgnoreCase))
            ?? metadata.RequestFields.FirstOrDefault()
            ?? DefaultRequestField;
        var pageParameters = new Dictionary<string, object?>(parameters, StringComparer.Ordinal);
        string? cursor = null;
        var seen = new HashSet<string>(StringComparer.Ordinal);
        while (true)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (cursor is not null) pageParameters[cursorField] = cursor;
            var page = await fetchPage(pageParameters, cancellationToken).ConfigureAwait(false);
            foreach (var item in page.Items) yield return item;
            if (page.HasMore == false) yield break;
            if (string.IsNullOrEmpty(page.NextCursor))
            {
                if (page.HasMore == true)
                    throw new InvalidOperationException($"Pagination declared more pages for '{cursorField}' but returned no next cursor.");
                yield break;
            }
            if (!seen.Add(page.NextCursor)) throw new InvalidOperationException($"Pagination cursor repeated for '{cursorField}'.");
            cursor = page.NextCursor;
        }
    }

}

public sealed class CursorPaginationStrategy : CursorPaginationStrategyBase
{
    protected override string DefaultRequestField => "cursor";
    public override bool CanHandle(string strategy) => strategy.Equals("CursorPagination", StringComparison.OrdinalIgnoreCase);
}

public sealed class CursorPaginationAfterStrategy : CursorPaginationStrategyBase
{
    protected override string DefaultRequestField => "after";
    public override bool CanHandle(string strategy) => strategy.Equals("CursorPaginationAfter", StringComparison.OrdinalIgnoreCase);
}

public sealed class CursorLimitPaginationStrategy : CursorPaginationStrategyBase
{
    protected override string DefaultRequestField => "cursor";
    public override bool CanHandle(string strategy) => strategy.Equals("CursorLimitPagination", StringComparison.OrdinalIgnoreCase);
}

public sealed class CloudflarePaginationExecutor
{
    private readonly IReadOnlyList<ICloudflarePaginationStrategy> _strategies;

    public CloudflarePaginationExecutor(IEnumerable<ICloudflarePaginationStrategy>? strategies = null)
    {
        _strategies = strategies?.ToList() ??
        [
            new SinglePagePaginationStrategy(),
            new V4PagePaginationArrayStrategy(),
            new V4PagePaginationStrategy(),
            new CursorPaginationStrategy(),
            new CursorPaginationAfterStrategy(),
            new CursorLimitPaginationStrategy()
        ];
    }

    public IAsyncEnumerable<T> ExecuteAsync<T>(RuntimePageFetcher<T> fetchPage, IReadOnlyDictionary<string, object?> parameters, RuntimePaginationMetadata metadata, CancellationToken cancellationToken = default)
        => _strategies.FirstOrDefault(x => x.CanHandle(metadata.Strategy))?.ExecuteAsync(fetchPage, parameters, metadata, cancellationToken)
           ?? throw new NotSupportedException($"No pagination strategy is registered for '{metadata.Strategy}'.");
}
