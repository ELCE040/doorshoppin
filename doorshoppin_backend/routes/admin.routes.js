import express from "express";
import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";
import path from "path";
import { fileURLToPath } from "url";
import { createRequire } from "module";
import { query } from "../config/database.js";
import { sendFcmNotification, sendFcmToAdminTopic } from "../config/firebase-admin.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const multerPath = path.join(__dirname, "..", "node_modules", "multer");
let multer;
try {
  multer = require(multerPath);
} catch (e) {
  console.error("[admin.routes] Multer not found at", multerPath);
  console.error("Run in the backend directory: npm install multer");
  throw e;
}

const router = express.Router();
const debug = (tag, ...args) => console.log(`[Admin ${tag}]`, ...args);

function safeJsonParse(value) {
  if (!value || typeof value !== "string") return null;
  try {
    return JSON.parse(value);
  } catch (_) {
    return null;
  }
}

function humanizePaymentOutcomeReason(reason, fallbackStatus) {
  switch (String(reason || "").toLowerCase()) {
    case "customer_cancelled":
      return "Customer cancelled in app";
    case "provider_cancelled":
      return "Cancelled by payment provider";
    case "provider_failed":
      return "Failed by payment provider";
    case "timed_out":
      return "Timed out waiting for payment";
    case "provider_pending":
      return "Still pending with provider";
    case "provider_success":
      return "Payment successful";
    default:
      switch (String(fallbackStatus || "").toLowerCase()) {
        case "canceled":
        case "cancelled":
          return "Cancelled";
        case "failed":
          return "Payment failed";
        case "pending":
          return "Payment pending";
        case "success":
        case "completed":
          return "Payment successful";
        default:
          return null;
      }
  }
}

function extractPaymentOutcome(row = {}) {
  const parsed = safeJsonParse(row.paymentResponse || row.payment_response);
  const outcome = parsed?.doorShoppinPayment || {};
  const reason = outcome.reason || null;
  const status = outcome.status || row.transactionStatus || row.transaction_status || null;
  return {
    paymentOutcomeStatus: status,
    paymentOutcomeReason: reason,
    paymentOutcomeSource: outcome.source || null,
    paymentOutcomeProviderStatus: outcome.providerStatus || row.transactionStatus || row.transaction_status || null,
    paymentOutcomeRecordedAt: outcome.recordedAt || null,
    paymentOutcomeLabel: humanizePaymentOutcomeReason(reason, status),
  };
}

function normalizeAdminImagePath(value) {
  if (!value) return "";
  const raw = String(value).trim();
  if (!raw) return "";
  const pathOnly = raw.replace(/^https?:\/\/[^/]+/i, "");
  const filename = path.basename(pathOnly.split("?")[0]);
  const lowerPath = pathOnly.toLowerCase();
  const hasImageExt = /\.(jpg|jpeg|png|webp|gif|avif)$/i.test(filename);
  const isKnownUpload =
    lowerPath.includes("/uploads/") ||
    lowerPath.includes("/admin/uploads/") ||
    /^product_\d+_[a-z0-9]+\.[a-z0-9]+$/i.test(filename) ||
    (hasImageExt && !pathOnly.slice(1).includes("/"));

  return isKnownUpload ? `/admin/uploads/${filename}` : raw;
}

function normalizeProductRow(row) {
  if (!row) return row;
  return {
    ...row,
    imageUrl: normalizeAdminImagePath(row.imageUrl ?? row.image_path),
  };
}

function normalizeVendorRow(row) {
  if (!row) return row;
  return {
    id: row.id,
    name: row.name,
    type: row.type || "store",
    phone: row.phone || "",
    address: row.address || "",
    active: row.active === true || row.active === 1,
    createdAt: row.createdAt || row.created_at || null,
    updatedAt: row.updatedAt || row.updated_at || null,
  };
}

async function getProductVendorMap(productIds, { includeInactive = false } = {}) {
  const ids = [...new Set((productIds || []).map((id) => Number(id)).filter((id) => Number.isInteger(id) && id > 0))];
  const result = new Map(ids.map((id) => [id, []]));
  if (ids.length === 0) return result;

  const placeholders = ids.map(() => "?").join(",");
  const activeClause = includeInactive ? "" : "AND v.active = 1 AND pv.available = 1";
  const rows = await query(
    `SELECT
       pv.product_id as productId,
       pv.vendor_id as vendorId,
       pv.price,
       pv.available,
       v.name as vendorName,
       v.type as vendorType,
       v.phone as vendorPhone,
       v.address as vendorAddress,
       v.active as vendorActive
     FROM product_vendors pv
     JOIN vendors v ON v.id = pv.vendor_id
     WHERE pv.product_id IN (${placeholders}) ${activeClause}
     ORDER BY pv.price ASC, v.name ASC`,
    ids
  );

  for (const row of rows || []) {
    const productId = Number(row.productId);
    const vendor = {
      productId,
      vendorId: Number(row.vendorId),
      id: Number(row.vendorId),
      name: row.vendorName,
      type: row.vendorType || "store",
      phone: row.vendorPhone || "",
      address: row.vendorAddress || "",
      price: Number(row.price),
      available: row.available === true || row.available === 1,
      active: row.vendorActive === true || row.vendorActive === 1,
    };
    if (!result.has(productId)) result.set(productId, []);
    result.get(productId).push(vendor);
  }

  return result;
}

async function attachVendorPrices(products, options = {}) {
  const list = Array.isArray(products) ? products : [products].filter(Boolean);
  if (list.length === 0) return Array.isArray(products) ? [] : products;
  const vendorMap = await getProductVendorMap(list.map((p) => p.id), options);
  const normalized = list.map((product) => {
    const vendors = vendorMap.get(Number(product.id)) || [];
    const prices = vendors
      .filter((vendor) => options.includeInactive || vendor.available)
      .map((vendor) => Number(vendor.price))
      .filter((price) => Number.isFinite(price));
    const lowestPrice = prices.length ? Math.min(...prices) : null;
    const highestPrice = prices.length ? Math.max(...prices) : null;
    const base = normalizeProductRow(product);

    return {
      ...base,
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

// Must match server.js uploadsDir so GET /uploads/xxx finds files we save here
const uploadsDir = process.env.ADMIN_UPLOADS_DIR
  ? path.resolve(process.env.ADMIN_UPLOADS_DIR)
  : path.join(__dirname, "..", "uploads");
try {
  const fs = require("fs");
  if (!fs.existsSync(uploadsDir)) {
    fs.mkdirSync(uploadsDir, { recursive: true });
    debug("Upload", "created uploads dir:", uploadsDir);
  }
} catch (e) {
  console.warn("[Admin] Could not ensure uploads dir exists:", e.message);
}
const upload = multer({
  storage: multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, uploadsDir),
    filename: (_req, file, cb) => {
      const ext = path.extname(file.originalname) || ".jpg";
      cb(null, `product_${Date.now()}_${Math.random().toString(36).slice(2)}${ext}`);
    },
  }),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const ext = path.extname(file.originalname || "").toLowerCase();
    const allowedExts = new Set([".jpg", ".jpeg", ".png", ".webp", ".gif", ".avif"]);
    const allowedMimes = new Set([
      "image/jpeg",
      "image/png",
      "image/webp",
      "image/gif",
      "image/avif",
    ]);
    if (!allowedExts.has(ext) || !allowedMimes.has(file.mimetype)) {
      return cb(new Error("Only image uploads are allowed"));
    }
    return cb(null, true);
  },
});

