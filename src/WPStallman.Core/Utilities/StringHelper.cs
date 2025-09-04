using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

namespace WPStallman.Core.Utilities;

public static class StringHelper
{

    /// <summary>
    /// Unwraps MySQL "versioned comments" like: /*!50003 CREATE*/ or /*!50003 TRIGGER ... */
    /// Keeps the inner content and drops the comment markers.
    /// </summary>
    private static string UnwrapMySqlVersionedComments(string sql)
    {
        if (string.IsNullOrWhiteSpace(sql)) return sql;
        // Replace ANY /*!##### ... */ with its inner content
        return Regex.Replace(sql, @"(?is)/\*!\d{5}\s*(.*?)\s*\*/", "$1");
    }

    /// <summary>
    /// Removes MySQL DEFINER clauses (both inline and versioned comment forms) and tidies spacing.
    /// Safe for PROCEDURE/FUNCTION/TRIGGER/EVENT/VIEW strings.
    /// </summary>
    public static string RemoveMySqlDefinerClauses(string sql)
    {
        if (string.IsNullOrWhiteSpace(sql)) return sql;
        var cleaned = sql;

        // First unwrap versioned comments so we see plain tokens
        cleaned = UnwrapMySqlVersionedComments(cleaned);

        // Strip inline definers: DEFINER=`user`@`host`
        cleaned = Regex.Replace(
            cleaned,
            @"(?is)\bDEFINER\s*=\s*`[^`]+`\s*@\s*`[^`]+`\s*",
            string.Empty,
            RegexOptions.Compiled
        );

        // Tidy multi-space gaps
        cleaned = Regex.Replace(cleaned, @"[ \t]{2,}", " ").Trim();
        return cleaned;
    }

    /// <summary>
    /// Convenience: sanitize any routine (proc/func/trigger/event) definition.
    /// </summary>
    public static string SanitizeMySqlRoutineDefinition(string sql)
    {
        if (string.IsNullOrWhiteSpace(sql)) return sql;
        var s = RemoveMySqlDefinerClauses(sql);
        // Normalize "CREATE" if it was in a versioned comment like /*!50003 CREATE*/
        s = Regex.Replace(s, @"(?i)\bCREATE\s+(?=\s*(PROCEDURE|FUNCTION|TRIGGER|EVENT)\b)", "CREATE ");
        // Optional: drop stray DELIMITER lines, if they appear in dumps
        s = Regex.Replace(s, @"(?im)^\s*DELIMITER\s+.+\s*$", string.Empty);
        return s.Trim();
    }

    /// <summary>
    /// View-specific: remove ALGORITHM/DEFINER/SQL SECURITY while preserving "OR REPLACE".
    /// (Still uses RemoveMySqlDefinerClauses under the hood.)
    /// </summary>
    public static string SanitizeMySqlViewDefinition(string sql)
    {
        if (string.IsNullOrWhiteSpace(sql)) return sql;
        var cleaned = RemoveMySqlDefinerClauses(sql);

        cleaned = Regex.Replace(
            cleaned,
            @"(?is)\bCREATE\s+((?:OR\s+REPLACE\s+)?)(?:(?:ALGORITHM\s*=\s*\w+)\s+)?(?:(?:DEFINER\s*=\s*`[^`]+`\s*@\s*`[^`]+`)\s+)?(?:(?:SQL\s+SECURITY\s+(?:DEFINER|INVOKER))\s+)?(VIEW\b)",
            "CREATE $1$2",
            RegexOptions.Compiled
        );

        cleaned = Regex.Replace(cleaned, @"[ \t]{2,}", " ").Trim();
        return cleaned;
    }

    public static string ConvertClassNameToKebabCase(string className)
    {
        if (string.IsNullOrEmpty(className))
            return className;

        var result = new StringBuilder();
        for (int i = 0; i < className.Length; i++)
        {
            var currentChar = className[i];
            if (char.IsUpper(currentChar))
            {
                if (i > 0) result.Append('-');
                result.Append(char.ToLower(currentChar));
            }
            else
            {
                result.Append(currentChar);
            }
        }

        result = result.Replace("_", "");

        return result.ToString();
    }

    public static string EscapePhpString(string sql)
    {
        return sql.Replace("\"", "\\\"").Replace("\r", "").Replace("\n", " ");
    }

