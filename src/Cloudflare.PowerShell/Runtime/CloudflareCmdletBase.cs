using System.Management.Automation;
using System.Text.Json.Nodes;

namespace Cloudflare.PowerShell;

/// <summary>
/// Shared PowerShell host adapter for generated commands. It owns only common
/// host concerns; operation-specific parameters and bindings remain generated.
/// </summary>
public abstract class CloudflareCmdletBase : PSCmdlet
{
    private readonly CancellationTokenSource _stopping = new();

    [Parameter(DontShow = true)]
    public string BaseUrl { get; set; } = "https://api.cloudflare.com/client/v4/";

    [Parameter(DontShow = true)]
    public string? Token { get; set; }

    [Parameter(DontShow = true)]
    public HttpMessageHandler? Handler { get; set; }

    protected CancellationToken CancellationToken => _stopping.Token;

    protected CloudflareClient CreateClient()
        => new(new CloudflareClientOptions
        {
            BaseUri = new Uri(BaseUrl, UriKind.Absolute),
            BearerToken = Token ?? Environment.GetEnvironmentVariable("CF_API_TOKEN"),
            Handler = Handler
        });

    protected BoundParameters BindParameters(params (string PublicName, string ApiName)[] mappings)
    {
        var values = new Dictionary<string, object?>(StringComparer.Ordinal);
        foreach (var (publicName, apiName) in mappings)
        {
            if (MyInvocation.BoundParameters.TryGetValue(publicName, out var value))
                values[apiName] = value;
        }
        return new BoundParameters(values);
    }

    protected BoundParameters BindParametersWithBody(object? body, params (string PublicName, string ApiName)[] mappings)
    {
        var values = BindParameters(mappings).Values.ToDictionary(x => x.Key, x => x.Value, StringComparer.Ordinal);
        values["body"] = body;
        return new BoundParameters(values);
    }

    protected T? InvokeSingle<T>(GeneratedOperationMetadata metadata, BoundParameters parameters, object? errorTarget = null)
    {
        try
        {
            using var client = CreateClient();
            var operation = GeneratedOperationMetadataAdapter.ToRuntime(metadata);
            return client.Dispatcher.ExecuteAsync<T>(operation, parameters, CancellationToken).GetAwaiter().GetResult();
        }
        catch (CloudflareApiException exception)
        {
            ThrowCloudflareError(exception, errorTarget);
            return default;
        }
    }

    protected void WritePaged<T>(GeneratedOperationMetadata metadata, BoundParameters parameters, object? errorTarget = null)
    {
        try
        {
            using var client = CreateClient();
            var operation = GeneratedOperationMetadataAdapter.ToRuntime(metadata);
            var pagination = GeneratedOperationMetadataAdapter.ToRuntimePagination(metadata)
                ?? throw new InvalidOperationException($"Generated operation '{metadata.OperationId}' is missing pagination metadata.");
            var items = client.Dispatcher.ExecutePagedAsync<T>(operation, parameters, pagination, CancellationToken);
            var enumerator = items.GetAsyncEnumerator(CancellationToken);
            try
            {
                while (enumerator.MoveNextAsync().AsTask().GetAwaiter().GetResult())
                    WriteObject(enumerator.Current);
            }
            finally
            {
                enumerator.DisposeAsync().AsTask().GetAwaiter().GetResult();
            }
        }
        catch (CloudflareApiException exception)
        {
            ThrowCloudflareError(exception, errorTarget);
        }
    }

    protected void ThrowCloudflareError(CloudflareApiException exception, object? targetObject)
    {
        var category = (int)exception.StatusCode switch
        {
            400 => ErrorCategory.InvalidArgument,
            401 or 403 => ErrorCategory.SecurityError,
            404 => ErrorCategory.ObjectNotFound,
            408 or 429 => ErrorCategory.ResourceUnavailable,
            _ => ErrorCategory.InvalidOperation
        };
        ThrowTerminatingError(new ErrorRecord(
            exception,
            exception.FullyQualifiedErrorId,
            category,
            targetObject));
    }

    protected override void StopProcessing()
    {
        _stopping.Cancel();
        base.StopProcessing();
    }

}
