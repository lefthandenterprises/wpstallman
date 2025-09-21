using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

internal static class Program
{
    // === CONFIG ===
    // The *base* filename of your GUI app as it will appear on each OS.
    // Change "WPStallman" if your main executable name differs.
    private const string AppBaseName = "WPStallman.GUI";

    // Optional overrides:
    // 1) CLI:   --target /absolute/path/to/GUI
    // 2) ENV:   WPSTALLMAN_GUI=/absolute/path/to/GUI
    private const string EnvTargetVar = "WPSTALLMAN_GUI";

    // Prefer self-contained exe first, but accept .dll via "dotnet" too.
    private static readonly string[] CandidateRelativePaths =
   {
    ".", // same folder as launcher

    // from .../src/WPStallman.Launcher/bin/Debug/net8.0/
    // go up 4 levels to .../src/
    "../../../../WPStallman.GUI/bin/Debug/net8.0",
    "../../../../WPStallman.GUI/bin/Release/net8.0",
        "../../../../WPStallman.GUI/bin/Debug/net8.0/linux-x64",
    "../../../../WPStallman.GUI/bin/Release/net8.0/linux-x64",

    // also try the project folders (if you run from different base dirs)
        "../../../../WPStallman.GUI",
    "../../../../../WPStallman.GUI/bin/Debug/net8.0",
    "../../../../../WPStallman.GUI/bin/Release/net8.0",
    "../../../../../WPStallman.GUI/bin/Debug/net8.0/linux-x64",
    "../../../../../WPStallman.GUI/bin/Release/net8.0/linux-x64",

    // generic fallbacks
        "..",
    "../..",
    "../../..",
    "../../../../.."
};

    // A cross-platform single-instance token.
    // Use a stable, unique name for your app.
    private const string SingleInstanceName = "WPStallman_SingleInstance_Mutex_v1";

    private static int Main(string[] args)
    {
        try
        {
            using var singleInstance = CreateSingleInstanceGuard(out bool isFirstInstance);
            if (!isFirstInstance)
            {
                // Already running — exit silently with a special code
                return 259; // arbitrary "already running" code
            }

            // Resolve the target executable
            var targetPath = ResolveTargetExecutable();
            if (string.IsNullOrEmpty(targetPath) || !File.Exists(targetPath))
            {
                ShowError("Could not locate the main application executable.\n" +
                          "Checked common locations relative to the launcher.\n\n" +
                          "Tips:\n - Ensure the GUI app is published/built\n - Place the launcher next to the GUI app");
                return 2;
            }

            // Resolve the target and launch
            if (!TryResolveProcessStartInfo(args, out var psi, out var whyNot))
            {
                ShowError("Could not locate the main application executable.\n" +
                          "Checked common locations relative to the launcher.\n\n" +
                          "Tips:\n - Ensure the GUI app is published/built\n - Place the launcher next to the GUI app\n\n" +
                          (string.IsNullOrWhiteSpace(whyNot) ? "" : $"Details:\n{whyNot}"));
                return 2;
            }

            using var proc = Process.Start(psi);
            if (proc == null)
            {
                ShowError("Failed to start the main application process.");
                return 3;
            }

            proc.WaitForExit();
            return proc.ExitCode;

        }
        catch (Exception ex)
        {
            ShowError("Launcher encountered an error:\n" + ex);
            return 1;
        }
    }

