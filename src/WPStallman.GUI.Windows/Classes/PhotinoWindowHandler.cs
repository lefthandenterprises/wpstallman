using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using Photino.NET;
using WPStallman.Core.Classes;
using WPStallman.Core.Interfaces;
using System.Text.Json;                 // <- for JsonElement, JsonValueKind
using System.Collections.Generic;       // <- if you use List<>
using WPStallman.Core.Platform.Windows; // <- for WindowsFileDialogs

using System.Linq;

namespace WPStallman.GUI.Classes;

public partial class PhotinoWindowHandler : IPhotinoWindowHandler
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

        var fileToOpen = WindowsFileDialogs
            .OpenFiles("Open Manifest", filter, multi: false, initialDirectory: null)
            .FirstOrDefault();

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
        var resp = new CommandResponse { RequestId = envelope.RequestId, Success = false };

        // Title (optional)
        var title = envelope.Details.TryGetPropertyCI("title", out var t) ? t.GetString() : "Save As";

        // File name: accept several aliases (case-insensitive)
        string? defaultName = null;
        if (envelope.Details.TryGetPropertyCI("defaultFileName", out var n) && n.ValueKind == JsonValueKind.String)
            defaultName = n.GetString();
        else if (envelope.Details.TryGetPropertyCI("fileName", out var fn) && fn.ValueKind == JsonValueKind.String)
            defaultName = fn.GetString();
        else if (envelope.Details.TryGetPropertyCI("SuggestedFilename", out var sfn) && sfn.ValueKind == JsonValueKind.String)
            defaultName = sfn.GetString();

        // Initial directory (optional, expand %USERPROFILE% etc)
        var initialDirRaw = envelope.Details.TryGetPropertyCI("initialDirectory", out var id) ? id.GetString()
                          : envelope.Details.TryGetPropertyCI("InitialDirectory", out var id2) ? id2.GetString()
                          : null;
        var initialDir = DialogHelpers.ExpandPath(initialDirRaw);

        // Filter (accept raw; normalize; if just *.* and we have an extension, make a nicer filter)
        var filterRaw = envelope.Details.TryGetPropertyCI("filter", out var f) ? f.GetString()
                     : envelope.Details.TryGetPropertyCI("Filter", out var f2) ? f2.GetString()
                     : null;

        // If filter is missing or basically "*.*", try to infer from defaultName extension
        string? extFromName = null;
        if (!string.IsNullOrWhiteSpace(defaultName))
        {
            var ext = Path.GetExtension(defaultName);
            if (!string.IsNullOrWhiteSpace(ext)) extFromName = ext.Trim();
        }

        // Normalize into valid WinForms filter pairs
        var filter = DialogHelpers.NormalizeFilter(
            string.IsNullOrWhiteSpace(filterRaw) || filterRaw.Trim() == "*.*" ? null : filterRaw,
            !string.IsNullOrWhiteSpace(defaultName) ? defaultName : extFromName
        );

        try
        {
            // DEBUG (optional): log what we resolved
            Console.WriteLine($"SaveFile title:{title}");
            Console.WriteLine($"SaveFile filter:{filter}");
            Console.WriteLine($"SaveFile defaultFileName:{defaultName}");
            Console.WriteLine($"SaveFile initialDirectory:{initialDir}");

            // Invoke dialog
           // in ShowSaveDialog(...)
var path = WindowsFileDialogs.SaveFile(title ?? "Save As", filter, defaultName ?? "", initialDir);


            resp.Success = !string.IsNullOrWhiteSpace(path);
            resp.Payload = new
            {
                Path = path,
                FileToSave = path,
                isWindowsForms = true
            };
            if (!resp.Success) resp.Error = "User cancelled or no path selected.";
        }
        catch (Exception ex)
        {
            resp.Success = false;
            resp.Error = ex.ToString();
        }

        return resp;
    }

    public bool IsWindowsForms => true;

    public string[] OpenFiles(string title = "Select file(s)",
                              string filter = "All files (*.*)|*.*",
                              bool multi = true,
                              string? initialDirectory = null)
