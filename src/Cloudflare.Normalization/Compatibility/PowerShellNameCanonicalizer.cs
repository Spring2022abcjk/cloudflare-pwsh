namespace Cloudflare.Normalization.Compatibility;

public static class PowerShellNameCanonicalizer
{
    public static string ToPowerShellName(string value)
    {
        var parts = new List<string>();
        var current = new System.Text.StringBuilder();
        foreach (var character in value)
        {
            if (char.IsLetterOrDigit(character))
            {
                current.Append(character);
                continue;
            }

            AddPart(parts, current);
        }
        AddPart(parts, current);
        var name = string.Concat(parts);
        if (name.Length == 0) return "Value";
        return char.IsDigit(name[0]) ? $"N_{name}" : name;
    }

    public static string ToIdentityKey(string value)
        => string.Concat(value.Where(char.IsLetterOrDigit)).ToUpperInvariant();

    public static bool AreUnique(IEnumerable<string> values)
    {
        var materialized = values.ToArray();
        return materialized.Select(ToIdentityKey).Distinct(StringComparer.Ordinal).Count() == materialized.Length;
    }

    private static void AddPart(List<string> parts, System.Text.StringBuilder current)
    {
        if (current.Length == 0) return;
        var value = current.ToString();
        if (value.All(char.IsUpper)) value = value.ToLowerInvariant();
        parts.Add(char.ToUpperInvariant(value[0]) + value[1..]);
        current.Clear();
    }
}