    private static bool TryResolveProcessStartInfo(string[] launcherArgs, out ProcessStartInfo psi, out string? reason)
    {
        psi = null!;
        reason = null;

        // 0) Explicit overrides
        // CLI: --target <path>
        string? cliTarget = null;
        for (int i = 0; i < launcherArgs.Length - 1; i++)
        {
            if (string.Equals(launcherArgs[i], "--target", StringComparison.OrdinalIgnoreCase))
            {
                cliTarget = launcherArgs[i + 1];
                break;
            }
        }
        var envTarget = Environment.GetEnvironmentVariable(EnvTargetVar);

        string? target = cliTarget ?? envTarget;
        if (!string.IsNullOrWhiteSpace(target))
        {
            if (File.Exists(target))
                return BuildPsiForTarget(target, launcherArgs, out psi, out reason);

            reason = $"Override specified but not found: {target}";
            return false;
        }

        // 1) Probe for native executable
        var exeName = GetPlatformExeName();
        if (TryFindInCandidates(exeName, out var nativePath))
            return BuildPsiForTarget(nativePath, launcherArgs, out psi, out reason);

        // 2) Linux AppImage fallback
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
        {
            var appImageName = AppBaseName + ".AppImage";
            if (TryFindInCandidates(appImageName, out var appImagePath))
                return BuildPsiForTarget(appImagePath, launcherArgs, out psi, out reason);
        }

        // 3) Framework-dependent: look for DLL and launch via "dotnet"
        var dllName = AppBaseName + ".dll";
        if (TryFindInCandidates(dllName, out var dllPath))
        {
            psi = new ProcessStartInfo
            {
                FileName = "dotnet",
                UseShellExecute = false,
                WorkingDirectory = Path.GetDirectoryName(dllPath)!,
            };
            psi.ArgumentList.Add(dllPath);
            // pass through remaining args but skip our own --target arg if present
            for (int i = 0; i < launcherArgs.Length; i++)
            {
                if (string.Equals(launcherArgs[i], "--target", StringComparison.OrdinalIgnoreCase))
                { i++; continue; } // skip value too
                psi.ArgumentList.Add(launcherArgs[i]);
            }
            // Report glibc info for framework-dependent (managed) launch
            CheckAndReportGlibc(dllPath, true);


            return true;
        }

        reason = $"Probed for '{exeName}', '{dllName}'" +
                 (RuntimeInformation.IsOSPlatform(OSPlatform.Linux) ? $" and '{AppBaseName}.AppImage'" : "") +
                 $" under:\n - {string.Join("\n - ", CandidateRelativePaths)}";
        return false;
    }

    private static bool TryFindInCandidates(string fileName, out string fullPath)
    {
        var baseDir = AppContext.BaseDirectory;
        // Check same directory first
        var sameDir = Path.Combine(baseDir, fileName);
        if (File.Exists(sameDir)) { fullPath = sameDir; return true; }

        foreach (var rel in CandidateRelativePaths)
        {
            var p = Path.GetFullPath(Path.Combine(baseDir, rel, fileName));
            if (File.Exists(p)) { fullPath = p; return true; }
        }

        fullPath = "";
        return false;
    }

    private static bool BuildPsiForTarget(string targetPath, string[] args, out ProcessStartInfo psi, out string? reason)
    {
        psi = new ProcessStartInfo
        {
            FileName = targetPath,
            UseShellExecute = false,
            WorkingDirectory = Path.GetDirectoryName(targetPath)!,
        };

        // forward args (but strip our --target pair if present)
        for (int i = 0; i < args.Length; i++)
        {
            if (string.Equals(args[i], "--target", StringComparison.OrdinalIgnoreCase))
            { i++; continue; } // skip the path value too
            psi.ArgumentList.Add(args[i]);
        }

        reason = null;
        // Report glibc info for native/AppImage launch
        if (!CheckAndReportGlibc(targetPath, isDllLaunch: false, hardFail: false))
        {
            return false; // stop if you set hardFail=true
        }
        return true;

    }


