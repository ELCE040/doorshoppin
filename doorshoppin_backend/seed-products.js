import { connectToDatabase, query } from "./config/database.js";
import dotenv from "dotenv";

dotenv.config();

const sampleProducts = [
  {
    name: "5kg Rice",
    price: 6500,
    category: "Groceries",
    description: "Premium quality rice, perfect for family meals. 5kg bag.",
    image_path: "",
  },
  {
    name: "Cooking Oil 2L",
    price: 5200,
    category: "Groceries",
    description: "Pure vegetable cooking oil. 2 liter bottle.",
    image_path: "",
  },
  {
    name: "Sugar 2kg",
    price: 3200,
    category: "Groceries",
    description: "Fine white sugar. 2kg pack.",
    image_path: "",
  },
  {
    name: "Milk 1L",
    price: 1800,
    category: "Drinks",
    description: "Fresh whole milk. 1 liter carton.",
    image_path: "",
  },
  {
    name: "Bread Loaf",
    price: 1500,
    category: "Groceries",
    description: "Fresh white bread loaf.",
    image_path: "",
  },
  {
    name: "Laundry Soap",
    price: 2100,
    category: "Cleaning",
    description: "Bar soap for laundry. 500g.",
    image_path: "",
  },
  {
    name: "Coca Cola 500ml",
    price: 800,
    category: "Drinks",
    description: "Carbonated soft drink. 500ml bottle.",
    image_path: "",
  },
  {
    name: "Potatoes 5kg",
    price: 4500,
    category: "Groceries",
    description: "Fresh potatoes. 5kg bag.",
    image_path: "",
  },
  {
    name: "Onions 2kg",
    price: 2800,
    category: "Groceries",
    description: "Fresh onions. 2kg bag.",
    image_path: "",
  },
  {
    name: "Tomatoes 2kg",
    price: 3500,
    category: "Groceries",
    description: "Fresh ripe tomatoes. 2kg pack.",
    image_path: "",
  },
  {
    name: "Biscuits Pack",
    price: 1200,
    category: "Snacks",
    description: "Assorted biscuits. 400g pack.",
    image_path: "",
  },
  {
    name: "Detergent Powder 1kg",
    price: 3800,
    category: "Cleaning",
    description: "Laundry detergent powder. 1kg pack.",
    image_path: "",
  },
];

async function seedProducts() {
  try {
    console.log("🔄 Connecting to database...");
    await connectToDatabase();
    console.log("✅ Connected to database");

    // Check if products already exist
    const existingProducts = await query("SELECT COUNT(*) as count FROM products");
    if (existingProducts[0].count > 0) {
      console.log(`ℹ️  Found ${existingProducts[0].count} existing products. Skipping seed.`);
      console.log("   To re-seed, delete existing products first.");
      process.exit(0);
    }

    // Insert sample products
    console.log("📦 Inserting sample products...");
    
    const insertSql = `
      INSERT INTO products (name, description, category, price, image_path, created_at)
      VALUES (?, ?, ?, ?, ?, NOW())
    `;

    let insertedCount = 0;
    for (const product of sampleProducts) {
      await query(insertSql, [
        product.name,
        product.description,
        product.category,
        product.price,
        product.image_path,
      ]);
      insertedCount++;
    }

    console.log(`✅ Successfully inserted ${insertedCount} products`);

    // Display inserted products
    const insertedProducts = await query(
      "SELECT id, name, price, category FROM products ORDER BY id DESC LIMIT ?",
      [sampleProducts.length]
    );
    
    console.log("\n📋 Inserted Products:");
    insertedProducts.forEach((product, index) => {
      console.log(
        `${index + 1}. ${product.name} - MWK ${product.price} (${product.category})`
      );
    });

    console.log("\n✅ Seeding completed successfully!");
    process.exit(0);
  } catch (error) {
    console.error("❌ Error seeding products:", error);
    process.exit(1);
  }
}

seedProducts();
