using System.Text.Json;
using System.Text.Json.Serialization;
using WPStallman.Core.Models;

namespace WPStallman.Core.Services;

public class ManifestGenerator
{
    private readonly JsonSerializerOptions _jsonOptions;

    public ManifestGenerator()
    {
        _jsonOptions = new JsonSerializerOptions
        {
            WriteIndented = true, // Pretty print for readability
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase // Matches our JSON standard
        };
    }

    /// <summary>
    /// Serializes a Manifest object to a JSON string.
    /// </summary>
    public string GenerateJson(Manifest manifest)
    {
        return JsonSerializer.Serialize(manifest, _jsonOptions);
    }

    /// <summary>
    /// Saves the manifest to a JSON file.
    /// </summary>
    public void SaveToFile(Manifest manifest, string filePath)
    {
        string json = GenerateJson(manifest);
        File.WriteAllText(filePath, json);
    }

    /// <summary>
    /// Loads a manifest from a JSON file (useful for regenerating installers later).
    /// </summary>
    public Manifest LoadFromFile(string filePath)
    {
        string json = File.ReadAllText(filePath);
        return JsonSerializer.Deserialize<Manifest>(json, _jsonOptions)
               ?? new Manifest();
    }
}
