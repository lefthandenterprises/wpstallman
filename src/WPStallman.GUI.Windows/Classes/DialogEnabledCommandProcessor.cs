using System.Text.Json;
using WPStallman.Core.Interfaces;
using WPStallman.Core.Classes;
using System; // <-- needed for Exception


namespace WPStallman.GUI.Windows;

/// <summary>
/// Adds native file/folder dialogs for Windows. Any unrecognized command is
/// passed through to the existing/regular GUICommandProcessor.
/// </summary>
public sealed class DialogEnabledCommandProcessor
{
    private readonly IPhotinoWindowHandler _handler;
    private readonly string _message;
    private readonly string? _requestId;

    // Your existing/regular processor
    private readonly GUICommandProcessor _inner;

    public DialogEnabledCommandProcessor(
        IPhotinoWindowHandler handler,
        string message,
        string? requestId,
        GUICommandProcessor inner)
    {
        _handler = handler;
        _message = message;
        _requestId = requestId;
        _inner = inner;
    }

    public CommandResponse ProcessCommand()
    {
        var jsonOpts = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        var env = JsonSerializer.Deserialize<CommandEnvelope>(_message, jsonOpts)
                  ?? throw new Exception("Command envelope was missing.");

        Console.WriteLine("Command:" + env.Command);

                var resp = new CommandResponse { RequestId = _requestId, Success = true };


        switch (env.Command)
        {
            case "ShowOpenFileDialog":
            case "OpenFiles":
                {

                    var filter = GetString(env.Details, "filter") ?? "All files (*.*)|*.*";
                    var title = GetString(env.Details, "title") ?? "Select file(s)";
                    var multi = GetBool(env.Details, "multi") ?? true;
                    var init = GetString(env.Details, "initialDirectory");
                    var files = _handler.OpenFiles(title, filter, multi, init);
                    resp.Payload = new { paths = files, isWindowsForms = _handler.IsWindowsForms };
                    return resp;
                }

            case "PickFolder":
                {
                    var desc = GetString(env.Details, "description") ?? "Select a folder";
                    var init = GetString(env.Details, "initialDirectory");
                    var show = GetBool(env.Details, "showNewFolderButton") ?? true;
                    var folder = _handler.PickFolder(desc, init, show);
                    resp.Payload = new { path = folder, isWindowsForms = _handler.IsWindowsForms };
                    return resp;
                }

            case "SaveFile":
                {
                    var title = GetString(env.Details, "title") ?? "Save As";
                    var filter = GetString(env.Details, "filter") ?? "All files (*.*)|*.*";
                    var name = GetString(env.Details, "defaultFileName");
                    var init = GetString(env.Details, "initialDirectory");
                    var file = _handler.SaveFile(title, filter, name, init);
                    resp.Payload = new { path = file, isWindowsForms = _handler.IsWindowsForms };
                    return resp;
                }

            // 👇 default/else → pass to your regular processor unchanged
            default:
                return _inner.ProcessCommand();
        }
    }

    // -------- helpers --------
    private static string? GetString(JsonElement el, string name) =>
        el.ValueKind == JsonValueKind.Object &&
        el.TryGetProperty(name, out var v) &&
        v.ValueKind == JsonValueKind.String
            ? v.GetString()
            : null;

    private static bool? GetBool(JsonElement el, string name) =>
        el.ValueKind == JsonValueKind.Object &&
        el.TryGetProperty(name, out var v) &&
        (v.ValueKind == JsonValueKind.True || v.ValueKind == JsonValueKind.False)
            ? v.GetBoolean()
            : (bool?)null;
}
