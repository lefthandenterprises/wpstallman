namespace WPStallman.Core.Models;

public class InstallerOutputFile
{
    public InstallerOutputFile()
    {

    }
    public InstallerOutputFile(string name, string content)
    {
        this.Name = name;
        this.Content = content;
    }

    public string? Name { get; set; }
    public string? Content { get; set; }
    
    public string? Type { get; set; } // InstallerClass, InstallerStub
}
