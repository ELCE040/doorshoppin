<?php
/**
 * Run once: php gen_admin_php.php
 * Copy the SQL output and run it in phpMyAdmin to create admin (username: admin, password: 123456)
 */
$password = '123456';
$hash = password_hash($password, PASSWORD_BCRYPT);

$hashEscaped = addslashes($hash);

echo "-- Run this SQL in phpMyAdmin to create admin (username: admin, password: 123456)\n\n";
echo "INSERT INTO admins (username, email, password, created_at)\n";
echo "VALUES ('admin', 'admin@doorshoppin.com', '" . $hashEscaped . "', NOW());\n";
