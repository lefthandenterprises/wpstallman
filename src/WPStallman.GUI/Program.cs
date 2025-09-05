using System;
using Photino.NET;
using WPStallman.GUI.Classes;
using System.Text.Json;
using WPStallman.Core.Services;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Collections.Generic;
using WPStallman.Core.Models;
using WPStallman.Core.Utilities;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace WPStallman.GUI
{
    class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            var window = new PhotinoWindow()
                .SetTitle("W. P. Stallman")
                .SetSize(1200, 900)
                .SetMinSize(800, 600)
                .Load("wwwroot/index.html");

            // --- Window icon (helps taskbar/dock when launching AppImage directly) ---
            try
            {
                var baseDir = AppContext.BaseDirectory;

                // Choose a sensible default per platform
                string iconPath;
                if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                {
                    // Use the .ico you embed for Windows builds
                    iconPath = Path.Combine(baseDir, "wwwroot", "img", "WPS.ico");
                }
                else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
                {
                    // If you ship an ICNS, set it here (otherwise PNG is fine too)
                    var icns = Path.Combine(baseDir, "wwwroot", "app.icns");
                    iconPath = File.Exists(icns)
                        ? icns
                        : Path.Combine(baseDir, "wwwroot", "img", "WPS-256.png");
                }
                else
                {
                    // Linux: PNG works great
                    iconPath = Path.Combine(baseDir, "wwwroot", "img", "WPS-256.png");
                }

                if (File.Exists(iconPath))
                {
                    window.SetIconFile(iconPath);
                    Console.WriteLine($"[Init] Window icon set: {iconPath}");
                }
                else
                {
                    Console.WriteLine($"[Init] Icon file not found (skipping SetIconFile): {iconPath}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Init] SetIconFile error: {ex.Message}");
            }
            // ------------------------------------------------------------------------

            window.RegisterWebMessageReceivedHandler((sender, message) =>
            {
                var win = sender as PhotinoWindow;
                var response = new CommandResponse();
                string requestId = null;

                try
                {
                    // Preserve RequestId from raw JSON
                    using (var jsonDoc = JsonDocument.Parse(message))
                    {
                        if (jsonDoc.RootElement.TryGetProperty("RequestId", out var ridProp)
                            && ridProp.ValueKind == JsonValueKind.String)
                        {
                            requestId = ridProp.GetString();
                        }
                    }

                    // with:
                    var jsonOpts = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
                    var envelope = JsonSerializer.Deserialize<CommandEnvelope>(message, jsonOpts);

                    Manifest manifest = new Manifest();
                    string filePath = string.Empty;

                    if (envelope == null)
                        throw new Exception("Command envelope was missing for request.");

                    bool hasDetails = envelope.Details.ValueKind != JsonValueKind.Undefined
                                   && envelope.Details.ValueKind != JsonValueKind.Null;

                    var manifestGenerator = new ManifestGenerator();
                    var installerClassGenerator = new InstallerClassGenerator();

                    switch (envelope.Command)
                    {
                        case "MaximizeWindow":
                            var winObj = sender as PhotinoWindow;
                            if (winObj != null)
                            {
                                winObj.SetMaximized(true);
                                response.Success = true;
                            }
                            else
                            {
                                response.Success = false;
                                response.Error = "Window object not found.";
                            }
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

                        case "ShowOpenFileDialog":

                            // Optionally accept a suggested filter from JS
                            string filter = envelope.Details.TryGetProperty("Filter", out var filterProp)
                                ? filterProp.GetString()
                                : "*.*";

                            var fileToOpen = OpenFileDialogHelper.ShowOpenFileDialog("Open Manifest", filter);

                            response.Success = !string.IsNullOrEmpty(fileToOpen);
                            response.Payload = new
                            {
                                FileToOpen = fileToOpen,
                                FileName = !string.IsNullOrEmpty(fileToOpen) ? System.IO.Path.GetFileName(fileToOpen) : null
                            };
                            break;
                        case "ShowSaveDialog":
                            // Optionally accept a suggested filename and filter from JS
                            string suggested = envelope.Details.TryGetProperty("SuggestedFilename", out var suggProp)
                                ? suggProp.GetString()
                                : "manifest.json";

                            string filterSave = envelope.Details.TryGetProperty("Filter", out var filterSaveProp)
                                ? filterSaveProp.GetString()
                                : "*.*";

                            var fileToSave = SaveFileDialogHelper.ShowSaveFileDialog(suggested, filterSave);

                            response.Success = !string.IsNullOrEmpty(fileToSave);
                            response.Payload = new
                            {
                                Path = fileToSave,
                                FileName = !string.IsNullOrEmpty(fileToSave) ? System.IO.Path.GetFileName(fileToSave) : null
                            };
                            break;

                        case "WriteFile":
                            filePath = envelope.Details.GetProperty("Path").GetString();
                            var data = envelope.Details.GetProperty("Data").GetString();
                            File.WriteAllText(filePath, data, new UTF8Encoding(false));
                            response.Success = true;
                            break;

                        case "IntrospectDatabase":
                            if (!hasDetails)
                                throw new Exception("IntrospectDatabase requires details.");

                            var introspectDetails = envelope.Details.Deserialize<GenerateManifestDetails>();
                            var introspector = new DatabaseIntrospector(
                                introspectDetails.ConnectionString,
                                introspectDetails.DbPrefix, introspectDetails.IncludeSeedData
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
                            break;

                        case "ParseInstallerManifest":
                            {
                                filePath = envelope.Details.GetProperty("filePath").GetString();
                                if (string.IsNullOrWhiteSpace(filePath) || !File.Exists(filePath))
                                {
                                    response.Success = false;
                                    response.Error = "Invalid or missing file path.";
                                    break;
                                }

                                try
                                {
                                    manifestGenerator = new ManifestGenerator();
                                    manifest = manifestGenerator.LoadFromFile(filePath);

                                    response.Success = true;
                                    response.Payload = new
                                    {
                                        manifest = manifest.ToCamelCaseObject(),
                                        defaultConnectionString = "" // fill if you’ve got it
                                    };
                                }
                                catch (Exception ex)
                                {
                                    response.Success = false;
                                    response.Error = $"Failed to parse manifest: {ex.Message}";
                                }
                                break;
                            }

                        case "CreateInstallerFiles":
                            {
                                try
                                {
                                    var raw = envelope.Details.GetRawText();

                                    // Be lenient on casing, accept both camelCase & PascalCase
                                    var opts = new System.Text.Json.JsonSerializerOptions
                                    {
                                        PropertyNameCaseInsensitive = true
                                    };

                                    var req = System.Text.Json.JsonSerializer.Deserialize<WPStallman.GUI.Classes.CreateInstallerDetails>(raw, opts);
                                    if (req == null)
                                    {
                                        response.Success = false;
                                        response.Error = "Could not deserialize CreateInstallerDetails.";
                                        break;
                                    }

                                    // Defensive: ensure Manifest present
                                    if (req.Manifest == null)
                                    {
                                        response.Success = false;
                                        response.Error = "Missing Manifest in request.";
                                        break;
                                    }

                                    // (Optional) quick counts to help debugging
                                    int t = req.Manifest.Tables?.Count ?? 0;
                                    int v = req.Manifest.Views?.Count ?? 0;
                                    int p = req.Manifest.StoredProcedures?.Count ?? 0;
                                    int g = req.Manifest.Triggers?.Count ?? 0;

                                    // if we have an override, pass it into the manifest
                                    if (!string.IsNullOrWhiteSpace(req.InstallerClassNameOverride))
                                    {
                                        req.Manifest.InstallerClass = req.InstallerClassNameOverride; ;
                                    }

                                    var files = installerClassGenerator.CreatePreviewFiles(req.Manifest);

                                    response.Success = true;
                                    response.Payload = new
                                    {
                                        counts = new { tables = t, views = v, procedures = p, triggers = g },
                                        files = files  // list of file output class
                                    };
                                }
                                catch (Exception ex)
                                {
                                    response.Success = false;
                                    response.Error = $"CreateInstallerFiles failed: {ex.Message}";
                                }
                                break;
                            }
                        case "CheckIfFileAlreadyExists":
                            {
                                if (!hasDetails)
                                {
                                    response.Success = false;
                                    response.Error = "CheckIfFileAlreadyExists requires details.";
                                    break;
                                }

                                // Accept several common field names
                                string path = null;
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

                                // Basic validation
                                if (Path.GetInvalidPathChars().Any(path.Contains))
                                {
                                    response.Success = false;
                                    response.Error = "Invalid characters in provided path.";
                                    response.Payload = new { Path = path };
                                    break;
                                }

                                // Optional normalization (env vars, etc.)
                                var expanded = Environment.ExpandEnvironmentVariables(path);
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
                                break;
                            }

                        case "CreateInstallerZip":
                            {
                                if (!hasDetails)
                                    throw new Exception("CreateInstallerZip requires command envelope details");

                                // Destination
                                var destinationZipFilePath = envelope.Details.TryGetProperty("DestinationZipFilePath", out var destEl)
                                    && destEl.ValueKind == JsonValueKind.String ? destEl.GetString() : null;

                                if (string.IsNullOrWhiteSpace(destinationZipFilePath))
                                    throw new Exception("CreateInstallerZip requires DestinationZipFilePath");
                                if (Path.GetInvalidPathChars().Any(destinationZipFilePath.Contains))
                                    throw new Exception("Invalid characters in DestinationZipFilePath");
                                if (!string.Equals(Path.GetExtension(destinationZipFilePath), ".zip", StringComparison.OrdinalIgnoreCase))
                                    throw new Exception("DestinationZipFilePath must end with .zip");

                                var directory = Path.GetDirectoryName(destinationZipFilePath);
                                if (!string.IsNullOrEmpty(directory) && !Directory.Exists(directory))
                                    Directory.CreateDirectory(directory);

                                // Require preview files
                                if (!envelope.Details.TryGetProperty("PreviewFiles", out var filesEl)
                                    || filesEl.ValueKind != JsonValueKind.Array
                                    || filesEl.GetArrayLength() == 0)
                                {
                                    response.Success = false;
                                    response.Error = "No preview files to zip. Generate a preview first.";
                                    break;
                                }

                                // Overwrite flag
                                var allowOverwrite = envelope.Details.TryGetProperty("AllowOverwrite", out var ao)
                                                     && ao.ValueKind == JsonValueKind.True;

                                // If file exists and overwrite not allowed, stop so UI can confirm
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

                                // Open stream with FileMode.Create: creates new or truncates existing (safe overwrite)
                                var utf8NoBom = new UTF8Encoding(false);
                                using (var fs = new FileStream(destinationZipFilePath, FileMode.Create, FileAccess.ReadWrite, FileShare.None))
                                using (var archive = new ZipArchive(fs, ZipArchiveMode.Create, leaveOpen: false))
                                {
                                    foreach (var fileEl in filesEl.EnumerateArray())
                                    {
                                        if (fileEl.ValueKind != JsonValueKind.Object) continue;

                                        var name = fileEl.TryGetProperty("Name", out var n) && n.ValueKind == JsonValueKind.String ? n.GetString() : null;
                                        var content = fileEl.TryGetProperty("Content", out var c) && c.ValueKind == JsonValueKind.String ? c.GetString() : "";

                                        if (string.IsNullOrWhiteSpace(name)) continue;

                                        var entry = archive.CreateEntry(name);
                                        using var entryStream = entry.Open();
                                        using var writer = new StreamWriter(entryStream, utf8NoBom);
                                        writer.Write(content ?? "");
                                    }
                                }

                                response.Success = true;
                                response.Payload = $"Zip file saved to {destinationZipFilePath}";
                                break;
                            }


                        case "OpenUrl":
                            {
                                string url = envelope.Details.TryGetProperty("url", out var urlEl) ? urlEl.GetString() : null;
                                if (!string.IsNullOrWhiteSpace(url))
                                    OpenInDefaultBrowser(url);

                                response.Success = true;
                                break;
                            }
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
                                break;
                            }

                        case "ReadContentText":
                            {
                                if (!hasDetails)
                                {
                                    response.Success = false;
                                    response.Error = "ReadContentText requires details.";
                                    break;
                                }

                                // Expect a relative path under wwwroot (e.g., "LICENSE.txt" or "docs/terms.txt")
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

                                // Resolve path under content root and block traversal
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

                                // Read as UTF-8 (no BOM)
                                var text = File.ReadAllText(fullPath, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
                                response.Success = true;
                                response.Payload = new { Text = text, Path = normalizedRel };
                                break;
                            }

                        default:
                            response.Success = false;
                            response.Error = $"Unknown command: {envelope.Command}";
                            break;
                    }
                }
                catch (Exception ex)
                {
                    response.Success = false;
                    response.Error = ex.ToString();
                }
                finally
                {
                    if (!string.IsNullOrEmpty(requestId))
                        response.RequestId = requestId;
                }

                var responseJson = JsonSerializer.Serialize(response);
                win.SendWebMessage(responseJson);
            });

            window.WaitForClose();
        }

        static void OpenInDefaultBrowser(string url)
        {
            if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) return;
            if (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps) return;

            try
            {
                // .NET on Windows/macOS/Linux: Use the OS shell to open with the default handler
                var psi = new ProcessStartInfo
                {
                    FileName = url,
                    UseShellExecute = true
                };
                Process.Start(psi);
            }
            catch
            {
                // Conservative cross-platform fallbacks
                if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
                {
                    Process.Start("xdg-open", url);
                }
                else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
                {
                    Process.Start("open", url);
                }
                else
                {
                    throw;
                }
            }
        }
    }
}