    public static string InjectPrefix(string sql, string defaultPrefix)
    {
        if (string.IsNullOrEmpty(sql)) return sql;

        // Replace token form {wp_} with PHP interpolation {$this->prefix}
        sql = System.Text.RegularExpressions.Regex.Replace(
            sql, @"\{wp_\}", "{$this->prefix}", System.Text.RegularExpressions.RegexOptions.IgnoreCase);

        // Also replace any raw defaultPrefix literals, if present
        if (!string.IsNullOrEmpty(defaultPrefix))
            sql = sql.Replace(defaultPrefix, "{$this->prefix}");

        return sql;
    }

    public static string NormalizeCurrentTimestampDefaults(string sql)
    {
        if (string.IsNullOrEmpty(sql)) return sql;

        // DEFAULT 'current_timestamp()'  -> DEFAULT CURRENT_TIMESTAMP
        sql = System.Text.RegularExpressions.Regex.Replace(
            sql, @"DEFAULT\s*'?\s*current_timestamp\s*\(\s*\)\s*'?",
            "DEFAULT CURRENT_TIMESTAMP",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);

        // DEFAULT 'current_timestamp'    -> DEFAULT CURRENT_TIMESTAMP
        sql = System.Text.RegularExpressions.Regex.Replace(
            sql, @"DEFAULT\s*'?\s*current_timestamp\s*'?",
            "DEFAULT CURRENT_TIMESTAMP",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);

        return sql;
    }


    public static bool TryCopyText(string text)
    {
        try
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                // Windows: cmd /c clip (expects UTF-16LE)
                var psi = new ProcessStartInfo
                {
                    FileName = "cmd.exe",
                    Arguments = "/c clip",
                };
                return WriteToProcessStdin(psi, text, Encoding.Unicode);
            }
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            {
                // macOS: pbcopy (UTF-8)
                var psi = new ProcessStartInfo
                {
                    FileName = "pbcopy",
                };
                return WriteToProcessStdin(psi, text, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            }
            else
            {
                // Linux: prefer Wayland wl-copy, else xclip, else xsel
                foreach (var tool in new[] { "wl-copy", "xclip", "xsel" })
                {
                    if (!IsCommandAvailable(tool)) continue;

                    ProcessStartInfo psi = tool switch
                    {
                        "wl-copy" => new ProcessStartInfo { FileName = "wl-copy" },
                        "xclip" => new ProcessStartInfo { FileName = "xclip", Arguments = "-selection clipboard" },
                        _ => new ProcessStartInfo { FileName = "xsel", Arguments = "--clipboard --input" }
                    };

                    if (WriteToProcessStdin(psi, text, new UTF8Encoding(false)))
                        return true;
                }
                return false;
            }
        }
        catch (Exception exc)
        {
            Console.WriteLine("TryCopyText failed - error was:");
            Console.WriteLine(exc);
            return false;
        }
    }

    /// <summary>
    /// Launches a process and writes the given text to its STDIN using the specified encoding.
    /// Ensures we close STDIN exactly once (via StreamWriter.Dispose), waits up to 3s, and kills on timeout.
    /// </summary>
    private static bool WriteToProcessStdin(ProcessStartInfo psi, string text, Encoding encoding)
    {
        psi.UseShellExecute = false;
        psi.RedirectStandardInput = true;
        psi.RedirectStandardError = true;   // helpful for debugging; not read to avoid deadlocks
        psi.CreateNoWindow = true;

        using var p = Process.Start(psi);
        if (p == null) return false;

        // Write and close stdin by disposing the writer (no separate p.StandardInput.Close()).
        using (var sw = new StreamWriter(p.StandardInput.BaseStream, encoding, bufferSize: 8192, leaveOpen: false))
        {
            sw.Write(text);
            sw.Flush();
        }

        // Wait up to 3s; if it hangs (rare), kill it.
        if (!p.WaitForExit(3000))
        {
            try { p.Kill(entireProcessTree: true); } catch { /* ignore */ }
            return false;
        }

        return p.ExitCode == 0;
    }


    public static bool IsCommandAvailable(string name)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "which",
                Arguments = name,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using var p = Process.Start(psi);
            p!.WaitForExit(1000);
            var output = p.StandardOutput.ReadToEnd();
            return p.ExitCode == 0 && !string.IsNullOrWhiteSpace(output);
        }
        catch (Exception exc)
        {
            Console.WriteLine("IsCommandAvailable failed - name was:");
            Console.WriteLine(name);
            Console.WriteLine("Error was:");
            Console.WriteLine(exc);
            return false;
        }
    }

}
