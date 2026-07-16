-- ============================================================
-- REDO ALL SCHEMA CHANGES
-- Run this to reset the database to the current expected schema.
-- WARNING: Drops views and tables, then recreates them. Back up first.
-- ============================================================

SET FOREIGN_KEY_CHECKS = 0;

-- Drop views first (depend on tables)
DROP VIEW IF EXISTS order_details;
DROP VIEW IF EXISTS payment_transactions;

-- Drop tables (child tables first)
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS temp_orders;
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS promotions;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS admins;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS delivery_settings;
DROP TABLE IF EXISTS settings;

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================
-- CREATE TABLES
-- ============================================================

CREATE TABLE `users` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `firebase_uid` varchar(255) NOT NULL,
  `name` varchar(255) DEFAULT NULL,
  `email` varchar(255) NOT NULL,
  `password` varchar(255) DEFAULT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `location` varchar(255) DEFAULT NULL,
  `avatar` varchar(500) DEFAULT NULL,
  `cover` varchar(500) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `last_login` timestamp NULL DEFAULT NULL,
  `is_verified` tinyint(1) NOT NULL DEFAULT 0,
  `verification_token` varchar(255) DEFAULT NULL,
  `verification_expires` datetime DEFAULT NULL,
  `reset_token` varchar(64) DEFAULT NULL,
  `reset_expires` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_firebase_uid` (`firebase_uid`),
  UNIQUE KEY `uniq_email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `admins` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `phone_number` varchar(20) DEFAULT NULL,
  `username` varchar(50) NOT NULL,
  `email` varchar(100) NOT NULL,
  `password` varchar(255) NOT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `username` (`username`),
  UNIQUE KEY `email` (`email`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

CREATE TABLE `products` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `description` text DEFAULT NULL,
  `category` varchar(100) DEFAULT NULL,
  `price` decimal(10,2) NOT NULL,
  `image_path` varchar(255) NOT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

CREATE TABLE `delivery_settings` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `fuel_cost_per_liter` decimal(10,2) DEFAULT 2500.00,
  `vehicle_km_per_liter` decimal(10,2) DEFAULT 10.00,
  `labor_cost_per_hour` decimal(10,2) DEFAULT 2000.00,
  `base_delivery_fee` decimal(10,2) DEFAULT 500.00,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

CREATE TABLE `settings` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `fuel_cost_per_liter` decimal(10,2) DEFAULT 2500.00,
  `vehicle_km_per_liter` decimal(10,2) DEFAULT 10.00,
  `labor_cost_per_hour` decimal(10,2) DEFAULT 2000.00,
  `base_delivery_fee` decimal(10,2) DEFAULT 500.00,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

CREATE TABLE `orders` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `status` varchar(50) NOT NULL,
  `payment_status` enum('pending','paid','failed','refunded') DEFAULT 'pending',
  `payment_method` varchar(50) DEFAULT NULL COMMENT 'cash, mobile, card',
  `total_amount` decimal(10,2) NOT NULL,
  `subtotal` decimal(10,2) DEFAULT NULL,
  `delivery_fee` decimal(10,2) DEFAULT NULL,
  `service_fee` decimal(10,2) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `admin_id` int(10) unsigned DEFAULT NULL,
  `latitude` decimal(10,8) DEFAULT NULL,
  `longitude` decimal(11,8) DEFAULT NULL,
  `address` varchar(255) DEFAULT NULL,
  `customer_name` varchar(255) DEFAULT NULL,
  `customer_phone` varchar(20) DEFAULT NULL,
  `customer_email` varchar(255) DEFAULT NULL,
  `place_description` text DEFAULT NULL,
  `order_tracking_id` varchar(50) DEFAULT NULL,
  `payment_transaction_id` varchar(255) DEFAULT NULL COMMENT 'Links to transactions.transaction_id',
  PRIMARY KEY (`id`),
  KEY `fk_orders_users` (`user_id`),
  KEY `fk_orders_admin` (`admin_id`),
  KEY `idx_orders_tracking_id` (`order_tracking_id`),
  KEY `idx_payment_transaction_id` (`payment_transaction_id`),
  KEY `idx_payment_status` (`payment_status`),
  KEY `idx_user_id` (`user_id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

CREATE TABLE `order_items` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `order_id` bigint(20) unsigned NOT NULL COMMENT 'References orders.id',
  `product_id` int(11) NOT NULL COMMENT 'References products.id',
  `product_name` varchar(255) NOT NULL,
  `quantity` int(11) NOT NULL,
  `unit_price` decimal(10,2) NOT NULL,
  `subtotal` decimal(10,2) NOT NULL COMMENT 'quantity * unit_price',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_order_id` (`order_id`),
  KEY `idx_product_id` (`product_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `transactions` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `transaction_id` varchar(255) NOT NULL,
  `user_id` int(11) DEFAULT NULL,
  `user_email` varchar(255) DEFAULT NULL,
  `phone_number` varchar(20) DEFAULT NULL COMMENT 'Customer phone for mobile money',
  `first_name` varchar(100) DEFAULT NULL,
  `last_name` varchar(100) DEFAULT NULL,
  `amount` decimal(10,2) DEFAULT NULL,
  `method` varchar(50) DEFAULT NULL,
  `payment_provider` varchar(50) DEFAULT NULL COMMENT 'e.g., paychangu, stripe',
  `payment_mode` varchar(20) DEFAULT NULL COMMENT 'sandbox or live',
  `status` enum('pending','canceled','completed','received','success','failed') DEFAULT 'pending',
  `created_at` datetime DEFAULT current_timestamp(),
  `updated_at` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `product_id` int(11) DEFAULT NULL,
  `product_name` varchar(255) DEFAULT NULL,
  `quantity` int(11) DEFAULT NULL,
  `unit_price` bigint(20) DEFAULT NULL,
  `charge_id` varchar(50) DEFAULT NULL,
  `provider_reference` varchar(255) DEFAULT NULL COMMENT 'Provider transaction reference',
  `payment_response` text DEFAULT NULL COMMENT 'Full JSON response from payment provider',
  PRIMARY KEY (`id`),
  KEY `transaction_id` (`transaction_id`),
  KEY `idx_charge_id` (`charge_id`),
  KEY `idx_status` (`status`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

CREATE TABLE `temp_orders` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) DEFAULT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `name` varchar(255) DEFAULT NULL,
  `email` varchar(255) DEFAULT NULL,
  `latitude` decimal(10,8) DEFAULT NULL,
  `longitude` decimal(11,8) DEFAULT NULL,
  `address` text DEFAULT NULL,
  `cart_items` text DEFAULT NULL,
  `total_amount` decimal(10,2) DEFAULT NULL,
  `order_id` int(11) DEFAULT NULL,
  `order_tracking_id` varchar(50) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_user_id` (`user_id`),
  KEY `idx_email` (`email`),
  KEY `idx_order_id` (`order_id`),
  KEY `idx_order_tracking_id` (`order_tracking_id`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `promotions` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `promotion_name` varchar(255) NOT NULL,
  `promotion_price` decimal(10,2) NOT NULL DEFAULT 0.00,
  `promotion_type` varchar(50) NOT NULL DEFAULT 'general',
  `related_products` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`related_products`)),
  `usage_limit` int(11) DEFAULT NULL,
  `used_count` int(11) DEFAULT 0,
  `status` enum('active','inactive','expired') DEFAULT 'active',
  `created_by` int(11) DEFAULT NULL,
  `old_title` varchar(255) DEFAULT NULL,
  `description` text DEFAULT NULL,
  `image` varchar(500) DEFAULT NULL,
  `old_discount_percent` int(11) DEFAULT NULL,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `old_is_active` tinyint(1) DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `is_active` (`old_is_active`),
  KEY `date_range` (`start_date`,`end_date`),
  KEY `idx_promotion_type` (`promotion_type`),
  KEY `idx_status` (`status`),
  KEY `idx_created_by` (`created_by`),
  KEY `idx_usage_limit` (`usage_limit`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- RECREATE VIEWS
-- ============================================================

CREATE VIEW `order_details` AS
SELECT
  o.id AS order_id,
  o.order_tracking_id AS order_tracking_id,
  o.user_id AS user_id,
  o.customer_name AS customer_name,
  o.customer_email AS customer_email,
  o.customer_phone AS customer_phone,
  o.status AS order_status,
  o.payment_status AS payment_status,
  o.payment_method AS payment_method,
  o.subtotal AS subtotal,
  o.delivery_fee AS delivery_fee,
  o.service_fee AS service_fee,
  o.total_amount AS total_amount,
  o.address AS address,
  o.place_description AS place_description,
  o.latitude AS latitude,
  o.longitude AS longitude,
  o.payment_transaction_id AS payment_transaction_id,
  o.created_at AS created_at,
  o.updated_at AS updated_at,
  COUNT(oi.id) AS item_count,
  GROUP_CONCAT(CONCAT(oi.product_name, ' (x', oi.quantity, ')') SEPARATOR ', ') AS items_summary
FROM orders o
LEFT JOIN order_items oi ON o.id = oi.order_id
GROUP BY o.id
ORDER BY o.created_at DESC;

CREATE VIEW `payment_transactions` AS
SELECT
  t.id AS id,
  t.transaction_id AS transaction_id,
  t.charge_id AS charge_id,
  t.user_id AS user_id,
  t.user_email AS user_email,
  t.phone_number AS phone_number,
  CONCAT(t.first_name, ' ', t.last_name) AS customer_name,
  t.amount AS amount,
  t.method AS method,
  t.payment_provider AS payment_provider,
  t.payment_mode AS payment_mode,
  t.status AS status,
  t.created_at AS created_at,
  t.updated_at AS updated_at,
  t.provider_reference AS provider_reference
FROM transactions t
WHERE t.method IN ('mobile', 'card', 'bank_transfer')
ORDER BY t.created_at DESC;

-- ============================================================
-- OPTIONAL: Seed default settings (uncomment if needed)
-- ============================================================
-- INSERT INTO delivery_settings (fuel_cost_per_liter, vehicle_km_per_liter, labor_cost_per_hour, base_delivery_fee) VALUES (2500, 10, 2000, 500);
-- INSERT INTO settings (fuel_cost_per_liter, vehicle_km_per_liter, labor_cost_per_hour, base_delivery_fee) VALUES (2500, 10, 2000, 500);
