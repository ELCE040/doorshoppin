import express from "express";
import { getDatabase, query } from "../config/database.js";
import { authenticate } from "../middleware/auth.middleware.js";

const router = express.Router();

function normalizeImagePath(value) {
  if (!value) return "";
  const raw = String(value).trim();
  if (!raw) return "";
  const pathOnly = raw.replace(/^https?:\/\/[^/]+/i, "");
  const filename = pathOnly.split("?")[0].split("/").pop();
  const lowerPath = pathOnly.toLowerCase();
  const hasImageExt = /\.(jpg|jpeg|png|webp|gif|avif)$/i.test(filename || "");
  const isKnownUpload =
    lowerPath.includes("/uploads/") ||
    lowerPath.includes("/admin/uploads/") ||
    /^product_\d+_[a-z0-9]+\.[a-z0-9]+$/i.test(filename || "") ||
    (hasImageExt && !pathOnly.slice(1).includes("/"));

  return isKnownUpload ? `/admin/uploads/${filename}` : raw;
}

async function getProductVendorMap(productIds) {
  const ids = [...new Set((productIds || []).map((id) => Number(id)).filter((id) => Number.isInteger(id) && id > 0))];
  const result = new Map(ids.map((id) => [id, []]));
  if (ids.length === 0) return result;

  const placeholders = ids.map(() => "?").join(",");
  const rows = await query(
    `SELECT
       pv.product_id as productId,
       pv.vendor_id as vendorId,
       pv.price,
       v.name as vendorName,
       v.type as vendorType,
       v.address as vendorAddress
     FROM product_vendors pv
     JOIN vendors v ON v.id = pv.vendor_id
     WHERE pv.product_id IN (${placeholders})
       AND pv.available = 1
       AND v.active = 1
     ORDER BY pv.price ASC, v.name ASC`,
    ids
  );

  for (const row of rows || []) {
    const productId = Number(row.productId);
    if (!result.has(productId)) result.set(productId, []);
    result.get(productId).push({
      vendorId: Number(row.vendorId),
      id: Number(row.vendorId),
      name: row.vendorName,
      type: row.vendorType || "store",
      address: row.vendorAddress || "",
      price: Number(row.price),
    });
  }
  return result;
}

async function attachVendorPrices(products) {
  const list = Array.isArray(products) ? products : [products].filter(Boolean);
  if (list.length === 0) return Array.isArray(products) ? [] : products;
  const vendorMap = await getProductVendorMap(list.map((p) => p.id));
  const normalized = list.map((product) => {
    const vendors = vendorMap.get(Number(product.id)) || [];
    const prices = vendors.map((vendor) => Number(vendor.price)).filter((price) => Number.isFinite(price));
    const lowestPrice = prices.length ? Math.min(...prices) : null;
    const highestPrice = prices.length ? Math.max(...prices) : null;
    return {
      ...product,
      imageUrl: normalizeImagePath(product.imageUrl ?? product.image_path),
      basePrice: Number(product.price),
      price: lowestPrice ?? Number(product.price),
      lowestPrice,
      highestPrice,
      vendorCount: vendors.length,
      vendors,
    };
  });

  return Array.isArray(products) ? normalized : normalized[0];
}

/* ----------------------------------------
   GET ALL PRODUCTS (with optional filters)
---------------------------------------- */
router.get("/", async (req, res) => {
  try {
    const { category, search, limit = 50, skip = 0 } = req.query;

    // Build WHERE clause
    let whereClause = "1=1";
    const params = [];

    if (category && category !== "all") {
      whereClause += " AND category = ?";
      params.push(category);
    }

    if (search) {
      whereClause += " AND (name LIKE ? OR description LIKE ?)";
      const searchTerm = `%${search}%`;
      params.push(searchTerm, searchTerm);
    }

    // Get products with pagination
    const sql = `
      SELECT id, name, description, category, price, image_path as imageUrl, created_at as createdAt
      FROM products
      WHERE ${whereClause}
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?
    `;
    params.push(parseInt(limit), parseInt(skip));

    const products = await query(sql, params);
    const productsWithVendors = await attachVendorPrices(products);

    // Get total count
    const countSql = `SELECT COUNT(*) as total FROM products WHERE ${whereClause}`;
    const countParams = params.slice(0, -2); // Remove limit and offset
    const [countResult] = await query(countSql, countParams);
    const total = countResult.total;

    res.json({
      success: true,
      data: productsWithVendors,
      pagination: {
        total,
        limit: parseInt(limit),
        skip: parseInt(skip),
        hasMore: parseInt(skip) + products.length < total,
      },
    });
  } catch (error) {
    console.error("Error fetching products:", error);
    res.status(500).json({
      success: false,
      error: "Failed to fetch products",
      message: error.message,
    });
  }
});

/* ----------------------------------------
   GET PRODUCTS BY CATEGORY
---------------------------------------- */
router.get("/category/:category", async (req, res) => {
  try {
    const { category } = req.params;
    const { limit = 50, skip = 0 } = req.query;

    const sql = `
      SELECT id, name, description, category, price, image_path as imageUrl, created_at as createdAt
      FROM products
      WHERE category = ?
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?
    `;

    const products = await query(sql, [category, parseInt(limit), parseInt(skip)]);
    const productsWithVendors = await attachVendorPrices(products);

    const [countResult] = await query(
      "SELECT COUNT(*) as total FROM products WHERE category = ?",
      [category]
    );
    const total = countResult.total;

    res.json({
      success: true,
      data: productsWithVendors,
      pagination: {
        total,
        limit: parseInt(limit),
        skip: parseInt(skip),
        hasMore: parseInt(skip) + products.length < total,
      },
    });
  } catch (error) {
    console.error("Error fetching products by category:", error);
    res.status(500).json({
      success: false,
      error: "Failed to fetch products",
      message: error.message,
    });
  }
});

