# WPStallman

A WordPress packaging utility designed to help developers generate **database installers** for their WordPress plugins.

The name is a combination of W\.C. Fields, WordPress, and Richard Stallman , combining a philosophy of open tools with a curmudgeonly approach to software development.

---

## ✅ Features

* **Generate JSON Manifests** of your database schema:

  * Tables (columns, keys, seed data, row limits, skip flags)
  * Views
  * Stored Procedures (with parameters)
  * Triggers
* **Generate WordPress Installer Classes** (PHP):

  * Automatically creates and drops tables, views, procedures, and triggers.
  * Populates seed data respecting row limits.
  * Skips tables marked as `skip: true` in the manifest.
* **Generate a Test Stub** to quickly verify your installer in a WordPress environment.

---

## ✅ Requirements

* **.NET 6.0 or later** (tested on .NET 8.0)
* **MySQL 5.7+ / MariaDB** (WordPress standard)
* WordPress installation (only needed for testing generated installers)

---

## ✅ Installation (Development)

Clone the repo and build:

```bash
git clone https://your-repo-url/wpstallmannetcore.git
cd wpstallmannetcore
dotnet restore
dotnet build
```

---

## ✅ Usage

### 1) Generate a Manifest

```bash
dotnet run --project WPStallman.CLI generate manifest \
  --connection "server=localhost;uid=root;pwd=;database=wp_my_plugin" \
  --prefix "wp_" \
  --output "manifest.json" \
  --include-data
```

### Example Manifest Snippet

```json
{
  "tables": [
    {
      "name": "my_plugin_settings",
      "rowLimit": 5,
      "skip": false,
      "columns": [
        { "name": "id", "type": "int(11)", "primaryKey": true, "autoIncrement": true },
        { "name": "setting_key", "type": "varchar(50)", "nullable": false },
        { "name": "setting_value", "type": "text", "nullable": true }
      ],
      "seedData": [
        { "id": 1, "setting_key": "enable_feature", "setting_value": "1" }
      ]
    }
  ]
}
```

### 2) Generate an Installer Class

```bash
dotnet run --project WPStallman.CLI generate installer \
  --manifest-file "manifest.json" \
  --output "class-my-plugin-installer.php" \
  --classname "MyPlugin_Installer" \
  --create-stub
```

### Example Installer Snippet

```php
<?php
class MyPlugin_Installer {
    private $wpdb;
    private $prefix;

    public function __construct($wpdb) {
        $this->wpdb = $wpdb;
        $this->prefix = $wpdb->get_blog_prefix();
    }

    public function install() {
        $charset_collate = $this->wpdb->get_charset_collate();
        require_once(ABSPATH . 'wp-admin/includes/upgrade.php');

        // Table: my_plugin_settings
        $sql = <<<SQL
CREATE TABLE {$this->prefix}my_plugin_settings (
    id int(11) NOT NULL AUTO_INCREMENT,
    setting_key varchar(50) NOT NULL,
    setting_value text,
    PRIMARY KEY (id)
) $charset_collate;
SQL;
        dbDelta($sql);
    }

    public function populate() {
        $this->wpdb->query("INSERT INTO {$this->prefix}my_plugin_settings (id, setting_key, setting_value) VALUES (1, 'enable_feature', '1');");
    }

    public function uninstall() {
        $this->wpdb->query("DROP TABLE IF EXISTS {$this->prefix}my_plugin_settings");
    }
}
?>
```

### 3) Test the Installer

Drop `class-my-plugin-installer.php` and `test-installer.php` into your plugin directory, then run:

```bash
php test-installer.php
```

Expected output:

```
Running install...
Populating seed data...
Done!
```

Uncomment the uninstall call in the stub to remove objects after testing.

---

## ✅ License

MIT © 2025 Left Hand Enterprises, LLC — see [LICENSE](./LICENSE) for details.


---

## ✅ Credits

Copyright 2025 Left Hand Enterprises, LLC.
