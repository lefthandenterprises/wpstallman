using System.Text.Json;

namespace WPStallman.Core.Models;

public class Manifest
{
    public string Database { get; set; } = string.Empty;
    public string GeneratedAt { get; set; } = DateTime.UtcNow.ToString("o");
    public string DefaultPrefix { get; set; } = "wp_";

    public string InstallerClass { get; set; } = "MyPluginInstaller";

    public bool IncludeSeedData { get; set; }

    public List<TableDefinition> Tables { get; set; } = new();
    public List<ViewDefinition> Views { get; set; } = new();
    public List<StoredProcedureDefinition> StoredProcedures { get; set; } = new();
    public List<TriggerDefinition> Triggers { get; set; } = new();

    public string ToJSONStringCamelCase()
    {
        return JsonSerializer.Serialize(this, new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        });
    }

    public object ToCamelCaseObject()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        };

        // Serialize and then deserialize to get a camel-cased object
        var json = JsonSerializer.Serialize(this, options);
        return JsonSerializer.Deserialize<object>(json, options);
    }

    public void CreatePHPStatements()
    {
        // first, gather a list of all tables, procedures, views used

        // next, cycle through each stored procedure and format a Wordpress compatible create statement
        // replacing the wp_ prefix with the standard PHP to insert the prefix from the wpdb object

        // do the same for the views and triggers
    }
}
