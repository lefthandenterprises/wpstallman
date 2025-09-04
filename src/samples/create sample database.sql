-- ============================================================================
-- WP Stallman Design • Safe Reset Script
-- Recreates all objects from the baseline manifest with a "sample_plugin_" prefix
-- so they never collide with WordPress core tables or existing sites.
-- Database: wp_stallman_design
-- Generated: 2025-08-27
-- ============================================================================

/* Strongly recommended: run this in a disposable schema while iterating. */
USE `wp_stallman_design`;

-- --------------------------------------------------------------------------
-- SAFETY SWITCHES
-- --------------------------------------------------------------------------
SET @old_fk_checks := @@FOREIGN_KEY_CHECKS;
SET @old_sql_notices := @@SQL_NOTES;
SET FOREIGN_KEY_CHECKS = 0;
SET SQL_NOTES = 0;

-- --------------------------------------------------------------------------
-- DROP in dependency-safe order
-- --------------------------------------------------------------------------

-- 1) Views (depend on tables)
DROP VIEW IF EXISTS `wp_sample_plugin_active_users`;
DROP VIEW IF EXISTS `wp_sample_plugin_active_roles`;

-- 2) Triggers (depend on tables)
DROP TRIGGER IF EXISTS `wp_sample_plugin_after_user_insert`;

-- 3) Stored Procedures
DROP PROCEDURE IF EXISTS `wp_sample_plugin_create_role`;
DROP PROCEDURE IF EXISTS `wp_sample_plugin_create_user`;
DROP PROCEDURE IF EXISTS `wp_sample_plugin_delete_role`;
DROP PROCEDURE IF EXISTS `wp_sample_plugin_delete_user`;
DROP PROCEDURE IF EXISTS `wp_sample_plugin_get_role`;
DROP PROCEDURE IF EXISTS `wp_sample_plugin_get_user`;
DROP PROCEDURE IF EXISTS `wp_sample_plugin_update_role`;
DROP PROCEDURE IF EXISTS `wp_sample_plugin_update_user`;

-- 4) Tables (children first)
DROP TABLE IF EXISTS `wp_sample_plugin_user_audit`;
DROP TABLE IF EXISTS `wp_sample_plugin_users`;
DROP TABLE IF EXISTS `wp_sample_plugin_roles`;

-- --------------------------------------------------------------------------
-- CREATE TABLES
-- --------------------------------------------------------------------------

