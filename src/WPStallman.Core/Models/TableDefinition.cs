namespace WPStallman.Core.Models;

public class TableDefinition
{
    public string Name { get; set; } = string.Empty;
    public string NameOriginal { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string? Comment { get; set; }

    public int RowLimit { get; set; } = 0;  // NEW
    public bool Skip { get; set; } = false; // NEW

    public List<ColumnDefinition> Columns { get; set; } = new();
    public List<IndexDefinition> Indexes { get; set; } = new();
    public List<ConstraintDefinition> Constraints { get; set; } = new();
    public List<ForeignKeyDefinition> ForeignKeys { get; set; } = new();
    public List<Dictionary<string, object>> SeedData { get; set; } = new();
}


public class ColumnDefinition
{
    public string Name { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public bool Nullable { get; set; }
    public bool AutoIncrement { get; set; }
    public bool PrimaryKey { get; set; }
    public string? Default { get; set; }
    public string? Comment { get; set; }
}

public class IndexDefinition
{
    public string Name { get; set; } = string.Empty;
    public List<string> Columns { get; set; } = new();
    public bool Unique { get; set; }
}

public class ConstraintDefinition
{
    public string Name { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty; // e.g., "PRIMARY KEY"
    public List<string> Columns { get; set; } = new();
}

public class ForeignKeyDefinition
{
    public string Name { get; set; } = string.Empty;
    public string Column { get; set; } = string.Empty;
    public ForeignKeyReference References { get; set; } = new();
    public string? OnDelete { get; set; }
    public string? OnUpdate { get; set; }
}

public class ForeignKeyReference
{
    public string Table { get; set; } = string.Empty;
    public string Column { get; set; } = string.Empty;
}
