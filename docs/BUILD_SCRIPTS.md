# WP Stallman – Packaging Scripts

This folder contains helper scripts to build and package the WP Stallman GUI app for multiple platforms.

## Scripts

- **deploy_icons.sh**  
  Copies icons from `WPStallman.Assets/logo/` into `WPStallman.GUI/wwwroot/img/`.  
  Run this before building to ensure the app has the correct icons.

  ```bash
  ./scripts/deploy_icons.sh
