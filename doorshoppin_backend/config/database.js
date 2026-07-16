import mysql from "mysql2/promise";
import dotenv from "dotenv";

dotenv.config();

let pool = null;

/**
 * Create MySQL connection pool
 */
export async function connectToDatabase() {
  try {
    // If pool already exists, return it
    if (pool) {
      return pool;
    }

    // Create connection pool
    pool = mysql.createPool({
      host: process.env.DB_HOST || "localhost",
      port: process.env.DB_PORT || 3306,
      user: process.env.DB_USER || "root",
      password: process.env.DB_PASSWORD || "",
      database: process.env.DB_NAME || "doorbuvi_door_shopping",
      waitForConnections: true,
      connectionLimit: 10,
      queueLimit: 0,
      enableKeepAlive: true,
      keepAliveInitialDelay: 0,
    });

    // Test connection
    const connection = await pool.getConnection();
    await connection.ping();
    connection.release();

    console.log("✅ MySQL connection pool created");
    console.log(`✅ Connected to database: ${process.env.DB_NAME || "doorbuvi_door_shopping"}`);

    return pool;
  } catch (error) {
    console.error("❌ MySQL connection error:", error);
    throw error;
  }
}

/**
 * Get the database pool (connect if needed)
 */
export async function getDatabase() {
  if (pool) {
    return pool;
  }
  return await connectToDatabase();
}

/**
 * Close database connection pool
 */
export async function closeDatabase() {
  try {
    if (pool) {
      await pool.end();
      pool = null;
      console.log("🔌 MySQL connection pool closed.");
    }
  } catch (error) {
    console.error("❌ Error closing MySQL:", error);
  }
}

/**
 * Helper function to execute queries
 */
export async function query(sql, params = []) {
  const db = await getDatabase();
  const [results] = await db.execute(sql, params);
  return results;
}