    private static string? ResolveTargetExecutable()
    {
        var launcherDir = AppContext.BaseDirectory;

        // Determine the platform-specific executable name
        var exeName = GetPlatformExeName();

        // 1) Prefer same directory
        var sameDirCandidate = Path.Combine(launcherDir, exeName);
        if (File.Exists(sameDirCandidate))
            return sameDirCandidate;

        // 2) Try common relative locations
        foreach (var rel in CandidateRelativePaths)
        {
            var p = Path.GetFullPath(Path.Combine(launcherDir, rel, exeName));
            Console.WriteLine("Trying to launch:");
            Console.WriteLine(p);

            if (File.Exists(p))
                return p;

            // Also try an AppImage if present (Linux packaging case)
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
            {
                var appImageName = AppBaseName + ".AppImage";
                var appImagePath = Path.GetFullPath(Path.Combine(launcherDir, rel, appImageName));
                if (File.Exists(appImagePath))
                    return appImagePath;
            }
        }

        return null;
    }

    private static string GetPlatformExeName()
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            return AppBaseName + ".exe";

        // On macOS self-contained publish names the file exactly (no extension)
        // On Linux same (unless you use .AppImage which we also probe above)
        return AppBaseName;
    }

    // ---- Single Instance Guard ----
    // Windows: named mutex
    // Unix: lock file + exclusive FileStream
    private static IDisposable CreateSingleInstanceGuard(out bool isFirstInstance)
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            var mutex = new Mutex(initiallyOwned: false, name: $"Global\\{SingleInstanceName}", out bool _);
            try
            {
                isFirstInstance = mutex.WaitOne(0);
            }
            catch (AbandonedMutexException)
            {
                isFirstInstance = true; // previous instance crashed
            }

            // Copy the out var into a local so the lambda doesn't capture an out parameter
            bool capturedFirstInstance = isFirstInstance;

            return new ActionOnDispose(() =>
            {
                try { if (capturedFirstInstance) mutex.ReleaseMutex(); } catch { /* ignore */ }
                mutex.Dispose();
            });
        }
        else
        {
            var lockPath = Path.Combine(Path.GetTempPath(), SingleInstanceName + ".lock");
            var fs = new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);

            isFirstInstance = fs.Length == 0; // exclusive open implies first instance

            return new ActionOnDispose(() => fs.Dispose());
        }
    }


    private static void ShowError(string message)
    {
        // Try a user-friendly message on Windows; fall back to console elsewhere
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            try
            {
                // Minimal message box without extra refs
                Process.Start(new ProcessStartInfo
                {
                    FileName = "powershell",
                    Arguments = $"-NoProfile -Command \"[System.Windows.MessageBox]::Show('{EscapeForPwsh(message)}','WP Stallman Launcher')\"",
                    UseShellExecute = false,
                    CreateNoWindow = true
                });
                return;
            }
            catch { /* ignore and fall back */ }
        }

        Console.Error.WriteLine(message);
    }

    private static string EscapeForPwsh(string s)
        => s.Replace("'", "''").Replace("\r", "").Replace("\n", "`n");

    private sealed class ActionOnDispose : IDisposable
    {
        private readonly Action _a;
        public ActionOnDispose(Action a) => _a = a;
        public void Dispose() => _a();
    }

    // ===== Linux glibc helpers =====
    [DllImport("libc")]
    private static extern IntPtr gnu_get_libc_version();

    private static string? GetInstalledGlibcVersion()
    {
        try
        {
            var ptr = gnu_get_libc_version();
            var v = Marshal.PtrToStringAnsi(ptr);
            return string.IsNullOrWhiteSpace(v) ? null : v;
        }
        catch
        {
            // Fallback: ldd --version first line usually contains "GLIBC X.Y"
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "ldd",
                    ArgumentList = { "--version" },
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false
                };
                using var p = Process.Start(psi)!;
                var first = p.StandardOutput.ReadLine();
                p.WaitForExit(1000);
                if (!string.IsNullOrWhiteSpace(first))
                {
                    // Try to extract X.Y
                    var idx = first.IndexOf("GLIBC", StringComparison.OrdinalIgnoreCase);
                    if (idx >= 0)
                    {
                        var tail = first[(idx + 5)..]; // after "GLIBC"
                        var m = System.Text.RegularExpressions.Regex.Match(tail, @"\s*([0-9]+\.[0-9]+)");
                        if (m.Success) return m.Groups[1].Value;
                    }
                }
            }
            catch { /* ignore */ }
            return null;
        }
    }

    // Tries to read the highest GLIBC_* symbol referenced by a native target.
    // Works for ELF executables/AppImages. Returns null if unknown.
    // Note: for framework-dependent .dll, there is no direct GLIBC requirement in the managed file.
    private static string? GetBinaryGlibcFloor(string targetPath)
    {
        try
        {
            // Prefer strings+grep; many systems have them even when binutils isn't installed.
            var sh = "/bin/bash";
            if (!File.Exists(sh)) sh = "/bin/sh";

            string cmd = $"strings -a \"{targetPath.Replace("\"", "\\\"")}\" 2>/dev/null | " +
                         "grep -oE 'GLIBC_[0-9]+\\.[0-9]+' | sort -V | tail -n1";

            var psi = new ProcessStartInfo
            {
                FileName = sh,
                ArgumentList = { "-lc", cmd },
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            };
            using var p = Process.Start(psi)!;
            var s = p.StandardOutput.ReadToEnd().Trim();
            p.WaitForExit(1500);
            if (!string.IsNullOrWhiteSpace(s)) return s.Replace("GLIBC_", "");

            // Fallback: objdump -T can show versioned symbols if available.
            try
            {
                var psi2 = new ProcessStartInfo
                {
                    FileName = sh,
                    ArgumentList = { "-lc", $"objdump -T \"{targetPath.Replace("\"", "\\\"")}\" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\\.[0-9]+' | sort -V | tail -n1" },
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false
                };
                using var p2 = Process.Start(psi2)!;
                var s2 = p2.StandardOutput.ReadToEnd().Trim();
                p2.WaitForExit(2000);
                if (!string.IsNullOrWhiteSpace(s2)) return s2.Replace("GLIBC_", "");
            }
            catch { /* ignore */ }
        }
        catch { /* ignore */ }

        return null;
    }

    private static int CompareSemver(string a, string b)
    {
        // compares "2.35" vs "2.16" etc.
        static int Parse(string s, int i) => i < s.Length ? int.Parse(s.Split('.')[i]) : 0;
        var a0 = Parse(a, 0); var a1 = Parse(a, 1);
        var b0 = Parse(b, 0); var b1 = Parse(b, 1);
        if (a0 != b0) return a0.CompareTo(b0);
        return a1.CompareTo(b1);
    }

    private static bool CheckAndReportGlibc(string targetPath, bool isDllLaunch, bool hardFail = false)
    {
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Linux)) return true;

        var installed = GetInstalledGlibcVersion() ?? "unknown";
        string required = "n/a (managed .dll)";

        if (!isDllLaunch)
            required = GetBinaryGlibcFloor(targetPath) ?? "unknown";

        Console.WriteLine($"[glibc] installed={installed}; required_by_target={required}");

        if (!isDllLaunch && installed != "unknown" && required != "unknown")
        {
            // installed < required ? warn or fail
            if (CompareSemver(installed, required) < 0)
            {
                var msg = $"This system’s glibc ({installed}) is older than the binary’s floor ({required}).";
                if (hardFail)
                {
                    ShowError(msg + " Aborting launch.");
                    return false;
                }
                Console.Error.WriteLine("[warning] " + msg);
            }
        }
        return true;
    }


    private static void PrintGlibcInfoIfLinux(string targetPath, bool isDllLaunch)
    {
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Linux)) return;

        var installed = GetInstalledGlibcVersion() ?? "unknown";
        string required = "n/a (managed .dll)";

        if (!isDllLaunch)
        {
            // Only try to read a native binary/AppImage
            required = GetBinaryGlibcFloor(targetPath) ?? "unknown";
        }

        Console.WriteLine($"[glibc] installed={installed}; required_by_target={required}");
    }

}
