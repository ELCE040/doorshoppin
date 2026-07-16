-- Restore sample products (same as seed-products.js)
-- Run this in phpMyAdmin if you emptied the products table by mistake.

INSERT INTO products (name, description, category, price, image_path, created_at) VALUES
('5kg Rice', 'Premium quality rice, perfect for family meals. 5kg bag.', 'Groceries', 6500, '', NOW()),
('Cooking Oil 2L', 'Pure vegetable cooking oil. 2 liter bottle.', 'Groceries', 5200, '', NOW()),
('Sugar 2kg', 'Fine white sugar. 2kg pack.', 'Groceries', 3200, '', NOW()),
('Milk 1L', 'Fresh whole milk. 1 liter carton.', 'Drinks', 1800, '', NOW()),
('Bread Loaf', 'Fresh white bread loaf.', 'Groceries', 1500, '', NOW()),
('Laundry Soap', 'Bar soap for laundry. 500g.', 'Cleaning', 2100, '', NOW()),
('Coca Cola 500ml', 'Carbonated soft drink. 500ml bottle.', 'Drinks', 800, '', NOW()),
('Potatoes 5kg', 'Fresh potatoes. 5kg bag.', 'Groceries', 4500, '', NOW()),
('Onions 2kg', 'Fresh onions. 2kg bag.', 'Groceries', 2800, '', NOW()),
('Tomatoes 2kg', 'Fresh ripe tomatoes. 2kg pack.', 'Groceries', 3500, '', NOW()),
('Biscuits Pack', 'Assorted biscuits. 400g pack.', 'Snacks', 1200, '', NOW()),
('Detergent Powder 1kg', 'Laundry detergent powder. 1kg pack.', 'Cleaning', 3800, '', NOW());
