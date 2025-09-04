// WPStallman.Core/Services/InstallerClassGenerator.cs
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using WPStallman.Core.Models;
using WPStallman.Core.Utilities;

namespace WPStallman.Core.Services
{
    public class InstallerClassGenerator
    {
        // =========================
        // Public API
        // =========================

        private static Dictionary<string, string> BuildTriggerNameMap(Manifest manifest)
        {
            // Reserve all non-trigger object names (prefix-free, case-insensitive)
            var reserved = new HashSet<string>(System.StringComparer.OrdinalIgnoreCase);
            foreach (var t in manifest.Tables) reserved.Add(t.Name ?? "");
            foreach (var v in manifest.Views) reserved.Add(v.Name ?? "");
            foreach (var sp in manifest.StoredProcedures) reserved.Add(sp.Name ?? "");

            // Ensure triggers are unique vs reserved and vs one another
            var map = new Dictionary<string, string>(System.StringComparer.OrdinalIgnoreCase);
            var used = new HashSet<string>(reserved, System.StringComparer.OrdinalIgnoreCase);

            foreach (var trg in manifest.Triggers)
            {
                var baseName = string.IsNullOrWhiteSpace(trg.Name) ? "trigger" : trg.Name;
                var candidate = baseName;
                int i = 1;
                while (used.Contains(candidate))
                {
                    candidate = baseName + (i == 1 ? "_trg" : $"_trg{i}");
                    i++;
                }
                map[trg.Name] = candidate;
                used.Add(candidate);
            }
            return map;
        }


