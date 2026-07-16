/**
 * WhatsApp Inbox API routes.
 * - GET /conversations       — list unique contacts with last message + unread count
 * - GET /messages/:phone     — get all messages for a contact
 * - POST /send               — send a reply via WhatsApp Cloud API
 * - PATCH /read/:phone       — mark all messages from a contact as read
 * - GET /unread-count        — total unread messages count
 *
 * All routes require admin authentication.
 */

import express from "express";
import { query } from "../config/database.js";

const router = express.Router();

const WHATSAPP_GRAPH_BASE = "https://graph.facebook.com/v21.0";

/** Admin-only auth (same pattern as admin.routes.js) */
import jwt from "jsonwebtoken";
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
    return res.status(500).json({ success: false, error: "Authentication error" });
  }
}

/**
 * GET /api/whatsapp/conversations
 * Returns unique contacts with their last message and unread count.
 */
router.get("/conversations", authenticateAdmin, async (req, res) => {
  try {
    const conversations = await query(`
      SELECT
        m.contact_phone,
        m.contact_name,
        m.body AS last_message,
        m.message_type AS last_message_type,
        m.direction AS last_direction,
        m.created_at AS last_message_time,
        (
          SELECT COUNT(*)
          FROM whatsapp_messages u
          WHERE u.contact_phone = m.contact_phone
            AND u.direction = 'inbound'
            AND u.is_read = 0
        ) AS unread_count
      FROM whatsapp_messages m
      INNER JOIN (
        SELECT contact_phone, MAX(id) AS max_id
        FROM whatsapp_messages
        GROUP BY contact_phone
      ) latest ON m.contact_phone = latest.contact_phone AND m.id = latest.max_id
      ORDER BY m.created_at DESC
    `);

    return res.json({ success: true, data: conversations });
  } catch (err) {
    console.error("[WhatsApp Inbox] Conversations error:", err.message);
    return res.status(500).json({ success: false, error: "Failed to load conversations" });
  }
});

/**
 * GET /api/whatsapp/messages/:phone
 * Returns all messages for a specific contact, ordered chronologically.
 * Query: ?limit=50&before=<id>
 */
router.get("/messages/:phone", authenticateAdmin, async (req, res) => {
  try {
    const phone = req.params.phone.replace(/\D/g, "");
    const limit = Math.min(parseInt(req.query.limit, 10) || 100, 500);
    const before = parseInt(req.query.before, 10) || null;

    let sql = `
      SELECT id, wa_message_id, contact_phone, contact_name, direction,
             message_type, body, media_url, status, wa_timestamp, is_read, created_at
      FROM whatsapp_messages
      WHERE contact_phone = ?
    `;
    const params = [phone];

    if (before) {
      sql += " AND id < ?";
      params.push(before);
    }

    sql += " ORDER BY created_at ASC LIMIT ?";
    params.push(limit);

    const messages = await query(sql, params);

    return res.json({ success: true, data: messages });
  } catch (err) {
    console.error("[WhatsApp Inbox] Messages error:", err.message);
    return res.status(500).json({ success: false, error: "Failed to load messages" });
  }
});

/**
 * POST /api/whatsapp/send
 * Body: { to, message }
 * Sends a text message via WhatsApp Cloud API and stores it in the database.
 */
router.post("/send", authenticateAdmin, async (req, res) => {
  try {
    const { to, message } = req.body || {};

    if (!to || !message) {
      return res.status(400).json({ success: false, error: "to and message are required" });
    }

    const phone = String(to).replace(/\D/g, "");
    const accessToken = process.env.WHATSAPP_ACCESS_TOKEN;
    const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID;

    if (!accessToken || !phoneNumberId) {
      return res.status(500).json({
        success: false,
        error: "WhatsApp not configured. Set WHATSAPP_ACCESS_TOKEN and WHATSAPP_PHONE_NUMBER_ID in .env",
      });
    }

    const url = `${WHATSAPP_GRAPH_BASE}/${phoneNumberId}/messages`;
    const payload = {
      messaging_product: "whatsapp",
      to: phone,
      type: "text",
      text: { body: message },
    };

    const apiRes = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify(payload),
    });

    const data = await apiRes.json().catch(() => ({}));

    if (!apiRes.ok) {
      const errMsg = data.error?.message || data.error?.error_user_msg || apiRes.statusText;
      console.error("[WhatsApp Send] API error:", apiRes.status, errMsg);
      return res.status(apiRes.status).json({ success: false, error: errMsg });
    }

    const waMessageId = data.messages?.[0]?.id || null;

    // Store outbound message in database
    await query(
      `INSERT INTO whatsapp_messages (wa_message_id, contact_phone, contact_name, direction, message_type, body, status, wa_timestamp)
       VALUES (?, ?, NULL, 'outbound', 'text', ?, 'sent', NOW())`,
      [waMessageId, phone, message]
    );

    return res.json({
      success: true,
      messageId: waMessageId,
      message: "Message sent",
    });
  } catch (err) {
    console.error("[WhatsApp Send] Error:", err.message);
    return res.status(500).json({ success: false, error: "Failed to send message" });
  }
});

/**
 * PATCH /api/whatsapp/read/:phone
 * Marks all inbound messages from a contact as read.
 */
router.patch("/read/:phone", authenticateAdmin, async (req, res) => {
  try {
    const phone = req.params.phone.replace(/\D/g, "");
    await query(
      "UPDATE whatsapp_messages SET is_read = 1 WHERE contact_phone = ? AND direction = 'inbound' AND is_read = 0",
      [phone]
    );
    return res.json({ success: true });
  } catch (err) {
    console.error("[WhatsApp Inbox] Mark read error:", err.message);
    return res.status(500).json({ success: false, error: "Failed to mark as read" });
  }
});

/**
 * GET /api/whatsapp/unread-count
 * Returns total unread inbound messages count.
 */
router.get("/unread-count", authenticateAdmin, async (req, res) => {
  try {
    const [row] = await query(
      "SELECT COUNT(*) as count FROM whatsapp_messages WHERE direction = 'inbound' AND is_read = 0"
    );
    return res.json({ success: true, count: row?.count ?? 0 });
  } catch (err) {
    console.error("[WhatsApp Inbox] Unread count error:", err.message);
    return res.status(500).json({ success: false, error: "Failed to get unread count" });
  }
});

export default router;
