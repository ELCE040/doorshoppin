import express from "express";
import { query } from "../config/database.js";
import { authenticate, authenticateAdmin, authenticateUserOrAdmin } from "../middleware/auth.middleware.js";
import { sendFcmNotification, sendFcmToAdminTopic } from "../config/firebase-admin.js";

const router = express.Router();

// Fallback user_id for guest checkout when orders.user_id is NOT NULL
const GUEST_USER_ID = parseInt(process.env.GUEST_USER_ID || "1", 10);

// ─── Store location ───────────────────────────────────────────────────────────
const OFFICE_LAT = parseFloat(process.env.OFFICE_LAT || "-15.7854788");
const OFFICE_LNG = parseFloat(process.env.OFFICE_LNG || "35.0075824");

// ─── Minimum delivery fee ─────────────────────────────────────────────────────
const MIN_DELIVERY_FEE = parseFloat(process.env.MIN_DELIVERY_FEE || "1000");
const DELIVERY_FEE_MULTIPLIER = parseFloat(process.env.DELIVERY_FEE_MULTIPLIER || "1.5");
const SERVICE_FEE_RATE = parseFloat(process.env.SERVICE_FEE_RATE || "0.12");

// ═══════════════════════════════════════════════════════════════════════════════
// MULTI-DIMENSIONAL PRICING — mirrors lib/services/delivery_fee_service.dart
// ═══════════════════════════════════════════════════════════════════════════════

// ── Distance base prices (16 tiers, no hard cap) ──────────────────────────────
const DISTANCE_TIERS = [
  { maxKm:  0.8,      baseFee:   800 },
  { maxKm:  1.5,      baseFee:  1000 },
  { maxKm:  2.5,      baseFee:  1300 },
  { maxKm:  3.5,      baseFee:  1600 },
  { maxKm:  5.0,      baseFee:  2000 },
  { maxKm:  6.5,      baseFee:  2500 },
  { maxKm:  8.0,      baseFee:  3000 },
  { maxKm: 10.0,      baseFee:  3500 },
  { maxKm: 12.0,      baseFee:  4200 },
  { maxKm: 14.0,      baseFee:  5000 },
  { maxKm: 17.0,      baseFee:  6000 },
  { maxKm: 20.0,      baseFee:  7000 },
  { maxKm: 25.0,      baseFee:  8500 },
  { maxKm: 30.0,      baseFee: 10000 },
  { maxKm: 40.0,      baseFee: 13000 },
  { maxKm: Infinity,  baseFee: 17000 },
];

// ── Road access multipliers (index = RoadAccess enum ordinal) ─────────────────
// 0=mainRoad  1=tarredSideRoad  2=gravelRoad  3=dirtTrack  4=offRoad
const ROAD_MULTIPLIERS = [0.90, 1.00, 1.15, 1.30, 1.55];

// ── Neighbourhood multipliers (index = NeighbourhoodType enum ordinal) ────────
// 0=wealthyLowDensity  1=upperMiddle  2=middleClass  3=denseTownship
// 4=poorTownship  5=ruralVillage  6=industrialCommercial
const NEIGHBOURHOOD_MULTIPLIERS = [0.95, 1.00, 1.05, 1.20, 1.30, 1.45, 0.90];

function baseFeeForKm(km) {
  for (const tier of DISTANCE_TIERS) {
    if (km <= tier.maxKm) return tier.baseFee;
  }
  return DISTANCE_TIERS[DISTANCE_TIERS.length - 1].baseFee;
}

function toRadians(value) {
  return (value * Math.PI) / 180;
}

function distanceKm(lat1, lng1, lat2, lng2) {
  const earthRadiusKm = 6371;
  const dLat = toRadians(lat2 - lat1);
  const dLng = toRadians(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRadians(lat1)) *
      Math.cos(toRadians(lat2)) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return earthRadiusKm * c;
}

/**
 * Calculate delivery fee in MWK using distance + road access + neighbourhood.
 * roadAccessIndex and neighbourhoodIndex are enum ordinals from the Flutter app.
 * Never returns below MIN_DELIVERY_FEE. No hard upper cap.
 */
