using Gtk;

namespace WPStallman.GUI.Classes
{
    public static class OpenFileDialogHelper
    {
        public static string? ShowOpenFileDialog(string title = "Open File", string filterPattern = "*.*")
        {
            string? selectedPath = null;
            Application.Init(); // Safe to call repeatedly

            using (var dialog = new FileChooserDialog(
                title,
                null,
                FileChooserAction.Open,
                "Cancel", ResponseType.Cancel,
                "Open", ResponseType.Accept))
            {
                // Set filter if provided
                if (!string.IsNullOrWhiteSpace(filterPattern) && filterPattern != "*.*")
                {
                    var filter = new FileFilter();
                    filter.Name = filterPattern;
                    filter.AddPattern(filterPattern);
                    dialog.AddFilter(filter);
                }

                if (dialog.Run() == (int)ResponseType.Accept)
                {
                    selectedPath = dialog.Filename;
                }
                dialog.Destroy();
            }
            // Do NOT call Application.Quit()
            return selectedPath;
        }
    }
}