        public string GenerateInstallerClass(Manifest manifest, string className = "MyPlugin_Installer")
        {
            var sb = new StringBuilder();

            // PHP class header
            sb.AppendLine("<?php");
            sb.AppendLine($"class {className} {{");
            sb.AppendLine("    /** @var wpdb */");
            sb.AppendLine("    private $wpdb;");
            sb.AppendLine("    /** @var string */");
            sb.AppendLine("    private $prefix;");
            sb.AppendLine();
            sb.AppendLine("    public function __construct($wpdb) {");
            sb.AppendLine("        $this->wpdb   = $wpdb;");
            sb.AppendLine("        $this->prefix = $wpdb->get_blog_prefix();");
            sb.AppendLine("    }");
            sb.AppendLine();

            // ================== INSTALL ==================
            sb.AppendLine("    public function install() {");
            sb.AppendLine("        $charset_collate = $this->wpdb->get_charset_collate();");
            sb.AppendLine("        require_once(ABSPATH . 'wp-admin/includes/upgrade.php');");

            // ---------- TABLES ----------
            foreach (var table in manifest.Tables.Where(t => !t.Skip))
            {
                // Build column lines with normalized defaults
                var colLines = new List<string>();
                foreach (var col in table.Columns)
                {
                    var nullable = col.Nullable ? "" : " NOT NULL";
                    var autoInc = col.AutoIncrement ? " AUTO_INCREMENT" : "";

                    string defaultClause = "";
                    if (!string.IsNullOrWhiteSpace(col.Default))
                    {
                        var d = col.Default.Trim();
                        var up = d.ToUpperInvariant();
                        if (up == "CURRENT_TIMESTAMP()" || up == "CURRENT_TIMESTAMP")
                            defaultClause = " DEFAULT CURRENT_TIMESTAMP";
                        else
                            defaultClause = " DEFAULT '" + d.Replace("'", "''") + "'";
                    }

                    colLines.Add("    " + col.Name + " " + col.Type + nullable + autoInc + defaultClause);
                }

                var pkCols = table.Columns.Where(c => c.PrimaryKey).Select(c => c.Name).ToList();
                if (pkCols.Any())
                {
                    colLines.Add("    PRIMARY KEY (" + string.Join(", ", pkCols) + ")");
                }

                sb.AppendLine();
                sb.AppendLine("        // Table: " + table.Name);
                sb.AppendLine("        $sql = <<<SQL");
                sb.AppendLine("CREATE TABLE {$this->prefix}" + table.Name + " (");
                for (int i = 0; i < colLines.Count; i++)
                {
                    var comma = (i < colLines.Count - 1) ? "," : "";
                    sb.AppendLine(colLines[i] + comma);
                }
                sb.AppendLine(") $charset_collate;");
                sb.AppendLine("SQL;");
                // Skip dbDelta for core WP tables
                sb.AppendLine("        if ( $this->is_core_table(\"{$this->prefix}" + table.Name + "\") ) {");
                sb.AppendLine("            // skip core WP table");
                sb.AppendLine("        } else {");
                sb.AppendLine("            dbDelta($sql);");
                sb.AppendLine("        }");
            }

            // ---------- VIEWS ----------
            foreach (var view in manifest.Views)
            {
                var viewSqlSanitized = StringHelper.InjectPrefix(view.DefinitionSanitized, manifest.DefaultPrefix);

                sb.AppendLine();
                sb.AppendLine("        // View: " + view.Name);
                sb.AppendLine("        $this->wpdb->query(\"DROP VIEW IF EXISTS {$this->prefix}" + view.Name + "\");");
                sb.AppendLine("        $this->run_sql(\"" + StringHelper.EscapePhpString(viewSqlSanitized) + "\");");
            }


            // ---------- STORED PROCEDURES ----------
            foreach (var sp in manifest.StoredProcedures)
            {
                sb.AppendLine();
                sb.AppendLine("        // Stored Procedure: " + sp.Name);

                // Start from sanitized definition and inject table tokens first
                var spCreate = StringHelper.InjectPrefix(sp.DefinitionSanitized ?? string.Empty, manifest.DefaultPrefix);

                // Force the CREATE PROCEDURE header to use `{$this->prefix}<name>`
                spCreate = System.Text.RegularExpressions.Regex.Replace(
                    spCreate,
                    @"(?is)\bCREATE\s+PROCEDURE\s+`?([A-Za-z0-9_]+)`?",
                    "CREATE PROCEDURE `{$this->prefix}$1`"
                );

                // DROP should also use the prefixed name (never rely on tokens here)
                sb.AppendLine("        $this->run_sql(\"DROP PROCEDURE IF EXISTS `{$this->prefix}" + sp.Name + "`\");");

                // CREATE (after header rewrite + injected tokens)
                sb.AppendLine("        $this->run_sql(\"" + StringHelper.EscapePhpString(spCreate) + "\");");
            }


            // ---------- TRIGGERS ----------
            var triggerNameMap = BuildTriggerNameMap(manifest);

            foreach (var trigger in manifest.Triggers)
            {
                sb.AppendLine();
                sb.AppendLine("        // Trigger: " + trigger.Name);

                // Final trigger name (unique vs tables/views/procs), then prefix at runtime
                var finalTrigName = triggerNameMap[trigger.Name];
                var triggerNamePrefixed = "`{$" + "this->prefix}" + finalTrigName + "`";

                // DROP must use prefixed trigger name
                sb.AppendLine("        $this->run_sql(\"DROP TRIGGER IF EXISTS " + triggerNamePrefixed + "\");");

                // Parse TIMING/EVENT from TriggerDefinition.Event (e.g., 'AFTER INSERT', 'BEFORE UPDATE', or 'INSERT')
                string timing = "AFTER";
                string ev = "INSERT";
                var evt = (trigger.Event ?? string.Empty).Trim();
                if (!string.IsNullOrEmpty(evt))
                {
                    var parts = evt.Split(new[] { ' ', '\t' }, System.StringSplitOptions.RemoveEmptyEntries);
                    if (parts.Length >= 2) { timing = parts[0].ToUpperInvariant(); ev = parts[1].ToUpperInvariant(); }
                    else if (parts.Length == 1)
                    {
                        var tok = parts[0].ToUpperInvariant();
                        if (tok == "BEFORE" || tok == "AFTER") timing = tok; else ev = tok;
                    }
                }

                // Body text (may be single statement). Ensure wrapped in BEGIN...END.
                var trgText = (trigger.DefinitionSanitized ?? string.Empty).Trim();
                trgText = StringHelper.InjectPrefix(trgText, manifest.DefaultPrefix);
                bool hasBegin = System.Text.RegularExpressions.Regex.IsMatch(trgText, @"(?is)^\s*BEGIN\b");
                string body = hasBegin ? trgText.Trim().TrimEnd(';') : "BEGIN " + trgText.Trim().TrimEnd(';') + " END";

                // ON table (TriggerDefinition.Table is prefix-free)
                string tableName = trigger.Table ?? string.Empty;
                string tableRef = "`{$" + "this->prefix}" + tableName + "`";

                // CREATE with prefixed trigger name and table
                string createStmt = "CREATE TRIGGER " + triggerNamePrefixed + " " + timing + " " + ev + " ON " + tableRef + " FOR EACH ROW " + body;

                sb.AppendLine("        $this->run_sql(\"" + StringHelper.EscapePhpString(createStmt) + "\");");
            }





            sb.AppendLine("    }"); // END install

            // ================== POPULATE ==================
            sb.AppendLine();
            sb.AppendLine("    public function populate() {");
            foreach (var table in manifest.Tables.Where(t => !t.Skip && t.RowLimit > 0 && t.SeedData.Any()))
            {
                sb.AppendLine("        // Seed data for table: " + table.Name);
                foreach (var row in table.SeedData.Take(table.RowLimit))
                {
                    var columns = string.Join(", ", row.Keys);
                    var values = string.Join(", ", row.Values.Select(v => v == null ? "NULL" : "'" + (v.ToString()?.Replace("'", "''") ?? "") + "'"));
                    sb.AppendLine("        $this->wpdb->query(\"INSERT INTO {$this->prefix}" + table.Name + " (" + columns + ") VALUES (" + values + ");\");");
                }
            }
            sb.AppendLine("    }"); // END populate

            // ================== UNINSTALL ==================
            sb.AppendLine();
            sb.AppendLine("    public function uninstall() {");
            // Drop plugin tables (never drop core tables)
            foreach (var table in manifest.Tables.Where(t => !t.Skip))
            {
                sb.AppendLine("        if ( !$this->is_core_table(\"{$this->prefix}" + table.Name + "\") ) {");
                sb.AppendLine("            $this->wpdb->query(\"DROP TABLE IF EXISTS {$this->prefix}" + table.Name + "\");");
                sb.AppendLine("        }");
            }
            // Drop views
            foreach (var view in manifest.Views)
            {
                sb.AppendLine("        $this->wpdb->query(\"DROP VIEW IF EXISTS {$this->prefix}" + view.Name + "\");");
            }

            // Drop routines
            foreach (var sp in manifest.StoredProcedures)
            {
                sb.AppendLine("        $this->run_sql(\"DROP PROCEDURE IF EXISTS `{$this->prefix}" + sp.Name + "`\");");
            }
            foreach (var trigger in manifest.Triggers)
            {
                sb.AppendLine("        $this->run_sql(\"DROP TRIGGER IF EXISTS `{$this->prefix}" + trigger.Name + "`\");");
            }

            sb.AppendLine("    }"); // END uninstall

            // ================== HELPERS ==================
            sb.AppendLine();
            sb.AppendLine("    /** Replace leftover tokens and guard dangerous core-table operations. */");
            sb.AppendLine("    private function apply_prefix($sql) {");
            sb.AppendLine("        $sql = str_replace('{wp_}', $this->prefix, $sql);");
            sb.AppendLine("        $sql = str_replace('{$this->prefix}', $this->prefix, $sql);");
            sb.AppendLine("        return $sql;");
            sb.AppendLine("    }");
            sb.AppendLine();
            sb.AppendLine("    /** Core table list resolved from $wpdb (single-site + multisite). */");
            sb.AppendLine("    private function core_tables() {");
            sb.AppendLine("        $w = $this->wpdb;");
            sb.AppendLine("        // Collect known core tables; filter out nulls and map to lowercase");
            sb.AppendLine("        $list = array_filter(array_map('strtolower', array(");
            sb.AppendLine("            isset($w->users) ? $w->users : null,");
            sb.AppendLine("            isset($w->usermeta) ? $w->usermeta : null,");
            sb.AppendLine("            isset($w->posts) ? $w->posts : null,");
            sb.AppendLine("            isset($w->postmeta) ? $w->postmeta : null,");
            sb.AppendLine("            isset($w->comments) ? $w->comments : null,");
            sb.AppendLine("            isset($w->commentmeta) ? $w->commentmeta : null,");
            sb.AppendLine("            isset($w->terms) ? $w->terms : null,");
            sb.AppendLine("            isset($w->term_taxonomy) ? $w->term_taxonomy : null,");
            sb.AppendLine("            isset($w->term_relationships) ? $w->term_relationships : null,");
            sb.AppendLine("            isset($w->termmeta) ? $w->termmeta : null,");
            sb.AppendLine("            isset($w->links) ? $w->links : null,");
            sb.AppendLine("            isset($w->options) ? $w->options : null,");
            sb.AppendLine("            // Multisite (if present)");
            sb.AppendLine("            isset($w->blogs) ? $w->blogs : null,");
            sb.AppendLine("            isset($w->blog_versions) ? $w->blog_versions : null,");
            sb.AppendLine("            isset($w->registration_log) ? $w->registration_log : null,");
            sb.AppendLine("            isset($w->signups) ? $w->signups : null,");
            sb.AppendLine("            isset($w->site) ? $w->site : null,");
            sb.AppendLine("            isset($w->sitemeta) ? $w->sitemeta : null");
            sb.AppendLine("        )));");
            sb.AppendLine("        return $list;");
            sb.AppendLine("    }");
            sb.AppendLine();
            sb.AppendLine("    private function is_core_table($fullTableName) {");
            sb.AppendLine("        return in_array(strtolower($fullTableName), $this->core_tables(), true);");
            sb.AppendLine("    }");
            sb.AppendLine();
            sb.AppendLine("    private function is_core_table_alter($sql) {");
            sb.AppendLine("        $tables = $this->core_tables();");
            sb.AppendLine("        if (empty($tables)) { return false; }");
            sb.AppendLine("        $quoted = array();");
            sb.AppendLine("        foreach ($tables as $t) { $quoted[] = preg_quote($t, '/'); }");
            sb.AppendLine("        $alts = implode('|', $quoted);");
            sb.AppendLine("        $pattern = '/^\\s*ALTER\\s+TABLE\\s+`?(?:' . $alts . ')`?/i';");
            sb.AppendLine("        return (bool) preg_match($pattern, $sql);");
            sb.AppendLine("    }");
            sb.AppendLine();
            sb.AppendLine("    private function run_sql($sql) {");
            sb.AppendLine("        $sql = $this->apply_prefix($sql);");
            sb.AppendLine("        if ($this->is_core_table_alter($sql)) {");
            sb.AppendLine("            return; // skip dangerous core table alters");
            sb.AppendLine("        }");
            sb.AppendLine("        $this->wpdb->query($sql);");
            sb.AppendLine("    }");

            // End class
            sb.AppendLine();
            sb.AppendLine("}"); // END class
           // sb.AppendLine("?>");

            return sb.ToString();
        }