function deliveryFeeFromDistanceKm(km, roadAccessIndex = 1, neighbourhoodIndex = 2) {
  const base = baseFeeForKm(Math.max(0, Number(km) || 0));
  const roadMult = ROAD_MULTIPLIERS[roadAccessIndex] ?? 1.0;
  const neighbourMult = NEIGHBOURHOOD_MULTIPLIERS[neighbourhoodIndex] ?? 1.05;
  const raw = base * roadMult * neighbourMult * DELIVERY_FEE_MULTIPLIER;
  const rounded = Math.ceil(raw / 100) * 100;
  return Math.max(rounded, MIN_DELIVERY_FEE);
}

function computeDeliveryFee({ fulfillmentMode, latitude, longitude, roadAccessIndex = 1, neighbourhoodIndex = 2 }) {
  if (fulfillmentMode === "pickup") return 0;
  if (latitude == null || longitude == null) return MIN_DELIVERY_FEE;

  const km = distanceKm(OFFICE_LAT, OFFICE_LNG, Number(latitude), Number(longitude));
  return deliveryFeeFromDistanceKm(km, roadAccessIndex, neighbourhoodIndex);
}

function phoneDigitVariants(phone) {
  const digits = String(phone || "").replace(/\D/g, "");
  if (!digits) return [];

  const local =
    digits.startsWith("265") && digits.length > 9
      ? digits.slice(3)
      : digits.startsWith("0") && digits.length > 1
        ? digits.slice(1)
        : digits;

  const variants = new Set([
    digits,
    local,
    local ? `0${local}` : "",
    local ? `265${local}` : "",
  ]);

  return [...variants].filter((value) => value && value.length >= 7);
}

