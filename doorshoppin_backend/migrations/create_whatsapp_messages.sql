-- WhatsApp Inbox: store incoming & outgoing messages
-- Run this migration on your MySQL database.

CREATE TABLE IF NOT EXISTS `whatsapp_messages` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `wa_message_id` varchar(255) DEFAULT NULL COMMENT 'WhatsApp message ID from Meta',
  `contact_phone` varchar(30) NOT NULL COMMENT 'E.164 without + (e.g. 265991234567)',
  `contact_name` varchar(255) DEFAULT NULL COMMENT 'Profile name if available',
  `direction` enum('inbound','outbound') NOT NULL DEFAULT 'inbound',
  `message_type` varchar(30) NOT NULL DEFAULT 'text' COMMENT 'text, image, audio, video, document, button, reaction, etc.',
  `body` text DEFAULT NULL COMMENT 'Message text body or caption',
  `media_url` varchar(500) DEFAULT NULL COMMENT 'URL for media messages',
  `status` varchar(30) DEFAULT NULL COMMENT 'sent, delivered, read, failed (for outbound)',
  `wa_timestamp` datetime DEFAULT NULL COMMENT 'Timestamp from WhatsApp',
  `is_read` tinyint(1) NOT NULL DEFAULT 0 COMMENT 'Whether admin has read this message',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_wa_message_id` (`wa_message_id`),
  KEY `idx_contact_phone` (`contact_phone`),
  KEY `idx_direction` (`direction`),
  KEY `idx_created_at` (`created_at`),
  KEY `idx_is_read` (`is_read`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
