-- ============================================================
-- Fix FCM token column width + ensure phone index exists
-- Run this on your database to fix user FCM token lookups.
-- Safe to run multiple times (uses IF NOT EXISTS / MODIFY).
-- ============================================================

-- 1. Widen fcm_token to 512 chars (FCM tokens can be 152–250+ chars)
ALTER TABLE `users`
  MODIFY COLUMN `fcm_token` VARCHAR(512) NULL DEFAULT NULL
  COMMENT 'Firebase Cloud Messaging device token';

-- 2. Add phone index if missing (needed for fast lookup during status update)
ALTER TABLE `users`
  ADD INDEX IF NOT EXISTS `idx_phone` (`phone`);

-- 3. Add email index if missing
ALTER TABLE `users`
  ADD INDEX IF NOT EXISTS `idx_email` (`email`);

-- 4. Add fcm_token index if missing (for quick non-null checks)
ALTER TABLE `users`
  ADD INDEX IF NOT EXISTS `idx_fcm_token` (`fcm_token`(64));

-- Verify
DESCRIBE `users`;