/* ----------------------------------------
   CREATE ORDER
---------------------------------------- */
router.post("/", async (req, res) => {
  try {
    const {
      userId,
      items, // Array of { productId, name, price, quantity }
      deliveryInfo, // { name, phone, email, address, placeDescription, location }
      paymentMethod, // 'mobile'
      paymentTransactionId, // Optional: from PayChangu payment flow
      subtotal,
      serviceFee,
      deliveryFee,
      fulfillmentMode, // "delivery" or "pickup"
      total,
    } = req.body;

    // Validate required fields
    if (!items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({
        success: false,
        error: "Order must contain at least one item",
      });
    }

    if (!deliveryInfo || !deliveryInfo.name || !deliveryInfo.phone || !deliveryInfo.address) {
      return res.status(400).json({
        success: false,
        error: "Delivery information is required (name, phone, address)",
      });
    }

    if (!paymentMethod) {
      return res.status(400).json({
        success: false,
        error: "Payment method is required",
      });
    }

    if (paymentMethod !== "mobile") {
      return res.status(400).json({
        success: false,
        error: "Cash on delivery has been removed. Please pay via mobile money.",
      });
    }

    // Generate order tracking ID
    const orderTrackingId = `DS-${new Date().getFullYear()}-${String(Math.floor(Math.random() * 10000)).padStart(4, "0")}`;

    const latitude = deliveryInfo.location?.lat || null;
    const longitude = deliveryInfo.location?.lng || null;
    const clientTotal = parseFloat(total) || 0;
    const subtotalAmount = parseFloat(subtotal) || 0;
    const isPickup = (fulfillmentMode || "delivery") === "pickup";

    const kmFromStore = (latitude != null && longitude != null)
      ? distanceKm(OFFICE_LAT, OFFICE_LNG, Number(latitude), Number(longitude))
      : 0;
    const roadAccessIndex = Number.isInteger(req.body.roadAccess) ? req.body.roadAccess : 1;
    const neighbourhoodIndex = Number.isInteger(req.body.neighbourhood) ? req.body.neighbourhood : 2;
    const computedDeliveryFee = computeDeliveryFee({
      fulfillmentMode: fulfillmentMode || "delivery",
      latitude,
      longitude,
      roadAccessIndex,
      neighbourhoodIndex,
    });
    const clientDeliveryFee = parseFloat(deliveryFee) || 0;
    const clientServiceFee = parseFloat(serviceFee) || 0;
    // Backend authoritative delivery fee (0 for pickup)
    const deliveryFeeAmount = isPickup ? 0 : computedDeliveryFee;
    const serviceFeeAmount = subtotalAmount * SERVICE_FEE_RATE;
    const totalAmount = subtotalAmount + serviceFeeAmount + deliveryFeeAmount;

    if (
      Math.abs(clientDeliveryFee - deliveryFeeAmount) > 0.5 ||
      Math.abs(clientServiceFee - serviceFeeAmount) > 0.5 ||
      Math.abs(clientTotal - totalAmount) > 0.5
    ) {
      console.warn("[Orders] Fee mismatch from client; backend values applied", {
        clientDeliveryFee,
        backendDeliveryFee: deliveryFeeAmount,
        clientServiceFee,
        backendServiceFee: serviceFeeAmount,
        clientTotal,
        backendTotal: totalAmount,
        isPickup,
      });
    }

    // Determine payment status based on payment method
    let paymentStatus = "pending";
    if (paymentMethod === "mobile" && paymentTransactionId) {
      // If payment transaction ID is provided, check payment status
      const paymentCheck = await query(
        "SELECT status FROM transactions WHERE transaction_id = ? OR charge_id = ?",
        [paymentTransactionId, paymentTransactionId]
      );
      
      if (paymentCheck.length > 0) {
        const txStatus = paymentCheck[0].status;
        paymentStatus = txStatus === "success" || txStatus === "completed" ? "paid" : "pending";
      }
    }

    // Insert order
    const orderSql = `
      INSERT INTO orders (
        user_id, 
        status, 
        payment_status,
        payment_method,
        payment_transaction_id,
        subtotal,
        delivery_fee,
        service_fee,
        total_amount, 
        latitude, 
        longitude, 
        address,
        place_description,
        customer_name,
        customer_phone,
        customer_email,
        order_tracking_id, 
        created_at, 
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())
    `;

    const effectiveUserId = (userId != null && userId !== "" && !Number.isNaN(Number(userId)))
      ? Number(userId)
      : GUEST_USER_ID;
    const orderResult = await query(orderSql, [
      effectiveUserId,
      "pending",
      paymentStatus,
      paymentMethod,
      paymentTransactionId || null,
      subtotalAmount,
      deliveryFeeAmount,
      serviceFeeAmount,
      totalAmount,
      latitude,
      longitude,
      deliveryInfo.address,
      deliveryInfo.placeDescription || null,
      deliveryInfo.name,
      deliveryInfo.phone,
      deliveryInfo.email || null,
      orderTrackingId,
    ]);

    const orderId = orderResult.insertId;

    // Insert order items into order_items table (NOT transactions)
    for (const item of items) {
      const itemSql = `
        INSERT INTO order_items (
          order_id, 
          product_id, 
          product_name, 
          quantity, 
          unit_price, 
          subtotal,
          created_at
        )
        VALUES (?, ?, ?, ?, ?, ?, NOW())
      `;
      
      const itemSubtotal = parseFloat(item.price) * parseInt(item.quantity);
      
      await query(itemSql, [
        orderId,
        item.productId,
        item.name,
        item.quantity,
        parseFloat(item.price),
        itemSubtotal,
      ]);
    }

    // If payment transaction ID was provided, link it back to this order
    if (paymentTransactionId) {
      try {
        if (paymentStatus === "paid") {
          await query(
            "UPDATE transactions SET product_name = ?, quantity = ?, status = 'completed', updated_at = NOW() WHERE transaction_id = ? OR charge_id = ?",
            [`Order ${orderTrackingId}`, items.length, paymentTransactionId, paymentTransactionId]
          );
        } else {
          await query(
            "UPDATE transactions SET product_name = ?, quantity = ?, updated_at = NOW() WHERE transaction_id = ? OR charge_id = ?",
            [`Order ${orderTrackingId}`, items.length, paymentTransactionId, paymentTransactionId]
          );
        }
      } catch (err) {
        console.warn("Could not update payment transaction with order details:", err);
      }
    }

    // If user has temp_orders, clear them (optional - for logged-in users)
    if (userId) {
      await query("DELETE FROM temp_orders WHERE user_id = ?", [userId]);
    }

    // Also clear temp_orders by email if provided
    if (deliveryInfo.email) {
      await query("DELETE FROM temp_orders WHERE email = ?", [deliveryInfo.email]);
    }

    // Send FCM push notification to user and admins (if tokens / topic are available)
    try {
      let fcmRows = [];
      if (effectiveUserId && effectiveUserId !== GUEST_USER_ID) {
        fcmRows = await query(
          "SELECT fcm_token FROM users WHERE id = ? AND fcm_token IS NOT NULL AND fcm_token != ''",
          [effectiveUserId]
        );
      }
      if (fcmRows.length === 0 && (deliveryInfo.email || deliveryInfo.phone)) {
        fcmRows = await query(
          "SELECT fcm_token FROM users WHERE (email = ? OR phone = ?) AND fcm_token IS NOT NULL AND fcm_token != ''",
          [deliveryInfo.email || null, deliveryInfo.phone || null]
        );
      }
      const fcmToken = fcmRows?.[0]?.fcm_token;
      const isCash = paymentMethod === "cash";
      const userTitle = isCash ? "Order Placed" : "Payment Successful";
      const userBody = isCash
        ? `Your order ${orderTrackingId} has been placed. We will deliver it soon.`
        : `Your order ${orderTrackingId} has been paid. We are preparing it now.`;
      const payload = {
        type: isCash ? "order_success" : "payment_success",
        orderId: String(orderId),
        orderTrackingId,
        total: String(totalAmount),
      };

      if (fcmToken) {
        await sendFcmNotification(fcmToken, userTitle, userBody, payload);
      }

      // Notify all admin devices subscribed to the admin topic
      const adminTitle = isCash
        ? "New Cash Order Placed"
        : "New Paid Order";
      const adminBody = isCash
        ? `Order ${orderTrackingId} placed. Total MWK ${totalAmount}.`
        : `Order ${orderTrackingId} paid. Total MWK ${totalAmount}.`;
      await sendFcmToAdminTopic(adminTitle, adminBody, {
        ...payload,
        type: isCash ? "admin_order_success" : "admin_payment_success",
      });
    } catch (fcmErr) {
      console.warn("FCM send failed (non-fatal):", fcmErr.message);
    }

    res.status(201).json({
      success: true,
      message: "Order created successfully",
      data: {
        orderId: orderId,
        orderTrackingId: orderTrackingId,
        total: totalAmount,
        status: "pending",
        paymentStatus: paymentStatus,
        paymentMethod: paymentMethod,
      },
    });
  } catch (error) {
    console.error("Error creating order:", error);
    res.status(500).json({
      success: false,
      error: "Failed to create order",
      message: error.message,
    });
  }
});

