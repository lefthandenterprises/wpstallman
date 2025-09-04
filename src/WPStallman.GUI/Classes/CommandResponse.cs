public class CommandResponse
{
    public bool Success { get; set; }
    public string Error { get; set; } = "";
    public object? Payload { get; set; }
    public string? RequestId { get; internal set; }
}