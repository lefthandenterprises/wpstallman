using MySqlConnector;
using WPStallman.Core.Models;
using System.Data;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace WPStallman.Core.Services;

public class DatabaseIntrospector
{
    private readonly string _connectionString;
    private readonly string _prefix;

    private readonly bool _includeData;
    private readonly JsonSerializerOptions _jsonOptions;

    public DatabaseIntrospector(string connectionString, string prefix = "wp_", bool includeData = false)
    {
        _connectionString = connectionString;
        _prefix = prefix;
        _includeData = includeData;
        _jsonOptions = NewMethod();
    }

    private JsonSerializerOptions NewMethod()
    {
        return new JsonSerializerOptions
        {
            WriteIndented = true, // Pretty print for readability
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase // Matches our JSON standard
        };
    }

    public DatabaseIntrospector(string connectionString, string prefix = "wp_")
    {
        _connectionString = connectionString;
        _prefix = prefix;
        _jsonOptions = NewMethod();
    }

    public Manifest GenerateManifest()
    {
        var manifest = new Manifest
        {
            Database = GetDatabaseName(),
            DefaultPrefix = _prefix,
            Tables = GetTables(),
            Views = GetViews(),
            StoredProcedures = GetStoredProcedures(),
            Triggers = GetTriggers()
        };

        manifest.CreatePHPStatements();

        return manifest;
    }

    public string GenerateManifestJSON()
    {
        var manifest = new Manifest
        {
            Database = GetDatabaseName(),
            DefaultPrefix = _prefix,
            Tables = GetTables(),
            Views = GetViews(),
            StoredProcedures = GetStoredProcedures(),
            Triggers = GetTriggers()
        };

        manifest.CreatePHPStatements();

        return JsonSerializer.Serialize(manifest, _jsonOptions);
    }

    private string GetDatabaseName()
    {
        using var conn = new MySqlConnection(_connectionString);
        return conn.Database;
    }

    #region Tables
    private List<TableDefinition> GetTables()
    {
        var tables = new List<TableDefinition>();
        using var conn = new MySqlConnection(_connectionString);
        conn.Open();

        using var cmd = new MySqlCommand("SHOW FULL TABLES WHERE Table_type = 'BASE TABLE';", conn);
        using var reader = cmd.ExecuteReader();

        while (reader.Read())
        {
            string originalName = reader.GetString(0);
            if (!originalName.StartsWith(_prefix)) continue;

            var table = new TableDefinition
            {
                NameOriginal = originalName,
                Name = StripPrefix(originalName),
                FullName = originalName,
                Comment = "" // Will populate later via information_schema if needed
            };

            table.Columns = GetColumns(table.NameOriginal);
            table.Indexes = GetIndexes(table.NameOriginal);
            table.Constraints = GetConstraints(table.NameOriginal);
            table.ForeignKeys = GetForeignKeys(table.NameOriginal);

            if (_includeData)
            {
                table.RowLimit = 100; // default global limit, editable later in manifest
                table.SeedData = GetSeedData(table.NameOriginal, table.RowLimit);
            }



            tables.Add(table);
        }

        return tables;
    }

    private List<ColumnDefinition> GetColumns(string tableName)
    {
        var columns = new List<ColumnDefinition>();
        using var conn = new MySqlConnection(_connectionString);
        conn.Open();

        string sql = $"SHOW FULL COLUMNS FROM `{tableName}`;";
        using var cmd = new MySqlCommand(sql, conn);
        using var reader = cmd.ExecuteReader();

        while (reader.Read())
        {
            columns.Add(new ColumnDefinition
            {
                Name = reader["Field"].ToString() ?? "",
                Type = reader["Type"].ToString() ?? "",
                Nullable = reader["Null"].ToString() == "YES",
                AutoIncrement = reader["Extra"].ToString().Contains("auto_increment"),
                PrimaryKey = reader["Key"].ToString() == "PRI",
                Default = reader["Default"]?.ToString(),
                Comment = reader["Comment"]?.ToString()
            });
        }

        return columns;
    }

    private List<IndexDefinition> GetIndexes(string tableName)
    {
        var indexes = new List<IndexDefinition>();
        using var conn = new MySqlConnection(_connectionString);
        conn.Open();

        string sql = $"SHOW INDEX FROM `{tableName}`;";
        using var cmd = new MySqlCommand(sql, conn);
        using var reader = cmd.ExecuteReader();

        var indexGroups = new Dictionary<string, IndexDefinition>();

        while (reader.Read())
        {
            string keyName = reader["Key_name"].ToString()!;
            if (!indexGroups.ContainsKey(keyName))
            {
                indexGroups[keyName] = new IndexDefinition
                {
                    Name = keyName,
                    Unique = reader["Non_unique"].ToString() == "0"
                };
            }

            indexGroups[keyName].Columns.Add(reader["Column_name"].ToString()!);
        }

        indexes.AddRange(indexGroups.Values);
        return indexes;
    }

