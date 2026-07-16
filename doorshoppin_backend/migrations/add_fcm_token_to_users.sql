-- ============================================================
-- Add FCM token and indexes for notifications (MySQL 8.0.12+)
-- Run once. Requires MySQL 8.0.12+ for IF NOT EXISTS.
-- ============================================================

-- Add fcm_token column if it doesn't exist
ALTER TABLE `users`
ADD COLUMN IF NOT EXISTS `fcm_token` VARCHAR(255) NULL DEFAULT NULL
COMMENT 'Firebase Cloud Messaging token for push notifications';

-- Ensure email column exists (users table already has email)
-- ALTER TABLE `users` ADD COLUMN IF NOT EXISTS `email` VARCHAR(255) NULL DEFAULT NULL;

-- Ensure phone_number column if you use it; otherwise your table has `phone`
-- ALTER TABLE `users` ADD COLUMN IF NOT EXISTS `phone_number` VARCHAR(50) NULL DEFAULT NULL;

-- Add indexes for faster lookups
ALTER TABLE `users`
ADD INDEX IF NOT EXISTS `idx_fcm_token` (`fcm_token`);

ALTER TABLE `users`
ADD INDEX IF NOT EXISTS `idx_email` (`email`);

ALTER TABLE `users`
ADD INDEX IF NOT EXISTS `idx_phone` (`phone`);

-- Show structure
DESCRIBE `users`;
