using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

namespace WPStallman.Launcher;

internal static class Program
{
    // glibc version via libc
    [DllImport("c")]
    private static extern IntPtr gnu_get_libc_version();

    private static Version ParseGlibc()
    {
        try
        {
            var ptr = gnu_get_libc_version();
            var s = Marshal.PtrToStringAnsi(ptr) ?? "0.0";
            // glibc reports like "2.39"
            if (Version.TryParse(s, out var v)) return v;
            // fallback: strip any suffix
            var parts = s.Split('-', '+')[0];
            return Version.TryParse(parts, out v) ? v : new Version(0, 0);
        }
        catch
        {
            return new Version(0, 0);
        }
    }

    private static string Here => AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);

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

        // forward CLI args
        foreach (var a in args) psi.ArgumentList.Add(a);

        // help native resolver find pre-copied libs if present
        var libDir = Path.GetDirectoryName(exe)!;
        var existingLd = Environment.GetEnvironmentVariable("LD_LIBRARY_PATH");
        psi.Environment["LD_LIBRARY_PATH"] = string.IsNullOrEmpty(existingLd) ? libDir : $"{libDir}:{existingLd}";

        // keep bundle extraction stable when running single-file .NET exe
        var cache = Environment.GetEnvironmentVariable("XDG_CACHE_HOME");
        var bundle = string.IsNullOrEmpty(cache)
            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".cache", "WPStallman", "dotnet_bundle")
            : Path.Combine(cache!, "WPStallman", "dotnet_bundle");
        psi.Environment["DOTNET_BUNDLE_EXTRACT_BASE_DIR"] = bundle;

        using var p = Process.Start(psi)!;
        p.WaitForExit();
        return p.ExitCode;
    }

    private static int Main(string[] args)
    {
        try
        {
            // Layout inside AppImage/deb:
            //   usr/lib/com.wpstallman.app/
            //     WPStallman.Launcher    <-- this process
            //     variants/
            //       glibc2.39/WPStallman.GUI
            //       glibc2.35/WPStallman.GUI
            var baseDir = Here;
            var variantsDir = Path.Combine(baseDir, "variants");

            var glibc = ParseGlibc();
            // Floors you chose
            var floorModern = new Version(2, 39);
            var floorLegacy = new Version(2, 35);

            // allow override (useful for debugging)
            var force = Environment.GetEnvironmentVariable("WPSTALLMAN_FORCE_VARIANT"); // "glibc2.39" | "glibc2.35"
            string[] candidateRel =
                force == "glibc2.39" ? new[] { "glibc2.39" } :
                force == "glibc2.35" ? new[] { "glibc2.35" } :
                glibc >= floorModern   ? new[] { "glibc2.39", "glibc2.35" } :
                glibc >= floorLegacy   ? new[] { "glibc2.35", "glibc2.39" } :
                                         new[] { "glibc2.35" }; // best shot

            foreach (var rel in candidateRel)
            {
                var exe = Path.Combine(variantsDir, rel, "WPStallman.GUI");
                if (File.Exists(exe))
                {
                    Console.WriteLine($"[launcher] glibc={glibc}; launching variant={rel}");
                    return Exec(exe, Path.GetDirectoryName(exe), args);
                }
            }

            Console.Error.WriteLine($"WPStallman Launcher error: no GUI executable found under {variantsDir} (glibc={glibc}).");
            return 127;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"WPStallman – launcher error: {ex}");
            return 1;
        }
    }
}