    private List<ConstraintDefinition> GetConstraints(string tableName)
    {
        // MySQL primary keys and unique keys are also in SHOW INDEX, but we keep them separate for clarity
        var constraints = new List<ConstraintDefinition>();
        using var conn = new MySqlConnection(_connectionString);
        conn.Open();

        string sql = @"
            SELECT CONSTRAINT_NAME, CONSTRAINT_TYPE
            FROM information_schema.TABLE_CONSTRAINTS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = @tableName;";

        using var cmd = new MySqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("@tableName", tableName);

        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            constraints.Add(new ConstraintDefinition
            {
                Name = reader["CONSTRAINT_NAME"].ToString() ?? "",
                Type = reader["CONSTRAINT_TYPE"].ToString() ?? "",
                Columns = new() // Optionally fill via KEY_COLUMN_USAGE
            });
        }

        return constraints;
    }

    private List<ForeignKeyDefinition> GetForeignKeys(string tableName)
    {
        var fks = new List<ForeignKeyDefinition>();
        using var conn = new MySqlConnection(_connectionString);
        conn.Open();

        string sql = @"
            SELECT
                rc.CONSTRAINT_NAME,
                kcu.COLUMN_NAME,
                kcu.REFERENCED_TABLE_NAME,
                kcu.REFERENCED_COLUMN_NAME,
                rc.UPDATE_RULE,
                rc.DELETE_RULE
            FROM information_schema.REFERENTIAL_CONSTRAINTS rc
            JOIN information_schema.KEY_COLUMN_USAGE kcu
              ON rc.CONSTRAINT_NAME = kcu.CONSTRAINT_NAME
             AND rc.CONSTRAINT_SCHEMA = kcu.CONSTRAINT_SCHEMA
            WHERE rc.CONSTRAINT_SCHEMA = DATABASE() AND rc.TABLE_NAME = @tableName;";

        using var cmd = new MySqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("@tableName", tableName);

        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            fks.Add(new ForeignKeyDefinition
            {
                Name = reader["CONSTRAINT_NAME"].ToString() ?? "",
                Column = reader["COLUMN_NAME"].ToString() ?? "",
                References = new ForeignKeyReference
                {
                    Table = StripPrefix(reader["REFERENCED_TABLE_NAME"].ToString() ?? ""),
                    Column = reader["REFERENCED_COLUMN_NAME"].ToString() ?? ""
                },
                OnUpdate = reader["UPDATE_RULE"].ToString(),
                OnDelete = reader["DELETE_RULE"].ToString()
            });
        }

        return fks;
    }

    private List<Dictionary<string, object>> GetSeedData(string tableName, int limit)
    {
        var rows = new List<Dictionary<string, object>>();
        using var conn = new MySqlConnection(_connectionString);
        conn.Open();

        string sql = limit > 0
            ? $"SELECT * FROM `{tableName}` LIMIT {limit};"
            : $"SELECT * FROM `{tableName}`;";

        using var cmd = new MySqlCommand(sql, conn);
        using var reader = cmd.ExecuteReader();

        while (reader.Read())
        {
            var row = new Dictionary<string, object>();
            for (int i = 0; i < reader.FieldCount; i++)
            {
                string colName = reader.GetName(i);
                object value = reader.IsDBNull(i) ? null! : reader.GetValue(i);
                row[colName] = value;
            }
            rows.Add(row);
        }

        return rows;
    }


    #endregion

    #region Views
    private List<ViewDefinition> GetViews()
    {
        var views = new List<ViewDefinition>();
        using var conn = new MySqlConnection(_connectionString);
        conn.Open();

        string sql = "SHOW FULL TABLES WHERE Table_type = 'VIEW';";
        using var cmd = new MySqlCommand(sql, conn);
        using var reader = cmd.ExecuteReader();

        while (reader.Read())
        {
            string originalName = reader.GetString(0);
            if (!originalName.StartsWith(_prefix)) continue;

            views.Add(new ViewDefinition
            {
                NameOriginal = originalName,
                Name = StripPrefix(originalName),
                FullName = originalName,
                Definition = GetViewDefinition(originalName)
            });
        }

        return views;
    }

    private string GetViewDefinition(string viewName)
    {
        using var conn = new MySqlConnection(_connectionString);
        conn.Open();

        using var cmd = new MySqlCommand($"SHOW CREATE VIEW `{viewName}`;", conn);
        using var reader = cmd.ExecuteReader();
        return reader.Read() ? reader["Create View"].ToString() ?? "" : "";
    }
    #endregion

    #region Stored Procedures
    private List<StoredProcedureDefinition> GetStoredProcedures()
    {
        var sps = new List<StoredProcedureDefinition>();
        using var conn = new MySqlConnection(_connectionString);
        conn.Open();

        string sql = "SHOW PROCEDURE STATUS WHERE Db = DATABASE();";
        using var cmd = new MySqlCommand(sql, conn);
        using var reader = cmd.ExecuteReader();

        while (reader.Read())
        {
            string originalName = reader["Name"].ToString()!;
            if (!originalName.StartsWith(_prefix)) continue;

            sps.Add(new StoredProcedureDefinition
            {
                NameOriginal = originalName,
                Name = StripPrefix(originalName),
                FullName = originalName,
                Definition = GetStoredProcedureDefinition(originalName),
                Parameters = GetStoredProcedureParameters(originalName)
            });
        }

        return sps;
    }

    private string GetStoredProcedureDefinition(string spName)
    {
        using var conn = new MySqlConnection(_connectionString);
        conn.Open();

        using var cmd = new MySqlCommand($"SHOW CREATE PROCEDURE `{spName}`;", conn);
        using var reader = cmd.ExecuteReader();
        return reader.Read() ? reader["Create Procedure"].ToString() ?? "" : "";
    }

    private List<StoredProcedureParameter> GetStoredProcedureParameters(string spName)
    {
        var parameters = new List<StoredProcedureParameter>();
        string definition = GetStoredProcedureDefinition(spName);

        // Extract the parameter section between parentheses after the procedure name
        // Example: CREATE PROCEDURE my_proc (IN p_start_date DATETIME, OUT p_count INT)
        var match = System.Text.RegularExpressions.Regex.Match(
            definition,
            @"\((.*?)\)",
            System.Text.RegularExpressions.RegexOptions.Singleline);

        if (!match.Success) return parameters;

        string paramSection = match.Groups[1].Value.Trim();

        if (string.IsNullOrEmpty(paramSection)) return parameters;

        // Split by commas, but trim whitespace
        var rawParams = paramSection.Split(',')
                                    .Select(p => p.Trim())
                                    .Where(p => !string.IsNullOrWhiteSpace(p));

        foreach (var rawParam in rawParams)
        {
            // Typical format: "IN p_start_date DATETIME" or "OUT p_count INT"
            var parts = rawParam.Split(' ', StringSplitOptions.RemoveEmptyEntries);

            string mode = "IN";
            string name = "";
            string type = "";

            if (parts.Length == 2)
            {
                // No explicit IN/OUT given (default IN)
                name = parts[0];
                type = parts[1];
            }
            else if (parts.Length >= 3)
            {
                mode = parts[0];
                name = parts[1];
                type = string.Join(" ", parts.Skip(2)); // Handles things like VARCHAR(255)
            }

            parameters.Add(new StoredProcedureParameter
            {
                Name = name,
                Type = type,
                Mode = mode
            });
        }

        return parameters;
    }

    #endregion

    #region Triggers
    private List<TriggerDefinition> GetTriggers()
    {
        var triggers = new List<TriggerDefinition>();
        using var conn = new MySqlConnection(_connectionString);
        conn.Open();

        string sql = "SHOW TRIGGERS;";
        using var cmd = new MySqlCommand(sql, conn);
        using var reader = cmd.ExecuteReader();

        while (reader.Read())
        {
            string triggerName = reader["Trigger"].ToString()!;
            string tableName = reader["Table"].ToString()!;

            // Only include triggers where the TABLE matches your prefix
            if (!tableName.StartsWith(_prefix)) continue;

            triggers.Add(new TriggerDefinition
            {
                NameOriginal = triggerName,
                Name = StripPrefix(triggerName),
                FullName = triggerName,
                Event = $"{reader["Timing"]} {reader["Event"]}",
                Table = StripPrefix(tableName),
                Definition = reader["Statement"].ToString() ?? ""
            });
        }

        return triggers;
    }

    #endregion

    private string StripPrefix(string name)
    {
        return name.StartsWith(_prefix) ? name.Substring(_prefix.Length) : name;
    }
}