#if WINDOWS
        => WindowsFileDialogs.OpenFiles(title, filter, multi, initialDirectory);
#else
        => Array.Empty<string>();
#endif

    public string? PickFolder(string description = "Select a folder",
                              string? initialDirectory = null,
                              bool showNewFolderButton = true)
#if WINDOWS
        => WindowsFileDialogs.PickFolder(description, initialDirectory, showNewFolderButton);
#else
        => null;
#endif

    public string? SaveFile(string title = "Save As",
                            string filter = "All files (*.*)|*.*",
                            string? defaultFileName = null,
                            string? initialDirectory = null)
#if WINDOWS
        => WindowsFileDialogs.SaveFile(title, filter, defaultFileName, initialDirectory);
#else
        => null;
#endif
}

// Case-insensitive property getter for JsonElement objects.
internal static class JsonElementExtensions
{
    public static bool TryGetPropertyCI(this JsonElement obj, string name, out JsonElement value)
    {
        if (obj.ValueKind != JsonValueKind.Object)
        {
            value = default;
            return false;
        }

        foreach (var p in obj.EnumerateObject())
        {
            if (string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase))
            {
                value = p.Value;
                return true;
            }
        }

        value = default;
        return false;
    }
}

internal static class DialogHelpers
{
    // Expands %USERPROFILE% etc.; returns null if input is null/empty.
    public static string? ExpandPath(string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return null;
        try
        {
            // Windows env expansion
            var expanded = Environment.ExpandEnvironmentVariables(path);

            // Normalize slashes
            expanded = expanded.Replace('/', Path.DirectorySeparatorChar);

            return expanded;
        }
        catch
        {
            return path;
        }
    }

    // Build a valid WinForms filter string.
    // If caller passes "All files (*.*)|*.*" or any string with '|' we respect it.
    // If caller passes "*.php" we convert to "PHP files (*.php)|*.php|All files (*.*)|*.*".
    // If caller passes null/empty, we infer from the suggested filename extension (if any).
    public static string NormalizeFilter(string? filterRaw, string? defaultNameOrExt)
    {
        // Already valid (contains '|')? Use as-is.
        if (!string.IsNullOrWhiteSpace(filterRaw) && filterRaw.Contains('|'))
            return filterRaw;

        // Get extension hint
        string? ext = null;

        if (!string.IsNullOrWhiteSpace(defaultNameOrExt))
        {
            // If they gave a filename, pull extension; if they gave "*.php", normalize to .php
            if (defaultNameOrExt.StartsWith("*.", StringComparison.Ordinal))
            {
                ext = defaultNameOrExt.Substring(1); // -> ".php"
            }
            else
            {
                var e = Path.GetExtension(defaultNameOrExt);
                if (!string.IsNullOrWhiteSpace(e)) ext = e;
            }
        }

        // If filterRaw is something like "*.json", turn it into a proper pair.
        if (!string.IsNullOrWhiteSpace(filterRaw) && filterRaw.Contains('*'))
        {
            var pat = filterRaw.Trim();
            var pretty = PrettyFromPattern(pat);
            return $"{pretty} ({pat})|{pat}|All files (*.*)|*.*";
        }

        // If we have an extension (e.g., ".php"), prefer that
        if (!string.IsNullOrWhiteSpace(ext) && ext.StartsWith('.'))
        {
            var pat = $"*{ext}";
            var pretty = $"{ext.Trim('.').ToUpperInvariant()} files";
            return $"{pretty} ({pat})|{pat}|All files (*.*)|*.*";
        }

        // No hints? Fallback
        return "All files (*.*)|*.*";

        static string PrettyFromPattern(string pat)
        {
            // "*.php" -> "PHP files"
            var dotIdx = pat.LastIndexOf('.');
            if (dotIdx >= 0 && dotIdx < pat.Length - 1)
            {
                var ext = pat.Substring(dotIdx + 1).Trim('*').Trim();
                if (!string.IsNullOrWhiteSpace(ext))
                    return $"{ext.ToUpperInvariant()} files";
            }
            return "Files";
        }
    }
}
