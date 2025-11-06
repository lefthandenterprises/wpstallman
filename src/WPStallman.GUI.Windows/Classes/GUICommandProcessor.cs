using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Collections.Generic;

using WPStallman.Core.Interfaces;   // IPhotinoWindowHandler
using WPStallman.Core.Classes;      // SettingsRepository, manifest DTOs
using WPStallman.Core.Services;     // DatabaseIntrospector
using WPStallman.Core.Utilities;    // StringHelper, ManifestGenerator, InstallerClassGenerator

// If your PhotinoHandler lives under this namespace, keep this line;
// otherwise see note in section 4 below.
namespace WPStallman.GUI.Windows;



public sealed class GUICommandProcessor
{
    private readonly IPhotinoWindowHandler _handler;
    private readonly string _message;
    private readonly string? _requestId;

    public GUICommandProcessor(IPhotinoWindowHandler handler, string message, string? requestId)
    {
        _handler = handler;
        _message = message;
        _requestId = requestId;
    }

    public CommandResponse ProcessCommand()
    {
        var jsonOpts = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        var envelope = JsonSerializer.Deserialize<CommandEnvelope>(_message, jsonOpts)
                  ?? throw new Exception("Command envelope was missing.");

        var response = new CommandResponse { RequestId = _requestId, Success = true };

        bool hasDetails = envelope.Details.ValueKind is not JsonValueKind.Undefined and not JsonValueKind.Null;
        var manifestGenerator = new ManifestGenerator();
        var installerClassGenerator = new InstallerClassGenerator();

        switch (envelope.Command)
        {
            // case "OpenFiles":
            //     {
            //         var filter = GetString(env.Details, "filter") ?? "All files (*.*)|*.*";
            //         var title = GetString(env.Details, "title") ?? "Select file(s)";
            //         var multi = GetBool(env.Details, "multi") ?? true;
            //         var init = GetString(env.Details, "initialDirectory");
            //         var files = _handler.OpenFiles(title, filter, multi, init);
            //         resp.Payload = new { paths = files, isWindowsForms = _handler.IsWindowsForms };
            //         return resp;
            //     }
            // case "PickFolder":
            //     {
            //         var desc = GetString(env.Details, "description") ?? "Select a folder";
            //         var init = GetString(env.Details, "initialDirectory");
            //         var show = GetBool(env.Details, "showNewFolderButton") ?? true;
            //         var folder = _handler.PickFolder(desc, init, show);
            //         resp.Payload = new { path = folder, isWindowsForms = _handler.IsWindowsForms };
            //         return resp;
            //     }
            // case "SaveFile":
            //     {
            //         var title = GetString(env.Details, "title") ?? "Save As";
            //         var filter = GetString(env.Details, "filter") ?? "All files (*.*)|*.*";
            //         var name = GetString(env.Details, "defaultFileName");
            //         var init = GetString(env.Details, "initialDirectory");
            //         var file = _handler.SaveFile(title, filter, name, init);
            //         resp.Payload = new { path = file, isWindowsForms = _handler.IsWindowsForms };
            //         return resp;
            //     }
            case "MaximizeWindow":
                response = _handler.MaximizeWindow();
                break;

            case "GetStartupSettings":
                using (var settingsRepo = new SettingsRepository())
                {
                    var payload = new
                    {
                        ConnectionString = settingsRepo.Load("ConnectionString") ?? "server=localhost;uid=root;pwd=;database=wp_my_plugin",
                        DbPrefix = settingsRepo.Load("DbPrefix") ?? "wp_",
                        InstallerClassName = settingsRepo.Load("InstallerClassName") ?? "MyPluginInstaller",
                        IncludeSeedData = settingsRepo.Load("IncludeSeedData") ?? "true",
                        LastManifest = settingsRepo.Load("LastManifest") ?? ""
                    };
                    response.Success = true;
                    response.Payload = payload;
                }
                break;

            case "OpenUrl":
                response = _handler.OpenUrl(envelope);
                break;
            case "ShowOpenFileDialog":
                response = _handler.ShowOpenDialog(envelope);
                break;
            case "ShowSaveDialog":
                response = _handler.ShowSaveDialog(envelope);
                break;

            case "WriteFile":
                {
                    var filePath = envelope.Details.GetProperty("Path").GetString() ?? throw new Exception("Path is required.");
                    var data = envelope.Details.GetProperty("Data").GetString() ?? string.Empty;
                    File.WriteAllText(filePath, data, new UTF8Encoding(false));
                    response.Success = true;
                }
                break;

            case "IntrospectDatabase":
                {
                    if (!hasDetails)
                        throw new Exception("IntrospectDatabase requires details.");

                    var introspectDetails = envelope.Details.Deserialize<GenerateManifestDetails>(jsonOpts)
                                            ?? throw new Exception("Missing or invalid IntrospectDatabase details.");

                    var introspector = new DatabaseIntrospector(
                        introspectDetails.ConnectionString,
                        introspectDetails.DbPrefix,
                        introspectDetails.IncludeSeedData
                    );

                    var manifestJson = introspector.GenerateManifestJSON();
                    using (var settingsRepo = new SettingsRepository())
                    {
                        settingsRepo.Save("ConnectionString", introspectDetails.ConnectionString);
                        settingsRepo.Save("DbPrefix", introspectDetails.DbPrefix);
                        settingsRepo.Save("InstallerClassName", introspectDetails.InstallerClassName);
                        settingsRepo.Save("IncludeSeedData", introspectDetails.IncludeSeedData.ToString());
                        settingsRepo.Save("LastManifest", manifestJson);
                    }

                    response.Success = true;
                    response.Payload = manifestJson;
                }
                break;

            case "ParseInstallerManifest":
                {
                    var filePath = envelope.Details.GetProperty("filePath").GetString();
                    if (string.IsNullOrWhiteSpace(filePath) || !File.Exists(filePath))
                    {
                        response.Success = false;
                        response.Error = "Invalid or missing file path.";
                        break;
                    }

                    try
                    {
                        var manifest = manifestGenerator.LoadFromFile(filePath);

                        response.Success = true;
                        response.Payload = new
                        {
                            manifest = manifest.ToCamelCaseObject(),
                            defaultConnectionString = ""
                        };
                    }
                    catch (Exception ex)
                    {
                        response.Success = false;
                        response.Error = $"Failed to parse manifest: {ex.Message}";
                    }
                }
                break;

            case "CreateInstallerFiles":
                {
                    try
                    {
                        var raw = envelope.Details.GetRawText();
                        var req = JsonSerializer.Deserialize<CreateInstallerDetails>(raw, jsonOpts);

                        if (req?.Manifest == null)
                        {
                            response.Success = false;
                            response.Error = "Missing Manifest in request.";
                            break;
                        }

                        if (!string.IsNullOrWhiteSpace(req.InstallerClassNameOverride))
                        {
                            req.Manifest.InstallerClass = req.InstallerClassNameOverride;
                        }

                        int t = req.Manifest.Tables?.Count ?? 0;
                        int v = req.Manifest.Views?.Count ?? 0;
                        int p = req.Manifest.StoredProcedures?.Count ?? 0;
                        int g = req.Manifest.Triggers?.Count ?? 0;

                        var files = installerClassGenerator.CreatePreviewFiles(req.Manifest);

                        response.Success = true;
                        response.Payload = new
                        {
                            counts = new { tables = t, views = v, procedures = p, triggers = g },
                            files
                        };
                    }
                    catch (Exception ex)
                    {
                        response.Success = false;
                        response.Error = $"CreateInstallerFiles failed: {ex.Message}";
                    }
                }
                break;

            case "CheckIfFileAlreadyExists":
                {
                    if (!hasDetails)
                    {
                        response.Success = false;
                        response.Error = "CheckIfFileAlreadyExists requires details.";
                        break;
                    }

                    string? path = null;
                    if (envelope.Details.TryGetProperty("Path", out var p1) && p1.ValueKind == JsonValueKind.String)
                        path = p1.GetString();
                    else if (envelope.Details.TryGetProperty("FullPath", out var p2) && p2.ValueKind == JsonValueKind.String)
                        path = p2.GetString();
                    else if (envelope.Details.TryGetProperty("DestinationZipFilePath", out var p3) && p3.ValueKind == JsonValueKind.String)
                        path = p3.GetString();

                    if (string.IsNullOrWhiteSpace(path))
                    {
                        response.Success = false;
                        response.Error = "A valid file path was not provided.";
                        break;
                    }

                    var expanded = Environment.ExpandEnvironmentVariables(path);
                    if (Path.GetInvalidPathChars().Any(expanded.Contains))
                    {
                        response.Success = false;
                        response.Error = "Invalid characters in provided path.";
                        response.Payload = new { Path = expanded };
                        break;
                    }

                    var dir = Path.GetDirectoryName(expanded);
                    var exists = File.Exists(expanded);
                    var dirExists = !string.IsNullOrEmpty(dir) && Directory.Exists(dir);

                    response.Success = true;
                    response.Payload = new
                    {
                        Exists = exists,
                        Path = expanded,
                        FileName = Path.GetFileName(expanded),
                        Directory = dir,
                        DirectoryExists = dirExists
                    };
                }
                break;

            case "CreateInstallerZip":
                {
                    if (!hasDetails)
                        throw new Exception("CreateInstallerZip requires command envelope details");

                    var destinationZipFilePath =
                        envelope.Details.TryGetProperty("DestinationZipFilePath", out var destEl)
                        && destEl.ValueKind == JsonValueKind.String
                            ? destEl.GetString()
                            : null;

                    if (string.IsNullOrWhiteSpace(destinationZipFilePath))
                        throw new Exception("CreateInstallerZip requires DestinationZipFilePath");
                    if (Path.GetInvalidPathChars().Any(destinationZipFilePath.Contains))
                        throw new Exception("Invalid characters in DestinationZipFilePath");
                    if (!string.Equals(Path.GetExtension(destinationZipFilePath), ".zip", StringComparison.OrdinalIgnoreCase))
                        throw new Exception("DestinationZipFilePath must end with .zip");

                    var directory = Path.GetDirectoryName(destinationZipFilePath);
                    if (!string.IsNullOrEmpty(directory) && !Directory.Exists(directory))
                        Directory.CreateDirectory(directory);

                    if (!envelope.Details.TryGetProperty("PreviewFiles", out var filesEl)
                        || filesEl.ValueKind != JsonValueKind.Array
                        || filesEl.GetArrayLength() == 0)
                    {
                        response.Success = false;
                        response.Error = "No preview files to zip. Generate a preview first.";
                        break;
                    }

                    var allowOverwrite = envelope.Details.TryGetProperty("AllowOverwrite", out var ao)
                                         && ao.ValueKind == JsonValueKind.True;

                    if (File.Exists(destinationZipFilePath) && !allowOverwrite)
                    {
                        response.Success = false;
                        response.Error = "Destination file already exists.";
                        response.Payload = new
                        {
                            reason = "FILE_EXISTS",
                            path = destinationZipFilePath,
                            fileName = Path.GetFileName(destinationZipFilePath)
                        };
                        break;
                    }

                    // Case-insensitive property getter
                    static bool TryGetPropCI(JsonElement obj, string name, out JsonElement value)
                    {
                        foreach (var p in obj.EnumerateObject())
                        {
                            if (string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase))
                            {
                                value = p.Value; return true;
                            }
                        }
                        value = default; return false;
                    }

                    var utf8NoBom = new UTF8Encoding(false);
                    var items = new List<(string Name, string Content, int ByteLen)>();

                    foreach (var fileEl in filesEl.EnumerateArray())
                    {
                        if (fileEl.ValueKind != JsonValueKind.Object) continue;

                        // Accept Name/fileName and Content/content
                        string? name = null;
                        if (TryGetPropCI(fileEl, "Name", out var nEl) && nEl.ValueKind == JsonValueKind.String)
                            name = nEl.GetString();
                        else if (TryGetPropCI(fileEl, "fileName", out var fnEl) && fnEl.ValueKind == JsonValueKind.String)
                            name = fnEl.GetString();

                        if (string.IsNullOrWhiteSpace(name)) continue;

                        string content = "";
                        if (TryGetPropCI(fileEl, "Content", out var cEl) && cEl.ValueKind == JsonValueKind.String)
                            content = cEl.GetString() ?? "";
                        else if (TryGetPropCI(fileEl, "content", out var ceEl) && ceEl.ValueKind == JsonValueKind.String)
                            content = ceEl.GetString() ?? "";

                        // Normalize path inside zip
                        name = name.Replace('\\', '/').TrimStart('/');

                        items.Add((name, content, utf8NoBom.GetByteCount(content)));
                    }

                    var totalFiles = items.Count;
                    var nonEmptyFiles = items.Count(i => i.ByteLen > 0);

                    if (totalFiles == 0)
                    {
                        response.Success = false;
                        response.Error = "No valid files to include in zip (property name mismatch?).";
                        response.Payload = new { reason = "NO_FILES_AFTER_FILTER", destinationZipFilePath };
                        break;
                    }
                    if (nonEmptyFiles == 0)
                    {
                        response.Success = false;
                        response.Error = "All files are empty; refusing to create an empty zip.";
                        response.Payload = new { reason = "ALL_FILES_EMPTY", destinationZipFilePath, totalFiles };
                        break;
                    }

                    using (var fs = new FileStream(destinationZipFilePath, FileMode.Create, FileAccess.ReadWrite, FileShare.None))
                    using (var archive = new ZipArchive(fs, ZipArchiveMode.Create, leaveOpen: false, entryNameEncoding: Encoding.UTF8))
                    {
                        foreach (var it in items)
                        {
                            var entry = archive.CreateEntry(it.Name, CompressionLevel.Optimal);
                            using var entryStream = entry.Open();
                            using var writer = new StreamWriter(entryStream, utf8NoBom);
                            writer.Write(it.Content);
                        }
                    }

                    // Verify zip has at least one non-empty entry (skip directory entries)
                    int entryCount = 0, nonEmptyEntryCount = 0;
                    using (var checkFs = new FileStream(destinationZipFilePath, FileMode.Open, FileAccess.Read, FileShare.Read))
                    using (var checkArchive = new ZipArchive(checkFs, ZipArchiveMode.Read, leaveOpen: false, entryNameEncoding: Encoding.UTF8))
                    {
                        foreach (var e in checkArchive.Entries)
                        {
                            if (string.IsNullOrEmpty(e.Name)) continue;
                            entryCount++;
                            if (e.Length > 0) nonEmptyEntryCount++;
                        }
                    }

                    if (entryCount == 0 || nonEmptyEntryCount == 0)
                    {
                        try { File.Delete(destinationZipFilePath); } catch { }
                        response.Success = false;
                        response.Error = "Zip integrity check failed: archive is empty or contains only empty entries.";
                        response.Payload = new { reason = "ZIP_EMPTY", expectedFiles = totalFiles, nonEmptySourceFiles = nonEmptyFiles };
                        break;
                    }

                    response.Success = true;
                    response.Payload = new
                    {
                        Message = $"Zip file saved to {destinationZipFilePath}",
                        filesAdded = entryCount,
                        nonEmptyEntries = nonEmptyEntryCount
                    };
                }
                break;

            case "CopyText":
                {
                    if (envelope.Details.ValueKind != JsonValueKind.Object ||
                        !envelope.Details.TryGetProperty("text", out var textEl))
                    {
                        response.Success = false;
                        response.Error = "CopyText requires a Details.text string.";
                        break;
                    }

                    var text = textEl.GetString() ?? string.Empty;
                    var ok = StringHelper.TryCopyText(text);

                    response.Success = ok;
                    if (!ok)
                        response.Error = "Clipboard copy failed or clipboard tool not available.";
                }
                break;

            case "ReadContentText":
                {
                    if (!hasDetails)
                    {
                        response.Success = false;
                        response.Error = "ReadContentText requires details.";
                        break;
                    }

                    var rel = envelope.Details.TryGetProperty("RelativePath", out var relEl) &&
                              relEl.ValueKind == JsonValueKind.String
                                ? relEl.GetString()
                                : null;

                    if (string.IsNullOrWhiteSpace(rel))
                    {
                        response.Success = false;
                        response.Error = "RelativePath is required.";
                        break;
                    }

                    var contentRoot = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "wwwroot"));
                    var normalizedRel = rel.Replace('\\', Path.DirectorySeparatorChar)
                                           .Replace('/', Path.DirectorySeparatorChar)
                                           .TrimStart(Path.DirectorySeparatorChar);

