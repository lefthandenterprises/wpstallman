using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using Photino.NET;
using WPStallman.Core.Classes;
using WPStallman.Core.Interfaces;
using WPStallman.Core.Services;

using WPStallman.GUI.Classes;

namespace WPStallman.GUI
{
    internal static class Program
    {

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

                    IPhotinoWindowHandler handler = new PhotinoWindowHandler(win);

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

                        var commandProcessor = new GUICommandProcessor(handler, message, requestId);

                        response = commandProcessor.ProcessCommand();

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
        // ---------- Optional console toggler (pass --console to see logs on Windows) ----------
        private static class ConsoleToggle
        {

            /// <summary>
            /// If "--console" is present on the command line, attach a console window (Windows only).
            /// </summary>
            public static void AttachIfRequested(string[] args)
            {
                if (!OperatingSystem.IsWindows()) return;
                if (!args.Any(a => a.Equals("--console", StringComparison.OrdinalIgnoreCase))) return;
                if (GetConsoleWindow() == IntPtr.Zero) AllocConsole();
            }
            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern bool AllocConsole();

            [DllImport("kernel32.dll", SetLastError = true)]
            private static extern IntPtr GetConsoleWindow();
        }

        // ---------- Minimal startup diagnostics (file log + Windows error box on crash) ----------
        private static class StartupDiag
        {

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
            [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
            private static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);
        }
    }
}
