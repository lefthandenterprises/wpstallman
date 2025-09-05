using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Collections.Generic;

using Photino.NET;

using WPStallman.Core.Models;
using WPStallman.Core.Services;
using WPStallman.Core.Utilities;

using WPStallman.GUI.Classes;

namespace WPStallman.GUI
{
    internal static class Program
    {
        // ---------- Optional console toggler (pass --console to see logs on Windows) ----------
        private static class ConsoleToggle
        {
            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern bool AllocConsole();

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern IntPtr GetConsoleWindow();

            /// <summary>
            /// If "--console" is present on the command line, attach a console window (Windows only).
            /// </summary>
            public static void AttachIfRequested(string[] args)
            {
                if (!OperatingSystem.IsWindows()) return;
                if (!args.Any(a => a.Equals("--console", StringComparison.OrdinalIgnoreCase))) return;
                if (GetConsoleWindow() == IntPtr.Zero) AllocConsole();
            }
        }


        // ---------- Minimal startup diagnostics (file log + Windows error box on crash) ----------
        private static class StartupDiag
        {
            [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
            private static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);

            public static string LogDir
            {
                get
                {
                    try
                    {
                        if (OperatingSystem.IsWindows())
                            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WPStallman", "logs");

                        var baseDir = Environment.GetEnvironmentVariable("XDG_STATE_HOME");
                        if (string.IsNullOrWhiteSpace(baseDir))
                            baseDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WPStallman");

                        return Path.Combine(baseDir, "logs");
                    }
                    catch
                    {
                        return Path.Combine(AppContext.BaseDirectory, "logs");
                    }
                }
            }

            public static string Log(string message)
            {
                Directory.CreateDirectory(LogDir);
                var path = Path.Combine(LogDir, $"app-{DateTime.Now:yyyyMMdd-HHmmss}.log");
                File.AppendAllText(path, $"[{DateTime.Now:O}] {message}{Environment.NewLine}");
                return path;
            }

            /// <summary>
            /// Show a fatal error message. On Windows, pops a MessageBox; elsewhere writes to stderr.
            /// </summary>
            public static void ShowError(string title, string body)
            {
                try
                {
                    if (OperatingSystem.IsWindows())
                        MessageBoxW(IntPtr.Zero, body, title, 0x00000010 /* MB_ICONERROR */);
                    else
                        Console.Error.WriteLine($"{title}: {body}");
                }
                catch
                {
                    // swallow
                }
            }
        }

