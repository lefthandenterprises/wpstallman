// File: Classes/AppSetting.cs
using LiteDB;

namespace WPStallman.GUI.Classes
{
    public class AppSetting
    {
        [BsonId]
        public string Key { get; set; } = "";
        public string Value { get; set; } = "";
    }
}
