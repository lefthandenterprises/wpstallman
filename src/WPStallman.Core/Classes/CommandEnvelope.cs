using System.Text.Json;

namespace WPStallman.Core.Classes;
public class CommandEnvelope
{
    public string? Command { get; set; }
    public JsonElement Details { get; set; }
    public string? RequestId { get; set; }
}
