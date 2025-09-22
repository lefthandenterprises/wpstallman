using WPStallman.Core.Models;

namespace WPStallman.Core.Classes;

    public class CreateInstallerDetails
    {
        public required string ConnectionString { get; set; }
        public required string DbPrefixOverride { get; set; }
        public required string InstallerClassNameOverride { get; set; }
        public bool IncludeSeedDataOverride { get; set; }

        public string? DestinationZipFilePath { get; set; }

        public required Manifest Manifest { get; set; }
    }

