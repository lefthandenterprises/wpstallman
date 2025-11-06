// SPDX-License-Identifier: MIT
#if WINDOWS
using System;
using System.Threading;
using System.Windows.Forms;

namespace WPStallman.Core.Platform.Windows;

/// <summary>
/// Centralized WinForms dialogs with STA marshalling. Used by handlers.
/// </summary>
public static class WindowsFileDialogs
{
    public static string[] OpenFiles(string title, string filter, bool multi, string? initialDirectory)
        => InvokeSta(() =>
        {
            using var dlg = new OpenFileDialog
            {
                Title = title,
                Filter = filter,
                Multiselect = multi,
                RestoreDirectory = true,
                CheckFileExists = true,
                InitialDirectory = InitDir(initialDirectory)
            };
            return dlg.ShowDialog() == DialogResult.OK ? dlg.FileNames : Array.Empty<string>();
        });

    public static string? PickFolder(string description, string? initialDirectory, bool showNewFolderButton)
        => InvokeSta(() =>
        {
            using var dlg = new FolderBrowserDialog
            {
                Description = description,
                ShowNewFolderButton = showNewFolderButton,
                SelectedPath = InitDir(initialDirectory)
            };
            return dlg.ShowDialog() == DialogResult.OK ? dlg.SelectedPath : null;
        });

    public static string? SaveFile(string title, string filter, string? defaultFileName, string? initialDirectory)
        => InvokeSta(() =>
        {
            Console.WriteLine("SaveFile title:" + title);
            Console.WriteLine("SaveFile filter:" + filter);
            Console.WriteLine("SaveFile defaultFileName:" + defaultFileName);
            Console.WriteLine("SaveFile initialDirectory:" + initialDirectory);

            using var dlg = new SaveFileDialog
            {
                Title = title,
                Filter = filter,
                RestoreDirectory = true,
                AddExtension = true,
                FileName = defaultFileName ?? string.Empty,
                InitialDirectory = InitDir(initialDirectory),
                OverwritePrompt = false
            };
            return dlg.ShowDialog() == DialogResult.OK ? dlg.FileName : null;
        });

    // ------- helpers -------
    private static T InvokeSta<T>(Func<T> body)
    {
        if (Thread.CurrentThread.GetApartmentState() == ApartmentState.STA)
            return body();

        T? result = default!;
        Exception? err = null;

        var t = new Thread(() =>
        {
            try { Application.EnableVisualStyles(); result = body(); }
            catch (Exception ex) { err = ex; }
        })
        { IsBackground = true };

        t.SetApartmentState(ApartmentState.STA);
        t.Start();
        t.Join();

        if (err != null) throw err;
        return result!;
    }

    private static string InitDir(string? path) =>
        string.IsNullOrWhiteSpace(path)
            ? Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments)
            : path!;
}
#endif
