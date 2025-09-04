using System.CommandLine;
using WPStallman.Core.Services;

// Root command
var rootCommand = new RootCommand("WPStallman - WordPress Packaging Utility (NetCore Rewrite)");

// Parent command: generate
var generateCommand = new Command("generate", "Generate outputs (manifest, installer, etc.)");

// ========== OPTIONS FOR MANIFEST ==========
var connectionOption = new Option<string>(
    name: "--connection",
    description: "Connection string to the MySQL database")
{ IsRequired = true };

var prefixOption = new Option<string>(
    name: "--prefix",
    description: "WordPress table prefix to strip during introspection",
    getDefaultValue: () => "wp_");

var manifestOutputOption = new Option<string>(
    name: "--output",
    description: "Output path for the manifest JSON file",
    getDefaultValue: () => "manifest.json");

var includeDataOption = new Option<bool>(
    name: "--include-data",
    description: "Include seed data for tables in the manifest",
    getDefaultValue: () => false);

// ---------- MANIFEST COMMAND ----------
var manifestCommand = new Command("manifest", "Generate a JSON manifest of the database schema");
manifestCommand.AddOption(connectionOption);
manifestCommand.AddOption(prefixOption);
manifestCommand.AddOption(manifestOutputOption);
manifestCommand.AddOption(includeDataOption);

manifestCommand.SetHandler(
    (string connection, string prefix, string output, bool includeData) =>
    {
        try
        {
            Console.WriteLine($"🔍 Generating manifest (prefix: {prefix}, includeData: {includeData})...");

            var introspector = new DatabaseIntrospector(connection, prefix, includeData);
            var manifest = introspector.GenerateManifest();

            var generator = new ManifestGenerator();
            generator.SaveToFile(manifest, output);

            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine($"✅ Manifest successfully saved to {output}");
            Console.ResetColor();
        }
        catch (Exception ex)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine($"❌ Error: {ex.Message}");
            Console.ResetColor();
        }
    },
    connectionOption, prefixOption, manifestOutputOption, includeDataOption
);

// ========== OPTIONS FOR INSTALLER ==========
var manifestFileOption = new Option<string>(
    name: "--manifest-file",
    description: "Path to the manifest JSON file")
{ IsRequired = true };

var installerOutputOption = new Option<string>(
    name: "--output",
    description: "Output path for the PHP installer class",
    getDefaultValue: () => "class-my-plugin-installer.php");

var classNameOption = new Option<string>(
    name: "--classname",
    description: "PHP class name for the installer",
    getDefaultValue: () => "MyPlugin_Installer");

var createStubOption = new Option<bool>(
    name: "--create-stub",
    description: "Also generate a PHP stub file to test the installer",
    getDefaultValue: () => false);
    

// ---------- INSTALLER COMMAND ----------
var installerCommand = new Command("installer", "Generate a WordPress installer/uninstaller PHP class");
installerCommand.AddOption(manifestFileOption);
installerCommand.AddOption(installerOutputOption);
installerCommand.AddOption(classNameOption);
installerCommand.AddOption(createStubOption);


installerCommand.SetHandler(
    (string manifestFile, string output, string classname, bool createStub) =>
    {
        try
        {
            Console.WriteLine($"🔧 Generating installer class ({classname}) from {manifestFile}...");

            var manifestGen = new ManifestGenerator();
            var manifestObj = manifestGen.LoadFromFile(manifestFile);

            var installerGen = new InstallerClassGenerator();
            installerGen.SaveToFile(manifestObj, output, classname);

            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine($"✅ Installer class saved to {output}");

            if (createStub)
            {
                string stubFile = Path.Combine(Path.GetDirectoryName(output) ?? ".", "test-installer.php");
                installerGen.SaveInstallerStub(stubFile, classname, Path.GetFileName(output));

                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine($"✅ Stub file created: {stubFile}");
            }

            Console.ResetColor();
        }
        catch (Exception ex)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine($"❌ Error: {ex.Message}");
            Console.ResetColor();
        }
    },
    manifestFileOption, installerOutputOption, classNameOption, createStubOption
);



// ---------- BUILD COMMAND TREE ----------
generateCommand.AddCommand(manifestCommand);
generateCommand.AddCommand(installerCommand);
rootCommand.AddCommand(generateCommand);

// ---------- EXECUTE ----------
await rootCommand.InvokeAsync(args);
