using System.Text.Json;

public class CommandEnvelope
{
    public string? Command { get; set; }
    public JsonElement Details { get; set; }
    public string? RequestId { get; set; }
}