function uploadSingleImage(req, res, next) {
  upload.single("image")(req, res, (err) => {
    if (err) {
      return res.status(400).json({ success: false, error: err.message || "Upload failed" });
    }
    return next();
  });
}

/** Admin-only auth: verify JWT with adminId (from admin login). No dependency on auth.middleware.js. */
function authenticateAdmin(req, res, next) {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader) {
      return res.status(401).json({ success: false, error: "Admin authorization required" });
    }
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : authHeader;
    if (!token) {
      return res.status(401).json({ success: false, error: "Invalid authorization header" });
    }
    const secret = process.env.JWT_SECRET;
    const decoded = jwt.verify(token, secret);
    if (!decoded.adminId) {
      return res.status(401).json({ success: false, error: "Invalid token: admin only" });
    }
    req.adminId = decoded.adminId;
    req.adminUsername = decoded.username;
    next();
  } catch (err) {
    if (err.name === "JsonWebTokenError") {
      return res.status(401).json({ success: false, error: "Invalid token" });
    }
    if (err.name === "TokenExpiredError") {
      return res.status(401).json({ success: false, error: "Token expired" });
    }
    console.error("Admin auth error:", err);
    return res.status(500).json({ success: false, error: "Authentication error", message: err.message });
  }
}

/** Manager-only: same as admin but requires isManager in JWT (from admin login). */
function authenticateManager(req, res, next) {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader) {
      return res.status(401).json({ success: false, error: "Manager authorization required" });
    }
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : authHeader;
    if (!token) {
      return res.status(401).json({ success: false, error: "Invalid authorization header" });
    }
    const secret = process.env.JWT_SECRET;
    const decoded = jwt.verify(token, secret);
    if (!decoded.adminId) {
      return res.status(401).json({ success: false, error: "Invalid token: admin only" });
    }
    if (!decoded.isManager) {
      return res.status(403).json({ success: false, error: "Manager access only" });
    }
    req.adminId = decoded.adminId;
    req.adminUsername = decoded.username;
    next();
  } catch (err) {
    if (err.name === "JsonWebTokenError") {
      return res.status(401).json({ success: false, error: "Invalid token" });
    }
    if (err.name === "TokenExpiredError") {
      return res.status(401).json({ success: false, error: "Token expired" });
    }
    console.error("Manager auth error:", err);
    return res.status(500).json({ success: false, error: "Authentication error", message: err.message });
  }
}

/**
 * POST /api/admin/login
 * Body: { username, password } - username can be either username or email
 * Returns JWT with adminId for use in admin app.
 */
router.post("/login", async (req, res) => {
  const debug = (msg, ...args) => console.log("[Admin Login]", msg, ...args);
  try {
    const { username, password } = req.body || {};
    const login = (username && String(username).trim()) || "";
    debug("request body keys:", Object.keys(req.body || {}), "| login length:", login.length, "| password present:", !!password);

    if (!login || !password) {
      debug("reject: missing login or password");
      return res.status(400).json({ success: false, error: "Username and password required" });
    }

    debug("query admins for login:", login);
    const rows = await query(
      "SELECT id, username, email, password, COALESCE(role, 'admin') as role FROM admins WHERE username = ? OR email = ? LIMIT 1",
      [login, login]
    );
    debug("admins query result: row count =", rows?.length ?? 0);

    if (!rows || rows.length === 0) {
      debug("reject: no admin found for username/email:", login);
      return res.status(401).json({ success: false, error: "Invalid credentials" });
    }

    const admin = rows[0];
    debug("admin found id:", admin.id, "username:", admin.username);

    const match = await bcrypt.compare(password, admin.password);
    debug("bcrypt compare result:", match);

    if (!match) {
      debug("reject: password mismatch for admin id:", admin.id);
      return res.status(401).json({ success: false, error: "Invalid credentials" });
    }

    const isManager = String(admin.role || "admin").toLowerCase() === "manager";
    const token = jwt.sign(
      { adminId: admin.id, username: admin.username, isManager },
      process.env.JWT_SECRET,
      { expiresIn: "7d" }
    );
    debug("login success, admin id:", admin.id, "isManager:", isManager);
    return res.json({
      success: true,
      token,
      admin: { id: admin.id, username: admin.username, email: admin.email, isManager },
    });
  } catch (err) {
    console.error("[Admin Login] error:", err.message);
    console.error("[Admin Login] stack:", err.stack);
    return res.status(500).json({ success: false, error: "Login failed" });
  }
});

/**
 * GET /api/admin/me
 * Returns current admin profile including isManager (for app to fix missing role in login response).
 * Requires: Authorization: Bearer <token>
 */
router.get("/me", authenticateAdmin, async (req, res) => {
  try {
    const adminId = req.adminId;
    debug("Me", "GET adminId=", adminId);
    const rows = await query(
      "SELECT id, username, email, COALESCE(role, 'admin') as role FROM admins WHERE id = ? LIMIT 1",
      [adminId]
    );
    if (!rows || rows.length === 0) {
      return res.status(404).json({ success: false, error: "Admin not found" });
    }
    const admin = rows[0];
    const isManager = String(admin.role || "admin").toLowerCase() === "manager";
    debug("Me", "success id=", admin.id, "isManager=", isManager);
    return res.json({
      success: true,
      admin: { id: admin.id, username: admin.username, email: admin.email, isManager },
    });
  } catch (err) {
    console.error("[Admin Me] error:", err?.message);
    return res.status(500).json({ success: false, error: "Failed to load profile" });
  }
});

/**
 * GET /api/admin/dashboard
 * Returns dashboard stats: revenue, orders, users, categories, payment methods, transaction stats.
 * Requires: Authorization: Bearer <admin token>
 */
