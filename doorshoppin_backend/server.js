import dotenv from "dotenv";
// Load .env first so process.env is set before any route modules read it (e.g. PAYCHANGU_SECRET_KEY)
dotenv.config();

import express from "express";
import cors from "cors";
import path from "path";
import fs from "fs";
import { fileURLToPath } from "url";
import { connectToDatabase } from "./config/database.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
// Same path as admin uploads (admin.routes.js) so GET /uploads/xxx serves files multer saved
const uploadsDir = process.env.ADMIN_UPLOADS_DIR
  ? path.resolve(process.env.ADMIN_UPLOADS_DIR)
  : path.join(__dirname, "uploads");
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
  console.log("Created uploads directory:", uploadsDir);
}

// Firebase Admin (FCM) - init early so routes can use it
import { initializeFirebaseAdmin } from "./config/firebase-admin.js";
initializeFirebaseAdmin();

// Import routes (after dotenv so they see PAYCHANGU_SECRET_KEY etc.)
// Use namespace import for auth so server works if deployed file uses default or named export
import * as authRoutesModule from "./routes/auth.routes.js";
const authRoutes = authRoutesModule.default ?? authRoutesModule.router ?? authRoutesModule;
import productsRoutes from "./routes/products.routes.js";
import ordersRoutes from "./routes/orders.routes.js";
import paymentsRoutes from "./routes/payments.routes.js";
import fcmRoutes from "./routes/fcm.routes.js";
import adminRoutes from "./routes/admin.routes.js";
import whatsappWebhookRoutes from "./routes/whatsapp.webhook.js";

const app = express();
const PORT = process.env.PORT || 3001;
const HOST = "0.0.0.0";

const weakJwtSecrets = new Set(["default-secret-change-me", "your_jwt_secret_here"]);
if (!process.env.JWT_SECRET || weakJwtSecrets.has(process.env.JWT_SECRET)) {
  console.error("JWT_SECRET must be configured to a strong secret before starting the API.");
  process.exit(1);
}

// CORS middleware
const corsOrigin = process.env.CORS_ORIGIN || "https://doorshoppin.com";

app.use(cors({
  origin: corsOrigin,
  methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  allowedHeaders: ["Content-Type", "Authorization"],
  credentials: true
}));

// Handle OPTIONS preflight requests
app.options('*', (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', corsOrigin);
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.status(204).end();
});

// Body parsing middleware
app.use(express.json({ limit: "10mb" }));
app.use(express.urlencoded({ limit: "10mb", extended: true }));

// Strip base path if deployed in subdirectory (e.g., /doorshoppin_backend)
app.use((req, res, next) => {
  // Log the original request for debugging
  console.log(`🔍 [Path Debug] Original URL: ${req.originalUrl}`);
  console.log(`🔍 [Path Debug] Request URL: ${req.url}`);
  console.log(`🔍 [Path Debug] Request Path: ${req.path}`);
  console.log(`🔍 [Path Debug] Base URL: ${req.baseUrl}`);
  
  // If path starts with /doorshoppin_backend, strip it from the URL
  // Note: req.path is read-only, so we only modify req.url
  if (req.path.startsWith('/doorshoppin_backend')) {
    const newUrl = req.url.replace('/doorshoppin_backend', '') || '/';
    console.log(`🔍 [Path Debug] Stripping prefix, new URL: ${newUrl}`);
    req.url = newUrl;
    // Also update the originalUrl if it contains the prefix
    if (req.originalUrl && req.originalUrl.startsWith('/doorshoppin_backend')) {
      req.originalUrl = req.originalUrl.replace('/doorshoppin_backend', '') || '/';
    }
  }
  next();
});

// Request logging middleware
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
  next();
});

// Ensure all API responses are JSON (critical for Node.js Selector health check)
app.use((req, res, next) => {
  // Always set JSON header for API routes and health checks
  if (req.path.startsWith('/api') || req.path === '/health' || req.path === '/' || req.path === '/favicon.ico') {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
  }
  next();
});

// Override res.json to ensure Content-Type is always set
const originalJson = express.response.json;
express.response.json = function(body) {
  if (!this.get('Content-Type')) {
    this.set('Content-Type', 'application/json; charset=utf-8');
  }
  return originalJson.call(this, body);
};

// Error handlers
process.on('unhandledRejection', (reason, promise) => {
  console.error('❌ Unhandled Rejection at:', promise, 'reason:', reason);
});

process.on('uncaughtException', (error) => {
  console.error('❌ Uncaught Exception:', error);
});

// Favicon handler
app.get("/favicon.ico", (req, res) => {
  res.status(204).end();
});