/* ----------------------------------------
   GET USER ORDERS (authenticated)
---------------------------------------- */
router.get("/my-orders", authenticate, async (req, res) => {
  try {
    const userId = req.userId; // From auth middleware
    const { limit = 20, skip = 0 } = req.query;

    const sql = `
      SELECT 
        o.id, 
        o.user_id as userId, 
        o.status, 
        o.payment_status as paymentStatus,
        o.payment_method as paymentMethod,
        o.total_amount as totalAmount,
        o.subtotal,
        o.delivery_fee as deliveryFee,
        o.service_fee as serviceFee,
        o.latitude, 
        o.longitude, 
        o.address,
        o.customer_name as customerName,
        o.customer_phone as customerPhone,
        o.order_tracking_id as orderTrackingId,
        o.created_at as createdAt, 
        o.updated_at as updatedAt,
        COUNT(oi.id) as itemCount
      FROM orders o
      LEFT JOIN order_items oi ON o.id = oi.order_id
      WHERE o.user_id = ?
      GROUP BY o.id
      ORDER BY o.created_at DESC
      LIMIT ? OFFSET ?
    `;

    const orders = await query(sql, [userId, parseInt(limit), parseInt(skip)]);

    // Get total count
    const [countResult] = await query(
      "SELECT COUNT(*) as total FROM orders WHERE user_id = ?",
      [userId]
    );
    const total = countResult.total;

    res.json({
      success: true,
      data: orders,
      pagination: {
        total,
        limit: parseInt(limit),
        skip: parseInt(skip),
        hasMore: parseInt(skip) + orders.length < total,
      },
    });
  } catch (error) {
    console.error("Error fetching orders:", error);
    res.status(500).json({
      success: false,
      error: "Failed to fetch orders",
      message: error.message,
    });
  }
});