router.get("/dashboard", authenticateAdmin, async (req, res) => {
  try {
    debug("Dashboard", "GET adminId=", req.adminId);
    const today = new Date().toISOString().slice(0, 10);
    const weekStart = new Date();
    weekStart.setDate(weekStart.getDate() - weekStart.getDay() + (weekStart.getDay() === 0 ? -6 : 1));
    const weekStartStr = weekStart.toISOString().slice(0, 10);
    const monthStart = new Date().toISOString().slice(0, 7) + "-01";

    const revenueCondition = "(payment_status IN ('paid', 'pending') OR payment_method = 'cash')";

    const [revenueTodayRow] = await query(
      `SELECT COALESCE(SUM(total_amount), 0) as total FROM orders WHERE DATE(created_at) = ? AND ${revenueCondition}`,
      [today]
    );
    const [revenueWeekRow] = await query(
      `SELECT COALESCE(SUM(total_amount), 0) as total FROM orders WHERE DATE(created_at) >= ? AND ${revenueCondition}`,
      [weekStartStr]
    );
    const [revenueMonthRow] = await query(
      `SELECT COALESCE(SUM(total_amount), 0) as total FROM orders WHERE DATE(created_at) >= ? AND ${revenueCondition}`,
      [monthStart]
    );

    const [paidTodayRow] = await query(
      "SELECT COALESCE(SUM(total_amount), 0) as total FROM orders WHERE DATE(created_at) = ? AND payment_status = 'paid'",
      [today]
    );
    const [paidMonthRow] = await query(
      "SELECT COALESCE(SUM(total_amount), 0) as total FROM orders WHERE DATE(created_at) >= ? AND payment_status = 'paid'",
      [monthStart]
    );
    const [pendingRevenueRow] = await query(
      "SELECT COALESCE(SUM(total_amount), 0) as total FROM orders WHERE payment_status = 'pending'"
    );

    const ordersLabels = [];
    const ordersData = [];
    const revenueData = [];
    for (let i = 6; i >= 0; i--) {
      const d = new Date();
      d.setDate(d.getDate() - i);
      const dateStr = d.toISOString().slice(0, 10);
      const dayName = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getDay()];
      ordersLabels.push(dayName);
      const [oc] = await query("SELECT COUNT(*) as count FROM orders WHERE DATE(created_at) = ?", [dateStr]);
      ordersData.push(oc?.count ?? 0);
      const [rc] = await query(
        `SELECT COALESCE(SUM(total_amount), 0) as total FROM orders WHERE DATE(created_at) = ? AND ${revenueCondition}`,
        [dateStr]
      );
      revenueData.push(Number(rc?.total ?? 0));
    }

    const usersLabels = [];
    const usersData = [];
    for (let i = 6; i >= 0; i--) {
      const d = new Date();
      d.setDate(d.getDate() - i);
      const dateStr = d.toISOString().slice(0, 10);
      const dayName = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getDay()];
      usersLabels.push(dayName);
      const [uc] = await query("SELECT COUNT(*) as count FROM users WHERE DATE(created_at) = ?", [dateStr]);
      usersData.push(uc?.count ?? 0);
    }

    const productCategories = await query("SELECT category, COUNT(*) as count FROM products GROUP BY category");
    const categoryLabels = (productCategories || []).map((r) => r.category || "Unknown");
    const categoryData = (productCategories || []).map((r) => r.count ?? 0);

    const paymentMethods = await query(
      `SELECT payment_method, COUNT(*) as count, COALESCE(SUM(total_amount), 0) as total FROM orders WHERE DATE(created_at) >= ? GROUP BY payment_method`,
      [monthStart]
    );
    const paymentMethodLabels = (paymentMethods || []).map((r) => (r.payment_method ? String(r.payment_method).charAt(0).toUpperCase() + String(r.payment_method).slice(1) : "Unknown"));
    const paymentMethodData = (paymentMethods || []).map((r) => r.count ?? 0);

    const paymentStatusRows = await query(
      "SELECT payment_status, COUNT(*) as count, COALESCE(SUM(total_amount), 0) as total FROM orders GROUP BY payment_status"
    );
    const paymentStatusData = { paid: 0, pending: 0, failed: 0, refunded: 0 };
    for (const row of paymentStatusRows || []) {
      const k = String(row.payment_status || "").toLowerCase();
      if (paymentStatusData.hasOwnProperty(k)) paymentStatusData[k] = row.count ?? 0;
    }

    const orderStatusRows = await query("SELECT status, COUNT(*) as count FROM orders GROUP BY status");
    const orderStatusCounts = { pending: 0, processing: 0, out_for_delivery: 0, delivered: 0, cancelled: 0 };
    for (const row of orderStatusRows || []) {
      const k = String(row.status || "").toLowerCase().replace(/-/g, "_");
      if (orderStatusCounts.hasOwnProperty(k)) orderStatusCounts[k] = row.count ?? 0;
    }

    const [totalTx] = await query("SELECT COUNT(*) as count FROM transactions");
    const [successTx] = await query("SELECT COUNT(*) as count FROM transactions WHERE status IN ('success', 'completed')");
    const [pendingTx] = await query("SELECT COUNT(*) as count FROM transactions WHERE status = 'pending'");
    const [failedTx] = await query("SELECT COUNT(*) as count FROM transactions WHERE status = 'failed'");
    const [canceledTx] = await query("SELECT COUNT(*) as count FROM transactions WHERE status IN ('canceled', 'cancelled')");
    const paymentOutcomeRows = await query(
      `SELECT status as transactionStatus, payment_response as paymentResponse
       FROM transactions
       WHERE payment_response IS NOT NULL
       ORDER BY created_at DESC
       LIMIT 500`
    );
    const paymentOutcomeCounts = {
      customer_cancelled: 0,
      provider_cancelled: 0,
      provider_failed: 0,
      timed_out: 0,
      provider_pending: 0,
      provider_success: 0,
      unknown: 0,
    };
    for (const row of paymentOutcomeRows || []) {
      const outcome = extractPaymentOutcome(row);
      const key = outcome.paymentOutcomeReason || "unknown";
      paymentOutcomeCounts[key] = (paymentOutcomeCounts[key] || 0) + 1;
    }

    debug("Dashboard", "success");
    return res.json({
      success: true,
      data: {
        revenueToday: Number(revenueTodayRow?.total ?? 0),
        revenueWeek: Number(revenueWeekRow?.total ?? 0),
        revenueMonth: Number(revenueMonthRow?.total ?? 0),
        paidRevenueToday: Number(paidTodayRow?.total ?? 0),
        paidRevenueMonth: Number(paidMonthRow?.total ?? 0),
        pendingRevenue: Number(pendingRevenueRow?.total ?? 0),
        ordersLabels,
        ordersData,
        revenueData,
        usersLabels,
        usersData,
        categoryLabels,
        categoryData,
        paymentMethodLabels,
        paymentMethodData,
        paymentStatusData,
        orderStatusCounts,
        totalTransactions: totalTx?.count ?? 0,
        successfulTransactions: successTx?.count ?? 0,
        pendingTransactions: pendingTx?.count ?? 0,
        failedTransactions: failedTx?.count ?? 0,
        canceledTransactions: canceledTx?.count ?? 0,
        paymentOutcomeCounts,
        ordersLast7: ordersData.reduce((a, b) => a + b, 0),
        usersLast7: usersData.reduce((a, b) => a + b, 0),
        totalProducts: categoryData.reduce((a, b) => a + b, 0),
      },
    });
  } catch (err) {
    console.error("Admin dashboard error:", err);
    return res.status(500).json({ success: false, error: "Failed to load dashboard" });
  }
});

