-- Stores/restaurants that can sell products at different prices.
-- A vendor can be a grocery store, shop, restaurant, or any future seller type.

CREATE TABLE IF NOT EXISTS `vendors` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `type` varchar(32) NOT NULL DEFAULT 'store',
  `phone` varchar(50) DEFAULT NULL,
  `address` varchar(255) DEFAULT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_type_active` (`type`, `active`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

CREATE TABLE IF NOT EXISTS `product_vendors` (
  `product_id` int(11) NOT NULL,
  `vendor_id` int(11) NOT NULL,
  `price` decimal(10,2) NOT NULL,
  `available` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`product_id`, `vendor_id`),
  KEY `idx_vendor_id` (`vendor_id`),
  KEY `idx_product_price` (`product_id`, `price`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

-- Optional convenience seed. Delete or rename these from the admin app.
INSERT INTO `vendors` (`name`, `type`, `active`)
SELECT 'DoorShoppin Main Store', 'store', 1
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM `vendors` WHERE `name` = 'DoorShoppin Main Store');

-- Backfill existing products to the default store so current prices still appear as vendor prices.
INSERT IGNORE INTO `product_vendors` (`product_id`, `vendor_id`, `price`, `available`)
SELECT p.id, v.id, p.price, 1
FROM `products` p
JOIN `vendors` v ON v.name = 'DoorShoppin Main Store'
WHERE p.price IS NOT NULL;
