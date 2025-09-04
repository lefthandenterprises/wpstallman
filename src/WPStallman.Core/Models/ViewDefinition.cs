using System.Text.Json.Serialization;
using WPStallman.Core.Utilities;

namespace WPStallman.Core.Models
{
    public class ViewDefinition
    {
        public string Name { get; set; } = string.Empty;
        public string NameOriginal { get; set; } = string.Empty;
        public string FullName { get; set; } = string.Empty;
        public string Definition { get; set; } = string.Empty; // CREATE VIEW ... AS SELECT ...

        [JsonIgnore] // optional
        public string DefinitionSanitized
        {
            get { return StringHelper.SanitizeMySqlViewDefinition(Definition); }
        }

        public string? Comment { get; set; }
    }
}