/**
 * GET /api/admin/orders
 * Returns all orders with items summary (for admin app). No auth required for now; add middleware if needed.
 */
router.get("/orders", authenticateAdmin, async (req, res) => {
  try {
    debug("Orders", "GET list");
    const ordersRows = await query(
      `SELECT 
        o.id, o.user_id as userId, o.status, o.payment_status as paymentStatus, o.payment_method as paymentMethod,
        o.payment_transaction_id as paymentTransactionId,
        o.total_amount as totalAmount, o.subtotal, o.delivery_fee as deliveryFee, o.service_fee as serviceFee,
        o.latitude, o.longitude, o.address, o.place_description as placeDescription,
        o.customer_name as customerName, o.customer_phone as customerPhone, o.customer_email as customerEmail,
        o.order_tracking_id as orderTrackingId, o.created_at as createdAt, o.admin_id as adminId,
        t.status as transactionStatus,
        t.provider_reference as paymentProviderReference,
        t.payment_response as paymentResponse
      FROM orders o
      LEFT JOIN transactions t
        ON t.charge_id = o.payment_transaction_id
        OR t.transaction_id = o.payment_transaction_id
      ORDER BY o.created_at DESC`
    );
    const orders = [];
    for (const row of ordersRows) {
      const items = await query(
        "SELECT product_id as productId, product_name as productName, quantity, unit_price as unitPrice, subtotal FROM order_items WHERE order_id = ? ORDER BY id",
        [row.id]
      );
      const {
        paymentResponse,
        ...safeRow
      } = row;
      orders.push({
        ...safeRow,
        ...extractPaymentOutcome(row),
        items: items || [],
      });
    }
    debug("Orders", "success count=", orders.length);
    return res.json({ success: true, data: orders });
  } catch (err) {
    console.error("Admin orders list error:", err);
    return res.status(500).json({ success: false, error: "Failed to fetch orders" });
  }
});

/**
 * GET /api/admin/transactions
 * Returns recent payment attempts with DoorShoppin outcome reason.
 */
router.get("/transactions", authenticateAdmin, async (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit, 10) || 100, 500);
    const rows = await query(
      `SELECT
        id,
        transaction_id as transactionId,
        charge_id as chargeId,
        user_email as userEmail,
        phone_number as phoneNumber,
        first_name as firstName,
        last_name as lastName,
        amount,
        method,
        payment_provider as paymentProvider,
        payment_mode as paymentMode,
        status as transactionStatus,
        provider_reference as paymentProviderReference,
        payment_response as paymentResponse,
        created_at as createdAt,
        updated_at as updatedAt
      FROM transactions
      ORDER BY created_at DESC
      LIMIT ?`,
      [limit]
    );

    const data = (rows || []).map((row) => {
      const { paymentResponse, ...safeRow } = row;
      return {
        ...safeRow,
        ...extractPaymentOutcome(row),
      };
    });

    return res.json({ success: true, data });
  } catch (err) {
    console.error("Admin transactions list error:", err);
    return res.status(500).json({ success: false, error: "Failed to fetch transactions" });
  }
});

const ORDER_STATUSES = ["pending", "processing", "out_for_delivery", "delivered", "cancelled"];

/**
 * PATCH /api/admin/orders/:id/status
 * Body: { status }
 * Updates order status and sends FCM notification to the order owner (customer).
 * Requires: Authorization Bearer (admin token).
 */
