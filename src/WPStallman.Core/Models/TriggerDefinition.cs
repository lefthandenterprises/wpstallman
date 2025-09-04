using System.Text.Json.Serialization;
using WPStallman.Core.Utilities;

namespace WPStallman.Core.Models;

public class TriggerDefinition
{
    public string Name { get; set; } = string.Empty;
    public string NameOriginal { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string Event { get; set; } = string.Empty;     // e.g., "AFTER INSERT"
    public string Table { get; set; } = string.Empty;     // Associated table (prefix-free)
    public string Definition { get; set; } = string.Empty;

    // Computed, read-only: sanitized for emission
    [JsonIgnore] // optional: omit from manifest JSON
    public string DefinitionSanitized
    {
        get { return StringHelper.SanitizeMySqlRoutineDefinition(Definition); }
    }
    public string? Comment { get; set; }
}
