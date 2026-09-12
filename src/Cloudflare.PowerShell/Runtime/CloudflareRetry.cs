using System.Globalization;
using System.Net;

namespace Cloudflare.PowerShell;

public sealed class RuntimeIdempotencyMetadata
{
    public bool Supported { get; init; }
    public string HeaderName { get; init; } = "Idempotency-Key";
    public string? KeyParameterName { get; init; }
    public bool RetrySafeWhenKeyPresent { get; init; }
    public bool AutoGenerate { get; init; }
}

public sealed class RetryPolicyOptions
{
    public int MaxRetries { get; init; } = 2;
    public TimeSpan BaseDelay { get; init; } = TimeSpan.FromMilliseconds(250);
    public TimeSpan MaxDelay { get; init; } = TimeSpan.FromSeconds(30);
    public double JitterRatio { get; init; } = 0.1;
    public Func<double> JitterSample { get; init; } = static () => Random.Shared.NextDouble();
}

public sealed class ExponentialBackoffRetryPolicy : ICloudflareRetryPolicy
{
    private readonly RetryPolicyOptions _options;

    public ExponentialBackoffRetryPolicy(RetryPolicyOptions? options = null)
    {
        _options = options ?? new RetryPolicyOptions();
        if (_options.MaxRetries < 0) throw new ArgumentOutOfRangeException(nameof(options), "MaxRetries cannot be negative.");
        if (_options.BaseDelay < TimeSpan.Zero) throw new ArgumentOutOfRangeException(nameof(options), "BaseDelay cannot be negative.");
        if (_options.MaxDelay < _options.BaseDelay) throw new ArgumentOutOfRangeException(nameof(options), "MaxDelay cannot be less than BaseDelay.");
        if (_options.JitterRatio < 0 || _options.JitterRatio > 1) throw new ArgumentOutOfRangeException(nameof(options), "JitterRatio must be between zero and one.");
    }

    public bool ShouldRetry(CloudflareRequest request, CloudflareResponse? response, Exception? exception, int retryCount)
    {
        if (!request.IsReplayable || !request.IsRetrySafe || retryCount >= _options.MaxRetries) return false;
        var overrideValue = GetHeader(response, "x-should-retry");
        if (bool.TryParse(overrideValue, out var overrideDecision)) return overrideDecision;
        if (exception is HttpRequestException or TimeoutException or TaskCanceledException) return true;
        if (response is null) return false;
        var status = (int)response.StatusCode;
        return response.StatusCode is HttpStatusCode.RequestTimeout
            or HttpStatusCode.Conflict
            or (HttpStatusCode)429
            || status >= 500;
    }

    public TimeSpan GetDelay(CloudflareResponse? response, int retryCount)
    {
        var retryAfterMilliseconds = GetHeader(response, "retry-after-ms");
        if (double.TryParse(retryAfterMilliseconds, NumberStyles.Float, CultureInfo.InvariantCulture, out var milliseconds) && milliseconds >= 0)
            return Clamp(TimeSpan.FromMilliseconds(milliseconds));

        var retryAfter = GetHeader(response, "Retry-After");
        if (int.TryParse(retryAfter, NumberStyles.Integer, CultureInfo.InvariantCulture, out var seconds) && seconds >= 0)
            return Clamp(TimeSpan.FromSeconds(seconds));
        if (DateTimeOffset.TryParse(retryAfter, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var retryAt))
            return Clamp(retryAt - DateTimeOffset.UtcNow);

        var exponent = Math.Min(retryCount, 30);
        var multiplier = Math.Pow(2, exponent);
        var baseMilliseconds = Math.Min(_options.MaxDelay.TotalMilliseconds, _options.BaseDelay.TotalMilliseconds * multiplier);
        var jitter = baseMilliseconds * _options.JitterRatio * Math.Clamp(_options.JitterSample(), 0, 1);
        return Clamp(TimeSpan.FromMilliseconds(baseMilliseconds + jitter));
    }

    private TimeSpan Clamp(TimeSpan value)
        => value < TimeSpan.Zero ? TimeSpan.Zero : value > _options.MaxDelay ? _options.MaxDelay : value;

    private static string? GetHeader(CloudflareResponse? response, string name)
        => response?.Headers
            .FirstOrDefault(x => x.Key.Equals(name, StringComparison.OrdinalIgnoreCase))
            .Value?.FirstOrDefault();
}
