-- Create admin user: username "admin", password "123456"
-- Run in phpMyAdmin. Hash is PHP password_hash(PASSWORD_BCRYPT) so password_verify() works.

INSERT INTO admins (username, email, password, created_at)
VALUES (
  'admin',
  'admin@doorshoppin.com',
  '$2y$10$j1vZ0PCrpWtvbfIdQBEbS.P8YoOTpHwXBdmEWTmGYS0NAmmhWKUBa',
  NOW()
);

-- If you get "Duplicate entry" (username or email exists), update password only:
-- UPDATE admins SET password = '$2y$10$j1vZ0PCrpWtvbfIdQBEbS.P8YoOTpHwXBdmEWTmGYS0NAmmhWKUBa' WHERE username = 'admin';