router.patch("/orders/:id/status", authenticateAdmin, async (req, res) => {
  try {
    const id = req.params.id;
    const { status } = req.body || {};
    debug("OrderStatus", "PATCH id=", id, "status=", status, "adminId=", req.adminId);
    if (!status || !ORDER_STATUSES.includes(status)) {
      return res.status(400).json({
        success: false,
        error: `Status must be one of: ${ORDER_STATUSES.join(", ")}`,
      });
    }

    let rows = await query(
      "SELECT id, user_id, customer_email, customer_phone, order_tracking_id, total_amount, payment_method FROM orders WHERE id = ?",
      [id]
    );
    if (rows.length === 0) {
      rows = await query(
        "SELECT id, user_id, customer_email, customer_phone, order_tracking_id, total_amount, payment_method FROM orders WHERE order_tracking_id = ?",
        [id]
      );
    }
    if (rows.length === 0) {
      return res.status(404).json({ success: false, error: "Order not found" });
    }

    const order = rows[0];
    const orderId = order.id;

    await query("UPDATE orders SET status = ?, updated_at = NOW() WHERE id = ?", [status, orderId]);

    if (status === "delivered" && (order.payment_method || "").toLowerCase() === "cash") {
      await query("UPDATE orders SET payment_status = 'paid' WHERE id = ?", [orderId]);
    }

    const tracking = order.order_tracking_id || `#${orderId}`;
    const total = order.total_amount != null ? String(order.total_amount) : "";

    // Normalise phone so 265991234567, 0991234567, 991234567 all match
    const normalizePhone = (p) => {
      if (!p) return null;
      const digits = p.replace(/\D/g, "");
      if (digits.startsWith("265") && digits.length >= 12) return digits.slice(3);
      if (digits.startsWith("0") && digits.length >= 9) return digits.slice(1);
      return digits;
    };

    let fcmToken = null;

    // 1. By user_id - skip guest (id=1)
    const uid = Number(order.user_id);
    if (!isNaN(uid) && uid > 1) {
      const userRows = await query(
        "SELECT fcm_token FROM users WHERE id = ? AND fcm_token IS NOT NULL AND fcm_token != ''",
        [uid]
      );
      if (userRows.length > 0) fcmToken = userRows[0].fcm_token;
    }

    // 2. By email
    if (!fcmToken && order.customer_email) {
      const userRows = await query(
        "SELECT fcm_token FROM users WHERE email = ? AND fcm_token IS NOT NULL AND fcm_token != '' LIMIT 1",
        [order.customer_email.trim().toLowerCase()]
      );
      if (userRows.length > 0) fcmToken = userRows[0].fcm_token;
    }

    // 3. By phone - all normalised variants
    if (!fcmToken && order.customer_phone) {
      const raw = order.customer_phone.replace(/\D/g, "");
      const local = normalizePhone(raw);
      const withCC = "265" + local;
      const withZero = "0" + local;
      const userRows = await query(
        `SELECT fcm_token FROM users
         WHERE fcm_token IS NOT NULL AND fcm_token != ''
           AND (phone = ? OR phone = ? OR phone = ? OR phone = ? OR phone = ?)
         LIMIT 1`,
        [raw, local, withCC, withZero, "+" + withCC]
      );
      if (userRows.length > 0) fcmToken = userRows[0].fcm_token;
    }

    console.log(`[FCM] Admin status update order ${orderId} -> token ${fcmToken ? "FOUND" : "NOT FOUND"}`);

    const statusMessages = {
      pending:          { title: "Order Received",   body: `Your order ${tracking} has been received.` },
      processing:       { title: "Order Processing", body: `Your order ${tracking} is being prepared.` },
      out_for_delivery: { title: "Out for Delivery", body: `Your order ${tracking} is on its way!` },
      delivered:        { title: "Order Delivered",  body: `Your order ${tracking} has been delivered. Thank you!` },
      cancelled:        { title: "Order Cancelled",  body: `Your order ${tracking} has been cancelled.` },
    };
    const msg = statusMessages[status] || {
      title: "Order Update",
      body: `Your order ${tracking} status: ${status.replace(/_/g, " ")}.`,
    };

    if (fcmToken) {
      await sendFcmNotification(fcmToken, msg.title, msg.body, {
        type: "order_status_update",
        orderId: String(orderId),
        orderTrackingId: String(tracking),
        status: String(status),
      });
      debug("OrderStatus", "FCM sent to customer orderId=", orderId);
    } else {
      debug("OrderStatus", "no FCM token for customer orderId=", orderId);
    }

    return res.json({
      success: true,
      message: "Order status updated",
      data: { orderId, orderTrackingId: tracking, status },
    });
  } catch (err) {
    console.error("[Admin] PATCH order status error:", err?.message);
    return res.status(500).json({ success: false, error: "Failed to update order status" });
  }
});

/**
 * POST /api/admin/order-status
 * Body: { orderId, orderTrackingId, status, total, adminName }
 * Sends an FCM notification to all admin devices (admin_orders topic).
 */
router.post("/order-status", authenticateAdmin, async (req, res) => {
  try {
    const { orderId, orderTrackingId, status, total, adminName } = req.body || {};

    if (!orderId || !status) {
      return res.status(400).json({
        success: false,
        error: "orderId and status are required",
      });
    }

    const tracking = orderTrackingId || orderId;
    const title =
      status === "processing"
        ? `Order #${tracking} accepted`
        : `Order #${tracking} status: ${status}`;
    const body =
      status === "processing"
        ? `Order #${tracking} accepted by ${adminName || "admin"}. Total MWK ${total ?? "0"}.`
        : `Order #${tracking} updated to ${status}. Total MWK ${total ?? "0"}.`;

    await sendFcmToAdminTopic(title, body, {
      type: "admin_order_status",
      orderId: String(orderId),
      orderTrackingId: String(tracking),
      status: String(status),
      total: String(total ?? ""),
      adminName: String(adminName ?? ""),
    });

    return res.json({ success: true });
  } catch (err) {
    console.error("Admin order-status FCM error:", err);
    return res.status(500).json({ success: false, error: "FCM send failed" });
  }
});

/* ----------------------------------------
   ADMIN VENDORS: stores and restaurants
---------------------------------------- */
router.get("/vendors", authenticateAdmin, async (req, res) => {
  try {
    const { type, includeInactive } = req.query;
    const where = [];
    const params = [];
    if (type && type !== "all") {
      where.push("type = ?");
      params.push(String(type).toLowerCase());
    }
    if (includeInactive !== "true") {
      where.push("active = 1");
    }
    const whereSql = where.length ? `WHERE ${where.join(" AND ")}` : "";
    const rows = await query(
      `SELECT id, name, type, phone, address, active, created_at as createdAt, updated_at as updatedAt
       FROM vendors
       ${whereSql}
       ORDER BY active DESC, type ASC, name ASC`,
      params
    );
    return res.json({ success: true, data: (rows || []).map(normalizeVendorRow) });
  } catch (err) {
    console.error("Admin vendors list error:", err);
    return res.status(500).json({ success: false, error: "Failed to fetch vendors" });
  }
});

router.post("/vendors", authenticateAdmin, async (req, res) => {
  try {
    const { name, type = "store", phone = "", address = "" } = req.body || {};
    const vendorName = String(name || "").trim();
    const vendorType = String(type || "store").trim().toLowerCase();
    if (!vendorName) {
      return res.status(400).json({ success: false, error: "name is required" });
    }
    if (!["store", "restaurant"].includes(vendorType)) {
      return res.status(400).json({ success: false, error: "type must be store or restaurant" });
    }

    const result = await query(
      "INSERT INTO vendors (name, type, phone, address, active) VALUES (?, ?, ?, ?, 1)",
      [vendorName, vendorType, String(phone).trim(), String(address).trim()]
    );
    const rows = await query(
      "SELECT id, name, type, phone, address, active, created_at as createdAt, updated_at as updatedAt FROM vendors WHERE id = ?",
      [result.insertId]
    );
    return res.status(201).json({ success: true, data: normalizeVendorRow(rows?.[0]) });
  } catch (err) {
    console.error("Admin vendor create error:", err);
    return res.status(500).json({ success: false, error: "Failed to create vendor" });
  }
});

