using System.Collections.Generic;
using System.Text.Json.Serialization;
using WPStallman.Core.Utilities;

namespace WPStallman.Core.Models
{
    public class StoredProcedureDefinition
    {
        public string Name { get; set; } = string.Empty;
        public string NameOriginal { get; set; } = string.Empty;
        public string FullName { get; set; } = string.Empty;
        public List<StoredProcedureParameter> Parameters { get; set; } = new();
        public string Definition { get; set; } = string.Empty;

        // Computed, read-only: sanitized for emission
        [JsonIgnore] // optional: omit from manifest JSON
        public string DefinitionSanitized
        {
            get { return StringHelper.SanitizeMySqlRoutineDefinition(Definition); }
        }

        public string? Comment { get; set; }
    }

    public class StoredProcedureParameter
    {
        public string Mode { get; set; } = "IN"; // IN, OUT, INOUT
        public string Name { get; set; } = string.Empty;
        public string Type { get; set; } = string.Empty; // e.g., "INT", "DATETIME", "VARCHAR(255)"
    }
}