CREATE TABLE `wp_sample_plugin_roles` (
  `role_id` int(11) NOT NULL AUTO_INCREMENT,
  `role_name` varchar(100) NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`role_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `wp_sample_plugin_users` (
  `user_id` int(11) NOT NULL AUTO_INCREMENT,
  `role_id` int(11) NOT NULL,
  `username` varchar(50) NOT NULL,
  `email` varchar(100) NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`user_id`),
  UNIQUE KEY `ux_username` (`username`),
  UNIQUE KEY `ux_email` (`email`),
  KEY `ix_role_id` (`role_id`),
  CONSTRAINT `fk_users_role`
    FOREIGN KEY (`role_id`) REFERENCES `wp_sample_plugin_roles` (`role_id`)
    ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `wp_sample_plugin_user_audit` (
  `audit_id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NULL,
  `action_type` varchar(20) NULL,
  `action_timestamp` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`audit_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------------------------
-- SEED DATA (from manifest)
-- --------------------------------------------------------------------------

INSERT INTO `wp_sample_plugin_roles` (`role_id`, `role_name`, `is_active`, `created_at`) VALUES
  (1, 'Administrator', 1, '2025-08-20 13:54:33'),
  (2, 'Editor',        1, '2025-08-20 13:54:33'),
  (3, 'Viewer',        1, '2025-08-20 13:54:33'),
  (4, 'InactiveRole',  0, '2025-08-20 13:54:33')
ON DUPLICATE KEY UPDATE
  `role_name`=VALUES(`role_name`),
  `is_active`=VALUES(`is_active`);

INSERT INTO `wp_sample_plugin_users` (`user_id`, `role_id`, `username`, `email`, `is_active`, `created_at`) VALUES
  (1, 1, 'admin_user',    'admin@example.com',           1, '2025-08-20 13:54:33'),
  (2, 2, 'editor_jane',   'jane.editor@example.com',     1, '2025-08-20 13:54:33'),
  (3, 2, 'editor_john',   'john.editor@example.com',     1, '2025-08-20 13:54:33'),
  (4, 3, 'viewer_sam',    'sam.viewer@example.com',      1, '2025-08-20 13:54:33'),
  (5, 4, 'old_inactive_user', 'inactive@example.com',    0, '2025-08-20 13:54:33')
ON DUPLICATE KEY UPDATE
  `role_id`=VALUES(`role_id`),
  `username`=VALUES(`username`),
  `email`=VALUES(`email`),
  `is_active`=VALUES(`is_active`);

INSERT INTO `wp_sample_plugin_user_audit` (`audit_id`, `user_id`, `action_type`, `action_timestamp`) VALUES
  (1, 1, 'INSERT', '2025-08-20 13:54:33'),
  (2, 2, 'INSERT', '2025-08-20 13:54:33'),
  (3, 3, 'INSERT', '2025-08-20 13:54:33'),
  (4, 4, 'INSERT', '2025-08-20 13:54:33'),
  (5, 5, 'INSERT', '2025-08-20 13:54:33')
ON DUPLICATE KEY UPDATE
  `user_id`=VALUES(`user_id`),
  `action_type`=VALUES(`action_type`);

-- --------------------------------------------------------------------------
-- VIEWS (without DEFINER to avoid permissions issues)
-- --------------------------------------------------------------------------

DROP VIEW IF EXISTS `wp_sample_plugin_active_roles`;
CREATE VIEW `wp_sample_plugin_active_roles` AS
SELECT
  r.`role_id`,
  r.`role_name`
FROM `wp_sample_plugin_roles` r
WHERE r.`is_active` = 1;

DROP VIEW IF EXISTS `wp_sample_plugin_active_users`;
CREATE VIEW `wp_sample_plugin_active_users` AS
SELECT
  u.`user_id`,
  u.`username`,
  u.`email`,
  r.`role_name`
FROM `wp_sample_plugin_users` u
JOIN `wp_sample_plugin_roles` r ON u.`role_id` = r.`role_id`
WHERE u.`is_active` = 1;

-- --------------------------------------------------------------------------
-- PROCEDURES (omit DEFINER; use DELIMITER for bodies)
-- --------------------------------------------------------------------------
DELIMITER $$

CREATE PROCEDURE `wp_sample_plugin_create_role`(
  IN p_role_name VARCHAR(100),
  IN p_is_active BOOLEAN
)
BEGIN
  INSERT INTO `wp_sample_plugin_roles` (role_name, is_active)
  VALUES (p_role_name, p_is_active);
END$$

CREATE PROCEDURE `wp_sample_plugin_create_user`(
  IN p_role_id INT,
  IN p_username VARCHAR(50),
  IN p_email VARCHAR(100),
  IN p_is_active BOOLEAN
)
BEGIN
  INSERT INTO `wp_sample_plugin_users` (role_id, username, email, is_active)
  VALUES (p_role_id, p_username, p_email, p_is_active);
END$$

CREATE PROCEDURE `wp_sample_plugin_delete_role`(IN p_role_id INT)
BEGIN
  DELETE FROM `wp_sample_plugin_roles` WHERE role_id = p_role_id;
END$$

CREATE PROCEDURE `wp_sample_plugin_delete_user`(IN p_user_id INT)
BEGIN
  DELETE FROM `wp_sample_plugin_users` WHERE user_id = p_user_id;
END$$

CREATE PROCEDURE `wp_sample_plugin_get_role`(IN p_role_id INT)
BEGIN
  SELECT * FROM `wp_sample_plugin_roles` WHERE role_id = p_role_id;
END$$

CREATE PROCEDURE `wp_sample_plugin_get_user`(IN p_user_id INT)
BEGIN
  SELECT * FROM `wp_sample_plugin_users` WHERE user_id = p_user_id;
END$$

CREATE PROCEDURE `wp_sample_plugin_update_role`(
  IN p_role_id INT,
  IN p_role_name VARCHAR(100),
  IN p_is_active BOOLEAN
)
BEGIN
  UPDATE `wp_sample_plugin_roles`
  SET role_name = p_role_name,
      is_active = p_is_active
  WHERE role_id = p_role_id;
END$$

CREATE PROCEDURE `wp_sample_plugin_update_user`(
  IN p_user_id INT,
  IN p_role_id INT,
  IN p_username VARCHAR(50),
  IN p_email VARCHAR(100),
  IN p_is_active BOOLEAN
)
BEGIN
  UPDATE `wp_sample_plugin_users`
  SET role_id = p_role_id,
      username = p_username,
      email = p_email,
      is_active = p_is_active
  WHERE user_id = p_user_id;
END$$

-- --------------------------------------------------------------------------
-- TRIGGERS
-- --------------------------------------------------------------------------

CREATE TRIGGER `wp_sample_plugin_after_user_insert`
AFTER INSERT ON `wp_sample_plugin_users`
FOR EACH ROW
BEGIN
  INSERT INTO `wp_sample_plugin_user_audit` (user_id, action_type)
  VALUES (NEW.user_id, 'INSERT');
END$$

DELIMITER ;

-- --------------------------------------------------------------------------
-- RESTORE SWITCHES
-- --------------------------------------------------------------------------
SET FOREIGN_KEY_CHECKS = @old_fk_checks;
SET SQL_NOTES = @old_sql_notices;

-- End of script