                    var fullPath = Path.GetFullPath(Path.Combine(contentRoot, normalizedRel));
                    if (!fullPath.StartsWith(contentRoot, StringComparison.Ordinal))
                    {
                        response.Success = false;
                        response.Error = "Invalid path.";
                        break;
                    }

                    if (!File.Exists(fullPath))
                    {
                        response.Success = false;
                        response.Error = $"File not found: {normalizedRel}";
                        response.Payload = new { Path = normalizedRel };
                        break;
                    }

                    var text = File.ReadAllText(fullPath, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
                    response.Success = true;
                    response.Payload = new { Text = text, Path = normalizedRel };
                }
                break;

            default:
                response.Success = false;
                response.Error = $"Unknown command: {envelope.Command}";
                break;
        }

        // ... your existing commands ...
        return response;
    }

    private static string? GetString(JsonElement el, string name) =>
        el.ValueKind == JsonValueKind.Object && el.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String
            ? v.GetString()
            : null;

    private static bool? GetBool(JsonElement el, string name) =>
        el.ValueKind == JsonValueKind.Object && el.TryGetProperty(name, out var v) &&
        (v.ValueKind == JsonValueKind.True || v.ValueKind == JsonValueKind.False)
            ? v.GetBoolean()
            : (bool?)null;
}
