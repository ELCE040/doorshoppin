import express from "express";
import jwt from "jsonwebtoken";
import { query } from "../config/database.js";
import { subscribeTokenToAdminTopic } from "../config/firebase-admin.js";

const router = express.Router();

/**
 * POST /api/fcm/register
 * Body: { fcm_token: string, is_admin?: boolean, admin_id?: number }
 * - If is_admin === true: require a matching admin JWT and admin_id.
 * - Otherwise: require a user JWT and update that user's fcm_token.
 */
router.post("/register", async (req, res) => {
  res.setHeader("Content-Type", "application/json");

  try {
    const { fcm_token, is_admin, admin_id } = req.body;

    if (!fcm_token || typeof fcm_token !== "string" || !fcm_token.trim()) {
      return res.status(400).json({
        success: false,
        error: "fcm_token is required",
      });
    }

    const token = fcm_token.trim();

    // Admin (registered in SQL): store token in admins table, then subscribe to topic for delivery
    if (is_admin === true) {
      const id = admin_id != null ? Number(admin_id) : NaN;
      if (!Number.isInteger(id) || id < 1) {
        console.warn("[FCM] Admin register: missing or invalid admin_id", { admin_id: req.body.admin_id });
        return res.status(400).json({
          success: false,
          error: "admin_id is required for admin registration (must be a positive integer)",
        });
      }
      const authHeader = req.headers.authorization || "";
      const authToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : authHeader;
      if (!authToken) {
        return res.status(401).json({
          success: false,
          error: "Admin authorization required",
        });
      }
      let decoded;
      try {
        decoded = jwt.verify(authToken, process.env.JWT_SECRET);
      } catch (authErr) {
        return res.status(401).json({
          success: false,
          error: authErr.name === "TokenExpiredError" ? "Token expired" : "Invalid token",
        });
      }
      if (!decoded.adminId || Number(decoded.adminId) !== id) {
        return res.status(403).json({
          success: false,
          error: "Admin token does not match admin_id",
        });
      }
      console.log("[FCM] Admin register: updating admins for admin_id=" + id + ", token length=" + token.length);
      const updateResult = await query(
        "UPDATE admins SET fcm_token = ? WHERE id = ?",
        [token, id]
      );
      const affectedRows = Number(updateResult?.affectedRows ?? 0);
      console.log("[FCM] Admin register: UPDATE admins affectedRows=" + affectedRows);
      if (affectedRows === 0) {
        console.warn("[FCM] Admin register: no row updated for admin_id=" + id + " (wrong id or wrong DB?)");
        return res.status(404).json({
          success: false,
          error: "No admin found with this admin_id. Check that Node uses the same DB as phpMyAdmin.",
        });
      }
      const ok = await subscribeTokenToAdminTopic(token);
      console.log("[FCM] Admin register: topic subscribe ok=" + ok);
      return res.status(200).json({
        success: true,
        message: ok
          ? "Admin FCM token saved to SQL and subscribed to admin_orders"
          : "Admin FCM token saved to SQL; topic subscribe failed",
      });
    }

    const authHeader = req.headers.authorization || "";
    const authToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : authHeader;
    if (!authToken) {
      return res.status(401).json({
        success: false,
        error: "User authorization required",
      });
    }
    let decoded;
    try {
      decoded = jwt.verify(authToken, process.env.JWT_SECRET);
    } catch (authErr) {
      return res.status(401).json({
        success: false,
        error: authErr.name === "TokenExpiredError" ? "Token expired" : "Invalid token",
      });
    }
    if (!decoded.userId) {
      return res.status(401).json({
        success: false,
        error: "Invalid token: user only",
      });
    }

    const result = await query(
      "UPDATE users SET fcm_token = ? WHERE id = ?",
      [token, decoded.userId]
    );
    const affectedRows = result?.affectedRows ?? 0;

    if (affectedRows === 0) {
      return res.status(404).json({
        success: false,
        error: "No user found for this token",
      });
    }

    res.status(200).json({
      success: true,
      message: "FCM token registered",
    });
  } catch (err) {
    console.error("FCM register error:", err);
    res.status(500).json({
      success: false,
      error: "Failed to register FCM token",
      message: err.message,
    });
  }
});

export default router;
