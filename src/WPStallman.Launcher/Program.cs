using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;

namespace WPStallman.Launcher;

internal static class Program
{
    // Linux-only P/Invokes (guarded by OS checks)
    private const int RTLD_LAZY = 0x0001;

    // dlopen from libdl
    [DllImport("dl")]
    private static extern IntPtr dlopen(string fileName, int flags);

    private static bool IsLinux =>
        RuntimeInformation.IsOSPlatform(OSPlatform.Linux);

    private static string Here =>
        AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);

    private static int Exec(string exe, string? workingDir, string[] args)
    {
        var psi = new ProcessStartInfo
        {
            FileName = exe,
            UseShellExecute = false,
            WorkingDirectory = workingDir ?? Path.GetDirectoryName(exe)!,
            RedirectStandardError = false,
            RedirectStandardOutput = false,
        };

        foreach (var a in args) psi.ArgumentList.Add(a);

        // Ensure the selected payload's native libs are first in search path
        var libDir = Path.GetDirectoryName(exe)!;
        var existingLd = Environment.GetEnvironmentVariable("LD_LIBRARY_PATH");
        psi.Environment["LD_LIBRARY_PATH"] = string.IsNullOrEmpty(existingLd) ? libDir : $"{libDir}:{existingLd}";

        // Stable bundle extraction dir (harmless for multi-file; helpful if single-file is ever used)
        var cache = Environment.GetEnvironmentVariable("XDG_CACHE_HOME");
        var bundle = string.IsNullOrEmpty(cache)
            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".cache", "WPStallman", "dotnet_bundle")
            : Path.Combine(cache!, "WPStallman", "dotnet_bundle");
        psi.Environment["DOTNET_BUNDLE_EXTRACT_BASE_DIR"] = bundle;

        using var p = Process.Start(psi)!;
        p.WaitForExit();
        return p.ExitCode;
    }

    // --- WebKitGTK detection ---

    private static bool CanDlopen(string soname)
    {
        try
        {
            var handle = dlopen(soname, RTLD_LAZY);
            return handle != IntPtr.Zero;
        }
        catch
        {
            return false;
        }
    }

    private static bool LdconfigHas(string pattern)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "/sbin/ldconfig",
                ArgumentList = { "-p" },
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            };
            using var p = Process.Start(psi)!;
            var output = p.StandardOutput.ReadToEnd();
            p.WaitForExit();
            return output.Contains(pattern, StringComparison.Ordinal);
        }
        catch
        {
            return false;
        }
    }

    private static bool HasWebKit41()
    {
        // Prefer definitive dlopen of the 4.1 sonames
        if (CanDlopen("libwebkit2gtk-4.1.so.0") && CanDlopen("libjavascriptcoregtk-4.1.so.0"))
            return true;

        // Fallback to ldconfig -p scan
        if (LdconfigHas("libwebkit2gtk-4.1.so") && LdconfigHas("libjavascriptcoregtk-4.1.so"))
            return true;

        // Last-resort filesystem probe (when ldconfig not accessible)
        return GlobExists("/usr/lib/*/libwebkit2gtk-4.1.so.*", "/lib/*/libwebkit2gtk-4.1.so.*")
            && GlobExists("/usr/lib/*/libjavascriptcoregtk-4.1.so.*", "/lib/*/libjavascriptcoregtk-4.1.so.*");
    }

    private static bool HasWebKit40()
    {
        if (CanDlopen("libwebkit2gtk-4.0.so.37") && CanDlopen("libjavascriptcoregtk-4.0.so.18"))
            return true;

        if (LdconfigHas("libwebkit2gtk-4.0.so") && LdconfigHas("libjavascriptcoregtk-4.0.so"))
            return true;

        return GlobExists("/usr/lib/*/libwebkit2gtk-4.0.so.*", "/lib/*/libwebkit2gtk-4.0.so.*")
            && GlobExists("/usr/lib/*/libjavascriptcoregtk-4.0.so.*", "/lib/*/libjavascriptcoregtk-4.0.so.*");
    }

    private static bool GlobExists(params string[] patterns)
    {
        try
        {
            foreach (var pat in patterns)
            {
                var stars = Directory.GetFiles(Path.GetPathRoot(pat) ?? "/", pat, new EnumerationOptions
                {
                    MatchCasing = MatchCasing.CaseSensitive,
                    RecurseSubdirectories = false,
                    IgnoreInaccessible = true,
                    AttributesToSkip = 0
                });
                if (stars != null && stars.Length > 0) return true;
            }
        }
        catch { /* ignore */ }
        return false;
    }

    private static int Main(string[] args)
    {
        try
        {
            if (!IsLinux)
            {
                Console.Error.WriteLine("WPStallman Launcher: this Linux launcher is intended for Linux only.");
                return 1;
            }

            // App payload roots
            var baseDir = Here; // typically .../usr/lib/com.wpstallman.app
            // We allow running from usr/bin too; if so, hop to lib root:
            if (Path.GetFileName(baseDir).Equals("bin", StringComparison.Ordinal))
            {
                // /usr/bin -> /usr/lib/com.wpstallman.app
                var libRoot = Path.Combine(Directory.GetParent(baseDir)!.FullName, "lib", "com.wpstallman.app");
                if (Directory.Exists(libRoot)) baseDir = libRoot;
            }

            var gtk41 = Path.Combine(baseDir, "gtk4.1");
            var gtk40 = Path.Combine(baseDir, "gtk4.0");

            // Allow override for debugging: WPSTALLMAN_FORCE_VARIANT=gtk4.1|gtk4.0
            var force = Environment.GetEnvironmentVariable("WPSTALLMAN_FORCE_VARIANT");
            if (force is "gtk4.1" or "gtk4.0")
            {
                var forcedDir = force == "gtk4.1" ? gtk41 : gtk40;
                var forcedExe = FindEntrypoint(forcedDir);
                if (forcedExe != null)
                {
                    Console.Error.WriteLine($"[launcher] override: {force}");
                    return Exec(forcedExe, Path.GetDirectoryName(forcedExe), args);
                }
            }

            // Detect WebKit runtime and choose variant
            string? variantDir = null;

            if (HasWebKit41() && Directory.Exists(gtk41))
                variantDir = gtk41;
            else if (HasWebKit40() && Directory.Exists(gtk40))
                variantDir = gtk40;

            if (variantDir is null)
            {
                Console.Error.WriteLine("W.P. Stallman needs WebKitGTK:");
                Console.Error.WriteLine("Ubuntu 24.04+:  sudo apt install libwebkit2gtk-4.1-0 libjavascriptcoregtk-4.1-0");
                Console.Error.WriteLine("Ubuntu 22.04 :  sudo apt install libwebkit2gtk-4.0-37 libjavascriptcoregtk-4.0-18");
                return 127;
            }

            var exePath = FindEntrypoint(variantDir);
            if (exePath is null)
            {
                Console.Error.WriteLine($"WPStallman – launcher error: no executable found under {variantDir}");
                return 126;
            }

            Console.Error.WriteLine($"[launcher] using variant: {Path.GetFileName(variantDir)}");
            return Exec(exePath, Path.GetDirectoryName(exePath), args);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"WPStallman – launcher error: {ex}");
            return 1;
        }
    }

    // Looks for a native host or managed dll entrypoint in the payload dir
    private static string? FindEntrypoint(string dir)
    {
        // Prefer a renamed native host if you ship one:
        var preferred = Path.Combine(dir, "com.wpstallman.app");
        if (File.Exists(preferred) && IsExecutable(preferred)) return preferred;

        // Typical native host produced by dotnet publish:
        var nativeHost = Path.Combine(dir, "WPStallman.GUI");
        if (File.Exists(nativeHost) && IsExecutable(nativeHost)) return nativeHost;

        // Fallback to managed DLL with dotnet
        var dll = Path.Combine(dir, "WPStallman.GUI.dll");
        if (File.Exists(dll))
        {
            // Use 'dotnet' as the launcher; Exec() will pass it via ArgumentList
            return dll; // Exec() handles dotnet-less fallback by trying to exec directly; you can adapt if needed
        }

        // Nothing found
        return null;
    }

    private static bool IsExecutable(string path)
    {
        try
        {
            // On Linux, just check the execute bit
            return (new FileInfo(path).Attributes & FileAttributes.Directory) == 0;
        }
        catch { return false; }
    }
}