/* ----------------------------------------
   SEARCH PRODUCTS
---------------------------------------- */
router.get("/search/:query", async (req, res) => {
  try {
    const { query: searchQuery } = req.params;
    const { limit = 50, skip = 0 } = req.query;

    const searchTerm = `%${searchQuery}%`;
    const sql = `
      SELECT id, name, description, category, price, image_path as imageUrl, created_at as createdAt
      FROM products
      WHERE name LIKE ? OR description LIKE ?
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?
    `;

    const products = await query(sql, [searchTerm, searchTerm, parseInt(limit), parseInt(skip)]);
    const productsWithVendors = await attachVendorPrices(products);

    const [countResult] = await query(
      "SELECT COUNT(*) as total FROM products WHERE name LIKE ? OR description LIKE ?",
      [searchTerm, searchTerm]
    );
    const total = countResult.total;

    res.json({
      success: true,
      data: productsWithVendors,
      pagination: {
        total,
        limit: parseInt(limit),
        skip: parseInt(skip),
        hasMore: parseInt(skip) + products.length < total,
      },
    });
  } catch (error) {
    console.error("Error searching products:", error);
    res.status(500).json({
      success: false,
      error: "Failed to search products",
      message: error.message,
    });
  }
});

/* ----------------------------------------
   GET PRODUCT BY ID
---------------------------------------- */
router.get("/:id", async (req, res) => {
  try {
    const { id } = req.params;

    const sql = `
      SELECT id, name, description, category, price, image_path as imageUrl, created_at as createdAt
      FROM products
      WHERE id = ?
    `;

    const products = await query(sql, [id]);

    if (products.length === 0) {
      return res.status(404).json({
        success: false,
        error: "Product not found",
      });
    }

    res.json({
      success: true,
      data: await attachVendorPrices(products[0]),
    });
  } catch (error) {
    console.error("Error fetching product:", error);
    res.status(500).json({
      success: false,
      error: "Failed to fetch product",
      message: error.message,
    });
  }
});

/* ----------------------------------------
   GET PRODUCTS BY CATEGORY
---------------------------------------- */
router.get("/category/:category", async (req, res) => {
  try {
    const { category } = req.params;
    const { limit = 50, skip = 0 } = req.query;

    const sql = `
      SELECT id, name, description, category, price, image_path as imageUrl, created_at as createdAt
      FROM products
      WHERE category = ?
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?
    `;

    const products = await query(sql, [category, parseInt(limit), parseInt(skip)]);
    const productsWithVendors = await attachVendorPrices(products);

    // Get total count
    const [countResult] = await query(
      "SELECT COUNT(*) as total FROM products WHERE category = ?",
      [category]
    );
    const total = countResult.total;

    res.json({
      success: true,
      data: productsWithVendors,
      pagination: {
        total,
        limit: parseInt(limit),
        skip: parseInt(skip),
        hasMore: parseInt(skip) + products.length < total,
      },
    });
  } catch (error) {
    console.error("Error fetching products by category:", error);
    res.status(500).json({
      success: false,
      error: "Failed to fetch products",
      message: error.message,
    });
  }
});

/* ----------------------------------------
   SEARCH PRODUCTS
---------------------------------------- */
router.get("/search/:query", async (req, res) => {
  try {
    const { query: searchQuery } = req.params;
    const { limit = 50, skip = 0 } = req.query;

    const searchTerm = `%${searchQuery}%`;
    const sql = `
      SELECT id, name, description, category, price, image_path as imageUrl, created_at as createdAt
      FROM products
      WHERE name LIKE ? OR description LIKE ?
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?
    `;

    const products = await query(sql, [searchTerm, searchTerm, parseInt(limit), parseInt(skip)]);
    const productsWithVendors = await attachVendorPrices(products);

    // Get total count
    const [countResult] = await query(
      "SELECT COUNT(*) as total FROM products WHERE name LIKE ? OR description LIKE ?",
      [searchTerm, searchTerm]
    );
    const total = countResult.total;

    res.json({
      success: true,
      data: productsWithVendors,
      pagination: {
        total,
        limit: parseInt(limit),
        skip: parseInt(skip),
        hasMore: parseInt(skip) + products.length < total,
      },
    });
  } catch (error) {
    console.error("Error searching products:", error);
    res.status(500).json({
      success: false,
      error: "Failed to search products",
      message: error.message,
    });
  }
});

/* ----------------------------------------
   GET RELATED PRODUCTS (by category)
---------------------------------------- */
router.get("/:id/related", async (req, res) => {
  try {
    const { id } = req.params;
    const { limit = 4 } = req.query;

    // First get the product to find its category
    const productSql = "SELECT category FROM products WHERE id = ?";
    const products = await query(productSql, [id]);

    if (products.length === 0) {
      return res.status(404).json({
        success: false,
        error: "Product not found",
      });
    }

    const category = products[0].category;

    // Get related products (same category, excluding current product)
    const relatedSql = `
      SELECT id, name, description, category, price, image_path as imageUrl, created_at as createdAt
      FROM products
      WHERE category = ? AND id != ?
      ORDER BY created_at DESC
      LIMIT ?
    `;

    const related = await query(relatedSql, [category, id, parseInt(limit)]);
    const relatedWithVendors = await attachVendorPrices(related);

    res.json({
      success: true,
      data: relatedWithVendors,
    });
  } catch (error) {
    console.error("Error fetching related products:", error);
    res.status(500).json({
      success: false,
      error: "Failed to fetch related products",
      message: error.message,
    });
  }
});

export default router;