        public void SaveToFile(Manifest manifest, string outputPath, string className = "MyPlugin_Installer")
        {
            File.WriteAllText(outputPath, GenerateInstallerClass(manifest, className), new UTF8Encoding(false));
        }

        public void SaveInstallerStub(string outputPath, string className = "MyPlugin_Installer", string classFile = "class-my-plugin-installer.php")
        {
            File.WriteAllText(outputPath, CreateInstallerStub(className, classFile), new UTF8Encoding(false));
        }

        public string CreateInstallerStub(string className, string classFile)
        {
            var sb = new StringBuilder();

            sb.AppendLine("<?php");
            sb.AppendLine("// Auto-generated test stub for " + className);
            sb.AppendLine();
            sb.AppendLine("require_once( dirname(__FILE__) . '/wp-load.php' );");
            sb.AppendLine("require_once( dirname(__FILE__) . '/" + classFile + "' );");
            sb.AppendLine();
            sb.AppendLine("global $wpdb;");
            sb.AppendLine("$installer = new " + className + "($wpdb);");
            sb.AppendLine();
            sb.AppendLine("echo \"Running install...\\n\";");
            sb.AppendLine("$installer->install();");
            sb.AppendLine();
            sb.AppendLine("echo \"Populating seed data...\\n\";");
            sb.AppendLine("$installer->populate();");
            sb.AppendLine();
            sb.AppendLine("// echo \"Uninstalling...\\n\";");
            sb.AppendLine("// $installer->uninstall();");
            sb.AppendLine();
            sb.AppendLine("echo \"Done!\\n\";");
           // sb.AppendLine("?>");

            return sb.ToString();
        }

