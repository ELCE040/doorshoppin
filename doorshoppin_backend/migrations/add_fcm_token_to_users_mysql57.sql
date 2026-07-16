-- ============================================================
-- Add FCM token and indexes for notifications (MySQL 5.7 / MariaDB)
-- Run once. Safe on older MySQL; ignore "Duplicate column/key" if re-run.
-- ============================================================

-- Add fcm_token column (ignore error if already exists)
ALTER TABLE `users`
ADD COLUMN `fcm_token` VARCHAR(255) NULL DEFAULT NULL
COMMENT 'Firebase Cloud Messaging token for push notifications';

-- Add indexes (ignore error if already exists)
ALTER TABLE `users` ADD INDEX `idx_fcm_token` (`fcm_token`);
ALTER TABLE `users` ADD INDEX `idx_email` (`email`);
ALTER TABLE `users` ADD INDEX `idx_phone` (`phone`);

-- Show structure
DESCRIBE `users`;