        // ---------- Entry point ----------
#if WINDOWS
        [STAThread]
#endif
        private static void Main(string[] args)
        {
            ConsoleToggle.AttachIfRequested(args);

            try
            {
                StartupDiag.Log("Starting WPStallman.GUI…");
                StartupDiag.Log($"BaseDirectory={AppContext.BaseDirectory}");
                StartupDiag.Log($"Args={string.Join(' ', args)}");

                var baseDir = AppContext.BaseDirectory;
                var indexRel = Path.Combine("wwwroot", "index.html");
                var indexAbs = Path.Combine(baseDir, indexRel);
                var indexToLoad = File.Exists(indexAbs) ? indexAbs : indexRel;

                StartupDiag.Log($"Index exists? {File.Exists(indexAbs)} @ {indexToLoad}");

                var window = new PhotinoWindow()
                    .SetTitle("W. P. Stallman")
                    .SetSize(1200, 900)
                    .SetMinSize(800, 600)
                    .Load(indexToLoad);

                // --- Window icon (keeps taskbar/dock looking right) ---
                try
                {
                    string iconPath;
                    if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                    {
                        // Ship a Windows .ico at wwwroot/img/WPS.ico
                        iconPath = Path.Combine(baseDir, "wwwroot", "img", "WPS.ico");
                    }
                    else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
                    {
                        // Prefer ICNS if available; fall back to PNG
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
                        StartupDiag.Log($"Window icon set: {iconPath}");
                    }
                    else
                    {
                        StartupDiag.Log($"Icon file not found (skipping SetIconFile): {iconPath}");
                    }
                }
                catch (Exception ex)
                {
                    StartupDiag.Log($"SetIconFile error: {ex}");
                }
                // ------------------------------------------------------

                // Web message bridge (unchanged, apart from a few null-safety guards on inputs)
                window.RegisterWebMessageReceivedHandler((sender, message) =>
                {
                    var win = sender as PhotinoWindow;
                    var response = new CommandResponse();
                    string? requestId = null;

                    try
                    {
                        using (var jsonDoc = JsonDocument.Parse(message))
                        {
                            if (jsonDoc.RootElement.TryGetProperty("RequestId", out var ridProp)
                                && ridProp.ValueKind == JsonValueKind.String)
                            {
                                requestId = ridProp.GetString();
                            }
                        }

                        var jsonOpts = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
                        var envelope = JsonSerializer.Deserialize<CommandEnvelope>(message, jsonOpts)
                                       ?? throw new Exception("Command envelope was missing for request.");

                        bool hasDetails = envelope.Details.ValueKind is not JsonValueKind.Undefined and not JsonValueKind.Null;

                        var manifestGenerator = new ManifestGenerator();
                        var installerClassGenerator = new InstallerClassGenerator();

                        switch (envelope.Command)
                        {
                            case "MaximizeWindow":
                                if (win != null)
                                {
                                    win.SetMaximized(true);
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
                                {
                                    string filter = envelope.Details.TryGetProperty("Filter", out var filterProp)
                                        ? (filterProp.GetString() ?? "*.*")
                                        : "*.*";

                                    var fileToOpen = OpenFileDialogHelper.ShowOpenFileDialog("Open Manifest", filter);

                                    response.Success = !string.IsNullOrEmpty(fileToOpen);
                                    response.Payload = new
                                    {
                                        FileToOpen = fileToOpen,
                                        FileName = !string.IsNullOrEmpty(fileToOpen) ? Path.GetFileName(fileToOpen) : null
                                    };
                                }
                                break;

                            case "ShowSaveDialog":
                                {
                                    string suggested = envelope.Details.TryGetProperty("SuggestedFilename", out var suggProp)
                                        ? (suggProp.GetString() ?? "manifest.json")
                                        : "manifest.json";

                                    string filterSave = envelope.Details.TryGetProperty("Filter", out var filterSaveProp)
                                        ? (filterSaveProp.GetString() ?? "*.*")
                                        : "*.*";

                                    var fileToSave = SaveFileDialogHelper.ShowSaveFileDialog(suggested, filterSave);

                                    response.Success = !string.IsNullOrEmpty(fileToSave);
                                    response.Payload = new
                                    {
                                        Path = fileToSave,
                                        FileName = !string.IsNullOrEmpty(fileToSave) ? Path.GetFileName(fileToSave) : null
                                    };
                                }
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
                                }
                                break;

                            case "OpenUrl":
                                {
                                    string? url = envelope.Details.TryGetProperty("url", out var urlEl) ? urlEl.GetString() : null;
                                    if (!string.IsNullOrWhiteSpace(url))
                                        OpenInDefaultBrowser(url);

                                    response.Success = true;
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
                    win?.SendWebMessage(responseJson);
                });

                StartupDiag.Log("GUI initialized OK; entering message loop.");
                window.WaitForClose();
            }
            catch (Exception ex)
            {
                var path = StartupDiag.Log("FATAL: " + ex);
                StartupDiag.ShowError("WPStallman – startup error",
                    $"An error occurred starting the app.\n\nDetails were written to:\n{path}");
                Environment.ExitCode = 1;
            }
        }

        private static void OpenInDefaultBrowser(string url)
        {
            if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) return;
            if (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps) return;

            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = url,
                    UseShellExecute = true
                };
                Process.Start(psi);
            }
            catch
            {
                if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
                    Process.Start("xdg-open", url);
                else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
                    Process.Start("open", url);
                else
                    throw;
            }
        }
    }
}
