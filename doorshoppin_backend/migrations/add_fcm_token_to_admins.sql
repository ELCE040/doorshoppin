-- Add FCM token to admins table (admins are in SQL, not Firebase).
-- Run once in phpMyAdmin on the same DB your Node backend uses (e.g. doorbuvi_door_shopping).

ALTER TABLE `admins`
ADD COLUMN `fcm_token` VARCHAR(255) NULL DEFAULT NULL AFTER `password`;

-- Optional: index for lookups if you ever query by token
-- CREATE INDEX idx_admins_fcm_token ON admins (fcm_token(64));