/* ----------------------------------------
   GET USER ORDERS BY EMAIL/PHONE (Firebase app users)
---------------------------------------- */
router.get("/lookup/my-orders", async (req, res) => {
  try {
    const email = String(req.query.email || "").trim().toLowerCase();
    const phoneVariants = phoneDigitVariants(req.query.phone);
    const { limit = 20, skip = 0 } = req.query;

    if (!email && phoneVariants.length === 0) {
      return res.status(400).json({
        success: false,
        error: "Email or phone is required",
      });
    }

    const whereClauses = [];
    const params = [];

    if (email) {
      whereClauses.push("LOWER(COALESCE(o.customer_email, '')) = ?");
      params.push(email);
    }

    if (phoneVariants.length > 0) {
      const normalizedPhoneExpr =
        "REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(COALESCE(o.customer_phone, ''), ' ', ''), '-', ''), '+', ''), '(', ''), ')', '')";
      whereClauses.push(
        `${normalizedPhoneExpr} IN (${phoneVariants.map(() => "?").join(", ")})`
      );
      params.push(...phoneVariants);
    }

    const whereSql = whereClauses.join(" OR ");

    const sql = `
      SELECT
        o.id,
        o.user_id as userId,
        o.status,
        o.payment_status as paymentStatus,
        o.payment_method as paymentMethod,
        o.total_amount as totalAmount,
        o.subtotal,
        o.delivery_fee as deliveryFee,
        o.service_fee as serviceFee,
        o.latitude,
        o.longitude,
        o.address,
        o.customer_name as customerName,
        o.customer_phone as customerPhone,
        o.order_tracking_id as orderTrackingId,
        o.created_at as createdAt,
        o.updated_at as updatedAt,
        COUNT(oi.id) as itemCount
      FROM orders o
      LEFT JOIN order_items oi ON o.id = oi.order_id
      WHERE ${whereSql}
      GROUP BY o.id
      ORDER BY o.created_at DESC
      LIMIT ? OFFSET ?
    `;

    const parsedLimit = parseInt(limit, 10) || 20;
    const parsedSkip = parseInt(skip, 10) || 0;
    const orders = await query(sql, [...params, parsedLimit, parsedSkip]);

    const countSql = `
      SELECT COUNT(*) as total
      FROM orders o
      WHERE ${whereSql}
    `;
    const [countResult] = await query(countSql, params);
    const total = countResult?.total || 0;

    res.json({
      success: true,
      data: orders,
      pagination: {
        total,
        limit: parsedLimit,
        skip: parsedSkip,
        hasMore: parsedSkip + orders.length < total,
      },
    });
  } catch (error) {
    console.error("Error fetching orders by contact:", error);
    res.status(500).json({
      success: false,
      error: "Failed to fetch orders",
      message: error.message,
    });
  }
});

/* ----------------------------------------
   GET DELIVERY FEE FOR A LOCATION
   GET /delivery-fee?lat=X&lng=Y
   Returns the delivery fee (MWK) for any lat/lng.
   Used by the Flutter app to keep client/server in sync.
---------------------------------------- */
router.get("/delivery-fee", (req, res) => {
  try {
    const lat = parseFloat(req.query.lat);
    const lng = parseFloat(req.query.lng);

    if (isNaN(lat) || isNaN(lng)) {
      return res.status(400).json({
        success: false,
        error: "lat and lng query parameters are required and must be numbers",
      });
    }

    const km = distanceKm(OFFICE_LAT, OFFICE_LNG, lat, lng);
    const roadIdx = parseInt(req.query.road ?? "1", 10);
    const neighbourIdx = parseInt(req.query.neighbourhood ?? "2", 10);
    const feeMwk = deliveryFeeFromDistanceKm(km, roadIdx, neighbourIdx);

    return res.json({
      success: true,
      data: {
        feeMwk,
        distanceKm: parseFloat(km.toFixed(3)),
        minDeliveryFee: MIN_DELIVERY_FEE,
      },
    });
  } catch (err) {
    console.error("[delivery-fee] Error:", err);
    return res.status(500).json({ success: false, error: "Failed to calculate fee" });
  }
});

