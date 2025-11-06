using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using Photino.NET;
using WPStallman.Core.Classes;
using WPStallman.Core.Interfaces;

namespace WPStallman.GUI.Classes;

public class PhotinoWindowHandler : IPhotinoWindowHandler
{
    private readonly PhotinoWindow _window;

    public PhotinoWindowHandler(PhotinoWindow window)
    {
        _window = window ?? throw new ArgumentNullException(nameof(window));
    }

    public CommandResponse MaximizeWindow()
    {
        var response = new CommandResponse();
        if (_window == null)
        {
            response.Success = false;
            response.Error = "Window object not found.";
        }
        else
        {
            _window.SetMaximized(true);
            response.Success = true;
        }

        return response;
    }

    public CommandResponse OpenUrl(CommandEnvelope envelope)
    {
        var response = new CommandResponse();
        string? url = envelope.Details.TryGetProperty("url", out var urlEl) ? urlEl.GetString() : null;
       
        if (string.IsNullOrWhiteSpace(url))
        {
            response.Success = false;
            response.Error = "URL must not be null or whitespace";
        }

        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri))
        {
            response.Success = false;
            response.Error = "Unable to create URL to open";
            return response;
        }

        if (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps)
        {
            response.Success = false;
            response.Error = "Invalid URL scheme - must be http or https";
            return response;
        }

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = url,
                UseShellExecute = true
            };
            Process.Start(psi);
            response.Success = true;
        }
        catch (Exception exc)
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
            {
                Process.Start("xdg-open", url);
                response.Success = true;
            }

            else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            {
                Process.Start("open", url);
                response.Success = true;
            }

            else
            {
                response.Success = false;
                response.Error = exc.Message;
            }

        }

        return response;
    }

    public CommandResponse ShowOpenDialog(CommandEnvelope envelope)
    {
        string filter = envelope.Details.TryGetProperty("Filter", out var filterProp)
             ? (filterProp.GetString() ?? "*.*")
            : "*.*";

        var fileToOpen = OpenFileDialogHelper.ShowOpenFileDialog("Open Manifest", filter);

        var response = new CommandResponse
        {
            Success = !string.IsNullOrEmpty(fileToOpen),
            Payload = new
            {
                FileToOpen = fileToOpen,
                FileName = !string.IsNullOrEmpty(fileToOpen) ? Path.GetFileName(fileToOpen) : null
            }
        };

        return response;
    }

    public CommandResponse ShowSaveDialog(CommandEnvelope envelope)
    {
        string suggested = envelope.Details.TryGetProperty("SuggestedFilename", out var suggProp)
           ? (suggProp.GetString() ?? "manifest.json")
            : "manifest.json";

        string filterSave = envelope.Details.TryGetProperty("Filter", out var filterSaveProp)
            ? (filterSaveProp.GetString() ?? "*.*")
            : "*.*";

        var fileToSave = SaveFileDialogHelper.ShowSaveFileDialog(suggested, filterSave);

        var response = new CommandResponse
        {
            Success = !string.IsNullOrEmpty(fileToSave),
            Payload = new
            {
                Path = fileToSave,
                FileName = !string.IsNullOrEmpty(fileToSave) ? Path.GetFileName(fileToSave) : null
            }
        };

        return response;
    }

        public bool IsWindowsForms => false;

    public string[] OpenFiles(string title = "Select file(s)",
                              string filter = "All files (*.*)|*.*",
                              bool multi = true,
                              string? initialDirectory = null)
        => Array.Empty<string>();

    public string? PickFolder(string description = "Select a folder",
                              string? initialDirectory = null,
                              bool showNewFolderButton = true)
        => null;

    public string? SaveFile(string title = "Save As",
                            string filter = "All files (*.*)|*.*",
                            string? defaultFileName = null,
                            string? initialDirectory = null)
        => null;
}