router.put("/vendors/:id", authenticateAdmin, async (req, res) => {
  try {
    const id = Number(req.params.id);
    const { name, type, phone, address, active } = req.body || {};
    if (!Number.isInteger(id) || id < 1) {
      return res.status(400).json({ success: false, error: "Invalid vendor id" });
    }

    const updates = [];
    const values = [];
    if (name !== undefined) {
      const vendorName = String(name).trim();
      if (!vendorName) return res.status(400).json({ success: false, error: "name is required" });
      updates.push("name = ?");
      values.push(vendorName);
    }
    if (type !== undefined) {
      const vendorType = String(type).trim().toLowerCase();
      if (!["store", "restaurant"].includes(vendorType)) {
        return res.status(400).json({ success: false, error: "type must be store or restaurant" });
      }
      updates.push("type = ?");
      values.push(vendorType);
    }
    if (phone !== undefined) {
      updates.push("phone = ?");
      values.push(String(phone).trim());
    }
    if (address !== undefined) {
      updates.push("address = ?");
      values.push(String(address).trim());
    }
    if (active !== undefined) {
      updates.push("active = ?");
      values.push(active === true || active === 1 || active === "1" || active === "true" ? 1 : 0);
    }

    if (updates.length > 0) {
      updates.push("updated_at = NOW()");
      values.push(id);
      await query(`UPDATE vendors SET ${updates.join(", ")} WHERE id = ?`, values);
    }

    const rows = await query(
      "SELECT id, name, type, phone, address, active, created_at as createdAt, updated_at as updatedAt FROM vendors WHERE id = ?",
      [id]
    );
    if (!rows || rows.length === 0) {
      return res.status(404).json({ success: false, error: "Vendor not found" });
    }
    return res.json({ success: true, data: normalizeVendorRow(rows[0]) });
  } catch (err) {
    console.error("Admin vendor update error:", err);
    return res.status(500).json({ success: false, error: "Failed to update vendor" });
  }
});

router.delete("/vendors/:id", authenticateAdmin, async (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id < 1) {
      return res.status(400).json({ success: false, error: "Invalid vendor id" });
    }
    await query("UPDATE vendors SET active = 0, updated_at = NOW() WHERE id = ?", [id]);
    return res.json({ success: true, deleted: true, id });
  } catch (err) {
    console.error("Admin vendor delete error:", err);
    return res.status(500).json({ success: false, error: "Failed to remove vendor" });
  }
});

router.get("/products/:id/vendors", authenticateAdmin, async (req, res) => {
  try {
    const productId = Number(req.params.id);
    if (!Number.isInteger(productId) || productId < 1) {
      return res.status(400).json({ success: false, error: "Invalid product id" });
    }
    const vendorMap = await getProductVendorMap([productId], { includeInactive: true });
    return res.json({ success: true, data: vendorMap.get(productId) || [] });
  } catch (err) {
    console.error("Admin product vendors get error:", err);
    return res.status(500).json({ success: false, error: "Failed to fetch product vendors" });
  }
});

router.put("/products/:id/vendors", authenticateAdmin, async (req, res) => {
  try {
    const productId = Number(req.params.id);
    const vendorPrices = Array.isArray(req.body?.vendors) ? req.body.vendors : [];
    if (!Number.isInteger(productId) || productId < 1) {
      return res.status(400).json({ success: false, error: "Invalid product id" });
    }

    const productRows = await query("SELECT id FROM products WHERE id = ?", [productId]);
    if (!productRows || productRows.length === 0) {
      return res.status(404).json({ success: false, error: "Product not found" });
    }

    const clean = [];
    for (const entry of vendorPrices) {
      const vendorId = Number(entry.vendorId ?? entry.id);
      const price = Number(entry.price);
      const available = entry.available === false || entry.available === 0 || entry.available === "0" ? 0 : 1;
      if (!Number.isInteger(vendorId) || vendorId < 1) continue;
      if (!Number.isFinite(price) || price < 0) {
        return res.status(400).json({ success: false, error: "Vendor prices must be non-negative numbers" });
      }
      clean.push({ vendorId, price, available });
    }

    await query("DELETE FROM product_vendors WHERE product_id = ?", [productId]);
    for (const entry of clean) {
      await query(
        `INSERT INTO product_vendors (product_id, vendor_id, price, available, updated_at)
         VALUES (?, ?, ?, ?, NOW())`,
        [productId, entry.vendorId, entry.price, entry.available]
      );
    }

    if (clean.length > 0) {
      const lowest = Math.min(...clean.filter((v) => v.available).map((v) => v.price));
      if (Number.isFinite(lowest)) {
        await query("UPDATE products SET price = ? WHERE id = ?", [lowest, productId]);
      }
    }

    const vendorMap = await getProductVendorMap([productId], { includeInactive: true });
    return res.json({ success: true, data: vendorMap.get(productId) || [] });
  } catch (err) {
    console.error("Admin product vendors update error:", err);
    return res.status(500).json({ success: false, error: "Failed to update product vendors" });
  }
});

/**
 * POST /api/admin/upload
 * Multipart form: field name "image" (file from device).
 * Returns { success: true, path: "/admin/uploads/filename" } for use as product image_path.
 */
router.post("/upload", authenticateAdmin, uploadSingleImage, (req, res) => {
  try {
    if (!req.file) {
      debug("Upload", "no file");
      return res.status(400).json({ success: false, error: "No image file (field name must be 'image')" });
    }
    const pathUrl = "/admin/uploads/" + req.file.filename;
    debug("Upload", "success adminId=", req.adminId, "path=", pathUrl);
    return res.json({ success: true, path: pathUrl });
  } catch (err) {
    console.error("Admin upload error:", err);
    return res.status(500).json({ success: false, error: "Upload failed" });
  }
});

/* ----------------------------------------
   ADMIN PRODUCTS: load list
   GET /api/admin/products
   Query: category, search, limit, skip
---------------------------------------- */
router.get("/products", async (req, res) => {
  try {
    const { category, search, limit = 50, skip = 0 } = req.query;
    debug("Products", "GET list category=", category, "search=", search ? "yes" : "no");
    let whereClause = "1=1";
    const params = [];
    if (category && category !== "all") {
      whereClause += " AND category = ?";
      params.push(category);
    }
    if (search) {
      whereClause += " AND (name LIKE ? OR description LIKE ?)";
      const term = `%${search}%`;
      params.push(term, term);
    }
    const sql = `
      SELECT id, name, description, category, price, image_path as imageUrl, created_at as createdAt
      FROM products
      WHERE ${whereClause}
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?
    `;
    params.push(parseInt(limit, 10), parseInt(skip, 10));
    const products = await query(sql, params);
    const [countResult] = await query(
      `SELECT COUNT(*) as total FROM products WHERE ${whereClause}`,
      params.slice(0, -2)
    );
    const total = countResult.total;
    debug("Products", "success count=", products.length, "total=", total);
    const productsWithVendors = await attachVendorPrices(products || [], { includeInactive: true });
    return res.json({
      success: true,
      data: productsWithVendors,
      pagination: {
        total,
        limit: parseInt(limit, 10),
        skip: parseInt(skip, 10),
        hasMore: parseInt(skip, 10) + products.length < total,
      },
    });
  } catch (err) {
    console.error("Admin products list error:", err);
    return res.status(500).json({ success: false, error: "Failed to fetch products" });
  }
});