/* ----------------------------------------
   GET ORDER BY ID (with items)
---------------------------------------- */
router.get("/:id", authenticateUserOrAdmin, async (req, res) => {
  try {
    const { id } = req.params;

    // Try to find by ID first, then by order_tracking_id
    let sql = `
      SELECT 
        o.id, 
        o.user_id as userId, 
        o.status,
        o.payment_status as paymentStatus,
        o.payment_method as paymentMethod,
        o.payment_transaction_id as paymentTransactionId,
        o.total_amount as totalAmount,
        o.subtotal,
        o.delivery_fee as deliveryFee,
        o.service_fee as serviceFee,
        o.latitude, 
        o.longitude, 
        o.address,
        o.place_description as placeDescription,
        o.customer_name as customerName,
        o.customer_phone as customerPhone,
        o.customer_email as customerEmail,
        o.order_tracking_id as orderTrackingId,
        o.created_at as createdAt, 
        o.updated_at as updatedAt
      FROM orders o
      WHERE o.id = ?
    `;

    let orders = await query(sql, [id]);

    // If not found by ID, try order_tracking_id
    if (orders.length === 0) {
      sql = `
        SELECT 
          o.id, 
          o.user_id as userId, 
          o.status,
          o.payment_status as paymentStatus,
          o.payment_method as paymentMethod,
          o.payment_transaction_id as paymentTransactionId,
          o.total_amount as totalAmount,
          o.subtotal,
          o.delivery_fee as deliveryFee,
          o.service_fee as serviceFee,
          o.latitude, 
          o.longitude, 
          o.address,
          o.place_description as placeDescription,
          o.customer_name as customerName,
          o.customer_phone as customerPhone,
          o.customer_email as customerEmail,
          o.order_tracking_id as orderTrackingId,
          o.created_at as createdAt, 
          o.updated_at as updatedAt
        FROM orders o
        WHERE o.order_tracking_id = ?
      `;
      orders = await query(sql, [id]);
    }

    if (orders.length === 0) {
      return res.status(404).json({
        success: false,
        error: "Order not found",
      });
    }

    const order = orders[0];

    if (!req.adminId && (!req.userId || !order.userId || order.userId.toString() !== req.userId)) {
      return res.status(403).json({
        success: false,
        error: "Access denied",
      });
    }

    // Get order items with product image (join products for image_path)
    const itemsSql = `
      SELECT 
        oi.id,
        oi.product_id as productId,
        oi.product_name as productName,
        oi.quantity,
        oi.unit_price as unitPrice,
        oi.subtotal,
        oi.created_at as createdAt,
        COALESCE(p.image_path, '') as imageUrl
      FROM order_items oi
      LEFT JOIN products p ON oi.product_id = p.id
      WHERE oi.order_id = ?
      ORDER BY oi.created_at ASC
    `;
    
    const items = await query(itemsSql, [order.id]);
    order.items = items;

    res.json({
      success: true,
      data: order,
    });
  } catch (error) {
    console.error("Error fetching order:", error);
    res.status(500).json({
      success: false,
      error: "Failed to fetch order",
      message: error.message,
    });
  }
});