// Root route
app.get("/", (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.status(200).json({
    message: "Doorshoppin API",
    version: "1.0.0",
      endpoints: {
        health: "/health",
        auth: "/api/auth",
        products: "/api/products",
        orders: "/api/orders",
        payments: "/api/payments",
        fcm: "/api/fcm",
        admin: "/api/admin (login, orders, products)",
        whatsappWebhook: "GET/POST /api/webhooks/whatsapp"
      }
  });
});

// Health check - must always return JSON, even if DB fails
app.get("/health", async (req, res) => {
  try {
    res.setHeader('Content-Type', 'application/json');
    // Try to check database connection
    try {
      await connectToDatabase();
      res.status(200).json({
        status: "OK",
        message: "Doorshoppin API is running",
        database: "connected",
        timestamp: new Date().toISOString()
      });
    } catch (dbError) {
      // Server is running but DB might not be connected yet
      res.status(200).json({
        status: "OK",
        message: "Doorshoppin API is running",
        database: "connecting",
        timestamp: new Date().toISOString()
      });
    }
  } catch (error) {
    res.setHeader('Content-Type', 'application/json');
    res.status(200).json({
      status: "OK",
      message: "Doorshoppin API is running",
      timestamp: new Date().toISOString()
    });
  }
});

// Serve uploaded product images (e.g. /uploads/product_xxx.jpg)
app.use("/uploads", express.static(uploadsDir));
// When client requests .../doorshoppin_backend/uploads/xxx, serve from same folder
app.use("/doorshoppin_backend/uploads", express.static(uploadsDir));

// API Routes
app.use("/api/auth", authRoutes);
app.use("/api/products", productsRoutes);
app.use("/api/orders", ordersRoutes);
app.use("/api/payments", paymentsRoutes);
app.use("/api/fcm", fcmRoutes);
app.use("/api/admin", adminRoutes);
app.use("/api/webhooks/whatsapp", whatsappWebhookRoutes);

// 404 fallback
app.use((req, res) => {
  console.log(`❌ 404 - Route not found: ${req.method} ${req.path}`);
  res.setHeader('Content-Type', 'application/json');
  res.status(404).json({
    error: "Route not found",
    path: req.path,
    method: req.method,
    availableEndpoints: {
      root: "GET /",
      health: "GET /health",
      auth: "/api/auth",
      products: "/api/products",
      orders: "/api/orders",
      admin: "GET/POST /api/admin/login, GET /api/admin/dashboard (auth), GET /api/admin/orders, GET/POST/PUT/DELETE /api/admin/products"
    }
  });
});

// Error handler
app.use((err, req, res, next) => {
  console.error('Error:', err);
  res.setHeader('Content-Type', 'application/json');
  res.status(err.status || 500).json({ 
    success: false, 
    error: 'Internal Server Error',
    message: err.message || 'Internal server error',
    ...(process.env.NODE_ENV === "development" && { stack: err.stack })
  });
});

// Start server - don't wait for database, start immediately
function startServer() {
  // Start server immediately (database will connect on first request)
  const server = app.listen(PORT, HOST, () => {
    console.log("\n🚀 Doorshoppin Backend Server running");
    console.log(`🌍 Host: ${HOST}`);
    console.log(`🔌 Port: ${PORT}`);
    console.log("\n📘 Available Endpoints:");
    console.log("  GET  /");
    console.log("  GET  /health");
    console.log("  POST /api/auth/register");
    console.log("  POST /api/auth/login");
    console.log("  GET  /api/products");
    console.log("  GET  /api/products/:id");
    console.log("  POST /api/orders");
    console.log("  GET  /api/orders/my-orders");
    console.log("  GET  /api/orders/track/:orderId");
  console.log("  GET  /api/orders/delivery-fee?lat=X&lng=Y");
    console.log("  POST /api/payments/initiate");
    console.log("  GET  /api/payments/verify/:txRef");
    console.log("  POST /api/admin/login");
    console.log("  GET  /api/admin/dashboard (auth)");
    console.log("  GET  /api/admin/orders");
    console.log("  GET  /api/admin/products");
    console.log("  GET  /api/admin/products/:id");
    console.log("  POST /api/admin/products (auth)");
    console.log("  PUT  /api/admin/products/:id (auth)");
    console.log("  DELETE /api/admin/products/:id (auth)");
  });

  // Attempt database connection in background (non-blocking)
  connectToDatabase().catch((error) => {
    console.error("⚠️  Database connection failed, but server is running");
    console.error("⚠️  API endpoints will attempt to connect on each request");
    console.error("⚠️  Error:", error.message);
  });

  // Handle server errors gracefully
  server.on('error', (error) => {
    if (error.code === 'EADDRINUSE') {
      console.error(`❌ Port ${PORT} is already in use`);
      console.error(`   Try changing PORT in environment variables`);
    } else {
      console.error('❌ Server error:', error);
    }
  });

  return server;
}

// Start the server
try {
  startServer();
} catch (error) {
  console.error('❌ Failed to start server:', error);
  process.exit(1);
}