/* ----------------------------------------
   ADMIN PRODUCTS: get one
   GET /api/admin/products/:id
---------------------------------------- */
router.get("/products/:id", async (req, res) => {
  try {
    const { id } = req.params;
    const rows = await query(
      "SELECT id, name, description, category, price, image_path as imageUrl, created_at as createdAt FROM products WHERE id = ?",
      [id]
    );
    if (rows.length === 0) {
      return res.status(404).json({ success: false, error: "Product not found" });
    }
    return res.json({ success: true, data: await attachVendorPrices(normalizeProductRow(rows[0]), { includeInactive: true }) });
  } catch (err) {
    console.error("Admin product get error:", err);
    return res.status(500).json({ success: false, error: "Failed to fetch product" });
  }
});

/* ----------------------------------------
   ADMIN PRODUCTS: create (upload)
   POST /api/admin/products
   Body: { name, description?, category?, price, image_path? }
   Requires: Authorization Bearer <admin JWT>
---------------------------------------- */
router.post("/products", authenticateAdmin, async (req, res) => {
  try {
    const { name, description, category, price, image_path } = req.body || {};
    if (!name || name.trim() === "" || price == null || price === "") {
      return res.status(400).json({
        success: false,
        error: "name and price are required",
      });
    }
    const priceNum = parseFloat(price);
    if (Number.isNaN(priceNum) || priceNum < 0) {
      return res.status(400).json({
        success: false,
        error: "price must be a non-negative number",
      });
    }
    const imagePath = image_path != null ? String(image_path).trim() : "";
    const insertResult = await query(
      "INSERT INTO products (name, description, category, price, image_path) VALUES (?, ?, ?, ?, ?)",
      [
        name.trim(),
        description != null ? String(description).trim() : "",
        category != null ? String(category).trim() : "",
        priceNum,
        imagePath,
      ]
    );
    const insertId = insertResult?.insertId;
    const rows = await query(
      "SELECT id, name, description, category, price, image_path as imageUrl, created_at as createdAt FROM products WHERE id = ?",
      [insertId]
    );
    const row = Array.isArray(rows) ? rows[0] : rows;
    const product = normalizeProductRow(row ?? null);
    if (product?.id) {
      await query(
        `INSERT INTO product_vendors (product_id, vendor_id, price, available, updated_at)
         SELECT ?, id, ?, 1, NOW()
         FROM vendors
         WHERE active = 1
         ORDER BY id ASC
         LIMIT 1`,
        [product.id, priceNum]
      );
    }
    return res.status(201).json({ success: true, data: await attachVendorPrices(product, { includeInactive: true }) });
  } catch (err) {
    console.error("Admin product create error:", err);
    return res.status(500).json({ success: false, error: "Failed to create product" });
  }
});

/* ----------------------------------------
  ADMIN PRODUCTS: update
  PUT /api/admin/products/:id
  Body: { name?, description?, category?, price?, image_path? }
  Requires: Authorization Bearer <admin JWT>
---------------------------------------- */
router.put("/products/:id", authenticateAdmin, uploadSingleImage, async (req, res) => {
  try {
    const { id } = req.params;
    const { name, description, category, price, image_path } = req.body || {};
    const bodyKeys = Object.keys(req.body || {}).filter((k) => req.body[k] !== undefined);
    const uploadedPath = req.file ? "/admin/uploads/" + req.file.filename : null;
    debug(
      "ProductUpdate",
      "PUT id=",
      id,
      "adminId=",
      req.adminId,
      "bodyKeys=",
      bodyKeys.join(","),
      "image_path=",
      image_path ? "yes" : "no",
      "file=",
      req.file ? req.file.originalname : "no"
    );
    const existingRows = await query("SELECT id FROM products WHERE id = ?", [id]);
    if (!existingRows || existingRows.length === 0) {
      return res.status(404).json({ success: false, error: "Product not found" });
    }
    const updates = [];
    const values = [];
    if (name !== undefined) {
      updates.push("name = ?");
      values.push(name.trim());
    }
    if (description !== undefined) {
      updates.push("description = ?");
      values.push(String(description).trim());
    }
    if (category !== undefined) {
      updates.push("category = ?");
      values.push(String(category).trim());
    }
    if (price !== undefined) {
      const priceNum = parseFloat(price);
      if (Number.isNaN(priceNum) || priceNum < 0) {
        return res.status(400).json({ success: false, error: "price must be a non-negative number" });
      }
      updates.push("price = ?");
      values.push(priceNum);
    }
    // If client uploaded a file, always use it and store relative URL path.
    if (uploadedPath) {
      updates.push("image_path = ?");
      values.push(uploadedPath);
    } else if (image_path !== undefined) {
      updates.push("image_path = ?");
      values.push(String(image_path).trim());
    }
    if (updates.length === 0) {
      const rows = await query(
        "SELECT id, name, description, category, price, image_path as imageUrl, created_at as createdAt FROM products WHERE id = ?",
        [id]
      );
      const row = Array.isArray(rows) ? rows[0] : rows;
      return res.json({ success: true, data: await attachVendorPrices(normalizeProductRow(row ?? null), { includeInactive: true }) });
    }
    values.push(id);
    await query(
      `UPDATE products SET ${updates.join(", ")} WHERE id = ?`,
      values
    );
    const rows = await query(
      "SELECT id, name, description, category, price, image_path as imageUrl, created_at as createdAt FROM products WHERE id = ?",
      [id]
    );
    const row = Array.isArray(rows) ? rows[0] : rows;
    debug("ProductUpdate", "success id=", id);
    return res.json({ success: true, data: await attachVendorPrices(normalizeProductRow(row ?? null), { includeInactive: true }) });
  } catch (err) {
    console.error("Admin product update error:", err);
    return res.status(500).json({ success: false, error: "Failed to update product" });
  }
});