/* ----------------------------------------
   TRACK ORDER BY ORDER TRACKING ID
---------------------------------------- */
router.get("/track/:orderId", async (req, res) => {
  try {
    const { orderId } = req.params;

    const sql = `
      SELECT 
        o.id, 
        o.user_id as userId, 
        o.status,
        o.payment_status as paymentStatus,
        o.payment_method as paymentMethod,
        o.total_amount as totalAmount,
        o.latitude, 
        o.longitude, 
        o.address,
        o.customer_name as customerName,
        o.customer_phone as customerPhone,
        o.order_tracking_id as orderTrackingId,
        o.created_at as createdAt, 
        o.updated_at as updatedAt
      FROM orders o
      WHERE o.order_tracking_id = ?
    `;

    const orders = await query(sql, [orderId]);

    if (orders.length === 0) {
      return res.status(404).json({
        success: false,
        error: "Order not found",
      });
    }

    const order = orders[0];

    // Get order items count
    const [itemCount] = await query(
      "SELECT COUNT(*) as count FROM order_items WHERE order_id = ?",
      [order.id]
    );

    // Return order with status timeline
    const statusTimeline = [
      { label: "Pending", completed: order.status !== "pending", current: order.status === "pending" },
      { label: "Processing", completed: ["processing", "out_for_delivery", "delivered"].includes(order.status), current: order.status === "processing" },
      { label: "Out for delivery", completed: ["out_for_delivery", "delivered"].includes(order.status), current: order.status === "out_for_delivery" },
      { label: "Delivered", completed: order.status === "delivered", current: order.status === "delivered" },
    ];

    res.json({
      success: true,
      data: {
        orderId: order.id,
        orderTrackingId: order.orderTrackingId,
        status: order.status,
        paymentStatus: order.paymentStatus,
        paymentMethod: order.paymentMethod,
        statusTimeline,
        itemCount: itemCount.count,
        total: parseFloat(order.totalAmount),
        deliveryInfo: {
          customerName: order.customerName,
          customerPhone: order.customerPhone,
          address: order.address,
          latitude: order.latitude,
          longitude: order.longitude,
        },
        createdAt: order.createdAt,
        updatedAt: order.updatedAt,
      },
    });
  } catch (error) {
    console.error("Error tracking order:", error);
    res.status(500).json({
      success: false,
      error: "Failed to track order",
      message: error.message,
    });
  }
});

/* ----------------------------------------
   UPDATE ORDER STATUS
---------------------------------------- */
router.patch("/:id/status", authenticateAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const { status } = req.body;

    const validStatuses = ["pending", "processing", "out_for_delivery", "delivered", "cancelled"];
    if (!status || !validStatuses.includes(status)) {
      return res.status(400).json({
        success: false,
        error: `Status must be one of: ${validStatuses.join(", ")}`,
      });
    }

    // Find order by ID or order_tracking_id
    let findSql = "SELECT id, payment_method FROM orders WHERE id = ?";
    let orders = await query(findSql, [id]);

    if (orders.length === 0) {
      findSql = "SELECT id, payment_method FROM orders WHERE order_tracking_id = ?";
      orders = await query(findSql, [id]);
    }

    if (orders.length === 0) {
      return res.status(404).json({
        success: false,
        error: "Order not found",
      });
    }

    const orderId = orders[0].id;
    const paymentMethod = orders[0].payment_method;

    // Update status
    const updateSql = "UPDATE orders SET status = ?, updated_at = NOW() WHERE id = ?";
    const result = await query(updateSql, [status, orderId]);

    // If delivered and payment method is cash, mark as paid
    if (status === "delivered" && paymentMethod === "cash") {
      await query(
        "UPDATE orders SET payment_status = 'paid' WHERE id = ?",
        [orderId]
      );
    }

    if (result.affectedRows === 0) {
      return res.status(400).json({
        success: false,
        error: "Failed to update order status",
      });
    }

    // Get updated order + resolve user FCM token
    const [updatedOrder] = await query(
      `SELECT order_tracking_id, payment_status, user_id,
              customer_email, customer_phone
       FROM orders WHERE id = ?`,
      [orderId]
    );

    // ── Notify user via FCM (data-only) ────────────────────────────────────
    try {
      let fcmRows = [];

      // Helper: strip country code so "265991234567" and "0991234567" and "991234567" all match
      const normalizePhone = (p) => {
        if (!p) return null;
        const digits = p.replace(/\D/g, "");
        if (digits.startsWith("265") && digits.length >= 12) return digits.slice(3); // strip 265
        if (digits.startsWith("0") && digits.length >= 9)   return digits.slice(1);  // strip leading 0
        return digits;
      };

      // 1. Try by user_id (logged-in users — not guest)
      const uid = Number(updatedOrder.user_id);
      if (!isNaN(uid) && uid > 1 && uid !== GUEST_USER_ID) {
        fcmRows = await query(
          "SELECT fcm_token FROM users WHERE id = ? AND fcm_token IS NOT NULL AND fcm_token != ''",
          [uid]
        );
      }

      // 2. Fall back: match by email
      if (fcmRows.length === 0 && updatedOrder.customer_email) {
        fcmRows = await query(
          "SELECT fcm_token FROM users WHERE email = ? AND fcm_token IS NOT NULL AND fcm_token != ''",
          [updatedOrder.customer_email.trim().toLowerCase()]
        );
      }

      // 3. Fall back: match by phone — try all 3 normalised forms
      if (fcmRows.length === 0 && updatedOrder.customer_phone) {
        const raw    = updatedOrder.customer_phone.replace(/\D/g, "");
        const local  = normalizePhone(raw);                              // e.g. 991234567
        const withCC = "265" + local;                                    // e.g. 265991234567
        const withZero = "0" + local;                                   // e.g. 0991234567
        fcmRows = await query(
          `SELECT fcm_token FROM users
           WHERE fcm_token IS NOT NULL AND fcm_token != ''
             AND (phone = ? OR phone = ? OR phone = ? OR phone = ? OR phone = ?)
           LIMIT 1`,
          [raw, local, withCC, withZero, "+" + withCC]
        );
      }

      const fcmToken = fcmRows?.[0]?.fcm_token;
      console.log(`[FCM] Status update order ${orderId} → token ${fcmToken ? "FOUND (" + fcmToken.slice(0,20) + "...)" : "NOT FOUND"}`);

      const statusMessages = {
        pending:          { title: "Order Received",      body: `Order ${updatedOrder.order_tracking_id} has been received and is pending.` },
        processing:       { title: "Order Processing",    body: `Order ${updatedOrder.order_tracking_id} is being prepared.` },
        out_for_delivery: { title: "Out for Delivery",    body: `Order ${updatedOrder.order_tracking_id} is on its way to you!` },
        delivered:        { title: "Order Delivered",     body: `Order ${updatedOrder.order_tracking_id} has been delivered. Enjoy!` },
        cancelled:        { title: "Order Cancelled",     body: `Order ${updatedOrder.order_tracking_id} has been cancelled.` },
      };
      const msg = statusMessages[status] || { title: "Order Update", body: `Your order ${updatedOrder.order_tracking_id} status: ${status}.` };

      if (fcmToken) {
        await sendFcmNotification(fcmToken, msg.title, msg.body, {
          type: "order_status_update",
          orderId: String(orderId),
          orderTrackingId: updatedOrder.order_tracking_id,
          status,
        });
      }
    } catch (fcmErr) {
      console.warn("FCM status update notify failed (non-fatal):", fcmErr.message);
    }
    // ─────────────────────────────────────────────────────────────────────

    res.json({
      success: true,
      message: "Order status updated",
      data: {
        orderId: orderId,
        orderTrackingId: updatedOrder.order_tracking_id,
        status: status,
        paymentStatus: updatedOrder.payment_status,
      },
    });
  } catch (error) {
    console.error("Error updating order status:", error);
    res.status(500).json({
      success: false,
      error: "Failed to update order status",
      message: error.message,
    });
  }
});

