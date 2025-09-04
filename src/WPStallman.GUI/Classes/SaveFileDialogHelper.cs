// SaveFileDialogHelper.cs
using Gtk;

namespace WPStallman.GUI.Classes
{
    public static class SaveFileDialogHelper
    {
   public static string? ShowSaveFileDialog(string suggestedFilename, string filter = "*.*")
    {
        string? selectedPath = null;
        Application.Init(); // Safe to call repeatedly

        using (var dialog = new FileChooserDialog(
            "Save File As...",
            null,
            FileChooserAction.Save,
            "Cancel", ResponseType.Cancel,
            "Save", ResponseType.Accept))
        {
            dialog.CurrentName = suggestedFilename;

            // Apply filter if not the default "*.*"
            if (!string.IsNullOrWhiteSpace(filter) && filter != "*.*")
            {
                var fileFilter = new FileFilter();
                fileFilter.Name = filter;
                fileFilter.AddPattern(filter);
                dialog.Filter = fileFilter;
            }

            if (dialog.Run() == (int)ResponseType.Accept)
            {
                selectedPath = dialog.Filename;
            }
            dialog.Destroy();
        }
        return selectedPath;
    }
        
    }
}
