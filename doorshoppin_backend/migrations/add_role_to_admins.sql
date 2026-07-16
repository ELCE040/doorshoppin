-- Add role to admins: 'admin' (default) or 'manager'. Only manager can access HR (add/remove admins, change passwords).
ALTER TABLE `admins` ADD COLUMN `role` VARCHAR(20) NOT NULL DEFAULT 'admin' AFTER `password`;
-- Optional: set first admin as manager (uncomment and run if needed)
-- UPDATE admins SET role = 'manager' WHERE id = 1 LIMIT 1;