/* ----------------------------------------
   ADMIN PRODUCTS: delete
   DELETE /api/admin/products/:id
   Requires: Authorization Bearer <admin JWT>
---------------------------------------- */
router.delete("/products/:id", authenticateAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    debug("ProductDelete", "DELETE id=", id, "adminId=", req.adminId);
    const existingRows = await query("SELECT id FROM products WHERE id = ?", [id]);
    if (!existingRows || existingRows.length === 0) {
      return res.status(404).json({ success: false, error: "Product not found" });
    }
    await query("DELETE FROM products WHERE id = ?", [id]);
    debug("ProductDelete", "success id=", id);
    return res.json({ success: true, deleted: true, id: parseInt(id, 10) });
  } catch (err) {
    console.error("Admin product delete error:", err);
    return res.status(500).json({ success: false, error: "Failed to delete product" });
  }
});

/* ----------------------------------------
   HR (manager only): list admins
   GET /api/admin/hr/admins
---------------------------------------- */
router.get("/hr/admins", authenticateManager, async (req, res) => {
  try {
    const rows = await query(
      "SELECT id, username, email, COALESCE(role, 'admin') as role, created_at as createdAt FROM admins ORDER BY id"
    );
    return res.json({ success: true, data: rows });
  } catch (err) {
    console.error("HR list admins error:", err);
    return res.status(500).json({ success: false, error: "Failed to list admins" });
  }
});

/* ----------------------------------------
   HR (manager only): add admin
   POST /api/admin/hr/admins
   Body: { username, email, password }
---------------------------------------- */
router.post("/hr/admins", authenticateManager, async (req, res) => {
  try {
    const { username, email, password } = req.body || {};
    if (!username || !email || !password) {
      return res.status(400).json({ success: false, error: "username, email and password required" });
    }
    const u = String(username).trim();
    const e = String(email).trim().toLowerCase();
    if (password.length < 6) {
      return res.status(400).json({ success: false, error: "Password must be at least 6 characters" });
    }
    const existing = await query("SELECT id FROM admins WHERE username = ? OR email = ?", [u, e]);
    if (existing.length > 0) {
      return res.status(400).json({ success: false, error: "Username or email already exists" });
    }
    const hashed = await bcrypt.hash(password, 10);
    await query(
      "INSERT INTO admins (username, email, password, role) VALUES (?, ?, ?, 'admin')",
      [u, e, hashed]
    );
    const [inserted] = await query(
      "SELECT id, username, email, COALESCE(role, 'admin') as role, created_at as createdAt FROM admins WHERE username = ?",
      [u]
    );
    return res.status(201).json({ success: true, data: inserted[0] });
  } catch (err) {
    console.error("HR add admin error:", err);
    return res.status(500).json({ success: false, error: "Failed to add admin" });
  }
});

/* ----------------------------------------
   HR (manager only): delete admin
   DELETE /api/admin/hr/admins/:id
---------------------------------------- */
router.delete("/hr/admins/:id", authenticateManager, async (req, res) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (id === req.adminId) {
      return res.status(400).json({ success: false, error: "Cannot delete yourself" });
    }
    const [rows] = await query("SELECT id, role FROM admins WHERE id = ?", [id]);
    if (rows.length === 0) {
      return res.status(404).json({ success: false, error: "Admin not found" });
    }
    if (String(rows[0].role).toLowerCase() === "manager") {
      return res.status(400).json({ success: false, error: "Cannot delete a manager" });
    }
    await query("DELETE FROM admins WHERE id = ?", [id]);
    return res.json({ success: true, deleted: true, id });
  } catch (err) {
    console.error("HR delete admin error:", err);
    return res.status(500).json({ success: false, error: "Failed to delete admin" });
  }
});

/* ----------------------------------------
   HR (manager only): change admin password
   PUT /api/admin/hr/admins/:id/password
   Body: { newPassword }
---------------------------------------- */
router.put("/hr/admins/:id/password", authenticateManager, async (req, res) => {
  try {
    const id = parseInt(req.params.id, 10);
    const { newPassword } = req.body || {};
    if (!newPassword || String(newPassword).length < 6) {
      return res.status(400).json({ success: false, error: "newPassword required (min 6 characters)" });
    }
    const [rows] = await query("SELECT id FROM admins WHERE id = ?", [id]);
    if (rows.length === 0) {
      return res.status(404).json({ success: false, error: "Admin not found" });
    }
    const hashed = await bcrypt.hash(String(newPassword), 10);
    await query("UPDATE admins SET password = ? WHERE id = ?", [hashed, id]);
    return res.json({ success: true });
  } catch (err) {
    console.error("HR change password error:", err);
    return res.status(500).json({ success: false, error: "Failed to change password" });
  }
});

/* ----------------------------------------
   HR (manager only): list app users (DoorShoppin registered users)
   GET /api/admin/hr/users
   Returns users from `users` table (created via FCM register or orders).
---------------------------------------- */
router.get("/hr/users", authenticateManager, async (req, res) => {
  try {
    const rows = await query(
      `SELECT id, email, phone, COALESCE(name, '') as name, created_at as createdAt,
       (fcm_token IS NOT NULL AND fcm_token != '') as hasFcmToken
       FROM users ORDER BY created_at DESC`
    );
    return res.json({ success: true, data: rows || [] });
  } catch (err) {
    console.error("HR list users error:", err);
    return res.status(500).json({ success: false, error: "Failed to list users" });
  }
});

/* ----------------------------------------
   HR (manager only): send notification to all app users
   POST /api/admin/notifications/broadcast
   Body: { title, body }
   Sends FCM to every user that has an fcm_token (DoorShoppin app receives it).
---------------------------------------- */
router.post("/notifications/broadcast", authenticateManager, async (req, res) => {
  try {
    const { title, body } = req.body || {};
    if (!title || !body) {
      return res.status(400).json({
        success: false,
        error: "title and body are required",
      });
    }
    const users = await query(
      "SELECT id, fcm_token FROM users WHERE fcm_token IS NOT NULL AND fcm_token != ''"
    );
    if (!users || users.length === 0) {
      return res.json({
        success: true,
        message: "No users with FCM token to notify",
        sent: 0,
        total: 0,
      });
    }
    let sent = 0;
    for (const u of users) {
      const ok = await sendFcmNotification(
        u.fcm_token,
        String(title).trim(),
        String(body).trim(),
        { type: "admin_broadcast" }
      );
      if (ok) sent++;
    }
    return res.json({
      success: true,
      message: `Notification sent to ${sent} of ${users.length} users`,
      sent,
      total: users.length,
    });
  } catch (err) {
    console.error("Admin broadcast notification error:", err);
    return res.status(500).json({ success: false, error: "Failed to send notification" });
  }
});

export default router;
