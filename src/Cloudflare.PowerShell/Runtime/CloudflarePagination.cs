namespace Cloudflare.PowerShell;

public sealed class RuntimePaginationMetadata
{
    public string Strategy { get; init; } = "SinglePage";
    public IReadOnlyList<string> RequestFields { get; init; } = [];
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
            if (page.HasMore == false || string.IsNullOrEmpty(page.NextCursor)) yield break;
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
