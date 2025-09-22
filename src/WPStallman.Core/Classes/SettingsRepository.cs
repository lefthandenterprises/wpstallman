// File: Classes/SettingsRepository.cs
using LiteDB;
using System;

namespace WPStallman.Core.Classes;

public class SettingsRepository : IDisposable
{
    private readonly LiteDatabase _db;
    private readonly ILiteCollection<AppSetting> _coll;

    public SettingsRepository(string dbPath = "settings.db")
    {
        _db = new LiteDatabase(dbPath);
        _coll = _db.GetCollection<AppSetting>("settings");
        _coll.EnsureIndex(x => x.Key, true);
    }

    public void Save(string key, string value)
    {
        var setting = new AppSetting { Key = key, Value = value };
        _coll.Upsert(setting);
    }

    public string? Load(string key)
    {
        var setting = _coll.FindById(key);
        return setting?.Value;
    }

    public void Dispose()
    {
        _db?.Dispose();
    }
}

