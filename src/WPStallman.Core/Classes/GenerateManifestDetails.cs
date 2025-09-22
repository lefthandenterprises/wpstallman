namespace WPStallman.Core.Classes;

    public class GenerateManifestDetails
    {
        public required string ConnectionString { get; set; }
        public required string DbPrefix { get; set; }
        public required string InstallerClassName { get; set; }
        public bool IncludeSeedData { get; set; }
        // Add other options as needed
    }



