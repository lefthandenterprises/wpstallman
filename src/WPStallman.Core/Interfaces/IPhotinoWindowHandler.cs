using WPStallman.Core.Classes;

namespace WPStallman.Core.Interfaces;

public interface IPhotinoWindowHandler
{
    public CommandResponse OpenUrl(CommandEnvelope envelope);

    public CommandResponse MaximizeWindow();
    public CommandResponse ShowOpenDialog(CommandEnvelope envelope);
    public CommandResponse ShowSaveDialog(CommandEnvelope envelope); bool IsWindowsForms { get; }

    /// <summary>Open one or more files. Empty array = cancelled.</summary>
    string[] OpenFiles(string title = "Select file(s)",
                       string filter = "All files (*.*)|*.*",
                       bool multi = true,
                       string? initialDirectory = null);

    /// <summary>Pick a folder. Null = cancelled.</summary>
    string? PickFolder(string description = "Select a folder",
                       string? initialDirectory = null,
                       bool showNewFolderButton = true);

    /// <summary>Save as. Null = cancelled.</summary>
    string? SaveFile(string title = "Save As",
                     string filter = "All files (*.*)|*.*",
                     string? defaultFileName = null,
                     string? initialDirectory = null);
}

