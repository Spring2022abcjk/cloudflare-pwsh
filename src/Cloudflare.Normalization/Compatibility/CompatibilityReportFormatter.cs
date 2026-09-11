using System.Text;

namespace Cloudflare.Normalization.Compatibility;

public static class CompatibilityReportFormatter
{
    public static string ToMarkdown(CompatibilityReport report)
    {
        var builder = new StringBuilder();
        builder.AppendLine($"# {report.Stage} Compatibility Report");
        builder.AppendLine();
        builder.AppendLine($"- Old source revision: `{report.OldSourceRevision}`");
        builder.AppendLine($"- New source revision: `{report.NewSourceRevision}`");
        builder.AppendLine($"- Changes: `{report.Changes.Count}`");
        builder.AppendLine($"- Fully compatible: `{report.FullyCompatible}`");
        builder.AppendLine();
        builder.AppendLine("## Impact summary");
        builder.AppendLine();
        builder.AppendLine("| Dimension | Impact | Count |");
        builder.AppendLine("| --- | --- | ---: |");
        foreach (var item in report.SeveritySummary.Where(x => x.Key != "Changes").OrderBy(x => x.Key, StringComparer.Ordinal))
        {
            var split = item.Key.Split(':', 2);
            builder.AppendLine($"| {split[0]} | {split[1]} | {item.Value} |");
        }
        builder.AppendLine();
        builder.AppendLine("## Changes");
        builder.AppendLine();
        if (report.Changes.Count == 0)
        {
            builder.AppendLine("No compatibility changes detected.");
            return builder.ToString();
        }

        builder.AppendLine("| Kind | Resource | Operation | Schema | Path | API | SDK | PowerShell | Old | New | Evidence |");
        builder.AppendLine("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |");
        foreach (var change in report.Changes)
        {
            builder.AppendLine("| " + string.Join(" | ",
                Escape(change.Kind.ToString()), Escape(change.ResourcePath), Escape(change.OperationId ?? string.Empty),
                Escape(change.SchemaName ?? string.Empty), Escape(change.Path), Escape(change.ApiImpact.ToString()),
                Escape(change.SdkImpact.ToString()), Escape(change.PowerShellImpact.ToString()), Escape(change.OldValue),
                Escape(change.NewValue), Escape(change.Evidence)) + " |");
        }
        return builder.ToString();
    }

    private static string Escape(string value) => value.Replace("|", "\\|", StringComparison.Ordinal).Replace("\r", " ", StringComparison.Ordinal).Replace("\n", " ", StringComparison.Ordinal);
}