/* ----------------------------------------
   UPDATE PAYMENT STATUS
---------------------------------------- */
router.patch("/:id/payment-status", authenticateAdmin, async (req, res) => {
  try {
    const { id } = req.params;
    const { paymentStatus } = req.body;

    const validStatuses = ["pending", "paid", "failed", "refunded"];
    if (!paymentStatus || !validStatuses.includes(paymentStatus)) {
      return res.status(400).json({
        success: false,
        error: `Payment status must be one of: ${validStatuses.join(", ")}`,
      });
    }

    // Find order
    let findSql = "SELECT id FROM orders WHERE id = ?";
    let orders = await query(findSql, [id]);

    if (orders.length === 0) {
      findSql = "SELECT id FROM orders WHERE order_tracking_id = ?";
      orders = await query(findSql, [id]);
    }

    if (orders.length === 0) {
      return res.status(404).json({
        success: false,
        error: "Order not found",
      });
    }

    const orderId = orders[0].id;

    // Update payment status
    const updateSql = "UPDATE orders SET payment_status = ?, updated_at = NOW() WHERE id = ?";
    await query(updateSql, [paymentStatus, orderId]);

    res.json({
      success: true,
      message: "Payment status updated",
      data: {
        orderId: orderId,
        paymentStatus: paymentStatus,
      },
    });
  } catch (error) {
    console.error("Error updating payment status:", error);
    res.status(500).json({
      success: false,
      error: "Failed to update payment status",
      message: error.message,
    });
  }
});

export default router;