        /// <summary>
        /// Generates the main WP plugin file (with header) that requires the class file and
        /// registers hooks. Activation/Deactivation use closures; Uninstall uses a named function.
        /// </summary>
        public string CreateMainPHPClass(string className)
        {
            var slug = StringHelper.ConvertClassNameToKebabCase(className).Replace("--", "-").Trim('-');
            var classPhpFile = "class-" + slug + ".php";
            var uninstallFunc = slug.Replace('-', '_') + "_uninstall";
            var pluginName = className.Replace('_', ' ');

            var sb = new StringBuilder();
            sb.AppendLine("<?php");
            sb.AppendLine("/*");
            sb.AppendLine("Plugin Name: " + pluginName);
            sb.AppendLine("Description: Database installer generated by W. P. Stallman");
            sb.AppendLine("Version: 0.1.0");
            sb.AppendLine("Requires at least: 6.0");
            sb.AppendLine("Requires PHP: 7.4");
            sb.AppendLine("Author: You");
            sb.AppendLine("License: GPLv2 or later");
            sb.AppendLine("Text Domain: " + slug);
            sb.AppendLine("*/");
            sb.AppendLine();
            sb.AppendLine("if ( ! defined( 'ABSPATH' ) ) exit;");
            sb.AppendLine();
            sb.AppendLine("require_once __DIR__ . '/" + classPhpFile + "';");
            sb.AppendLine();
            // Activation/Deactivation (closures OK)

            sb.AppendLine("register_activation_hook( __FILE__, function() { (new " + className + "($GLOBALS['wpdb']))->install(); (new " + className + "($GLOBALS['wpdb']))->populate(); } );");

            sb.AppendLine("register_deactivation_hook( __FILE__, function() { /* (new " + className + "($GLOBALS['wpdb']))->deactivate(); */ } );");
            sb.AppendLine();
            // Uninstall must be a named callable (persisted)
            sb.AppendLine("register_uninstall_hook( __FILE__, '" + uninstallFunc + "' );");
            sb.AppendLine("function " + uninstallFunc + "() { (new " + className + "($GLOBALS['wpdb']))->uninstall(); }");
            sb.AppendLine();
            return sb.ToString();
        }

        public List<InstallerOutputFile> CreatePreviewFiles(Manifest manifest)
        {
            var output = new List<InstallerOutputFile>();

            // Installer class
            var installer = new InstallerOutputFile
            {
                Name = "class-" + StringHelper.ConvertClassNameToKebabCase(manifest.InstallerClass) + ".php",
                Content = GenerateInstallerClass(manifest, manifest.InstallerClass),
                Type = "InstallerClass"
            };

            // Test stub
            var stub = new InstallerOutputFile
            {
                Name = StringHelper.ConvertClassNameToKebabCase(manifest.InstallerClass) + "-installer.php",
                Content = CreateInstallerStub(manifest.InstallerClass, installer.Name),
                Type = "InstallerStub"
            };

            // Main plugin file
            var main = new InstallerOutputFile
            {
                Name = StringHelper.ConvertClassNameToKebabCase(manifest.InstallerClass) + ".php",
                Content = CreateMainPHPClass(manifest.InstallerClass),
                Type = "MainPlugin"
            };

            // Order: stub, main, class (keeps prior UI expectation)
            output.Add(stub);
            output.Add(main);
            output.Add(installer);

            return output;
        }
    }
}
