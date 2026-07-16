import bcrypt from "bcryptjs";
import { connectToDatabase, query } from "./config/database.js";
import dotenv from "dotenv";

dotenv.config();

const ADMIN_USERNAME = "admin";
const ADMIN_EMAIL = "admin@doorshoppin.com";
const ADMIN_PASSWORD = "123456";

async function seedAdmin() {
  try {
    console.log("🔄 Connecting to database...");
    await connectToDatabase();
    console.log("✅ Connected");

    const hashedPassword = await bcrypt.hash(ADMIN_PASSWORD, 10);
    console.log("🔐 Password hashed");

    await query(
      `INSERT INTO admins (username, email, password, created_at)
       VALUES (?, ?, ?, NOW())
       ON DUPLICATE KEY UPDATE password = VALUES(password), created_at = IF(created_at IS NULL, NOW(), created_at)`,
      [ADMIN_USERNAME, ADMIN_EMAIL, hashedPassword]
    );

    console.log("✅ Admin created/updated");
    console.log("   Username:", ADMIN_USERNAME);
    console.log("   Email:", ADMIN_EMAIL);
    console.log("   Password:", ADMIN_PASSWORD);
    process.exit(0);
  } catch (error) {
    console.error("❌ Error:", error.message);
    process.exit(1);
  }
}

seedAdmin();
