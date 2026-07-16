/**
 * WhatsApp Cloud API webhook (Meta).
 * - GET: Verification (Meta sends hub.mode, hub.verify_token, hub.challenge).
 * - POST: Incoming messages and status updates.
 * Configure URL in Meta Developer Console: https://developers.facebook.com/apps → WhatsApp → Configuration.
 */

import express from "express";

const router = express.Router();

const VERIFY_TOKEN = process.env.WHATSAPP_VERIFY_TOKEN || "doorshoppin_verify";

/* ----------------------------------------
   GET – Webhook verification (Meta requires this)
   Query: hub.mode=subscribe&hub.verify_token=XXX&hub.challenge=YYYY
----------------------------------------- */
router.get("/", (req, res) => {
  const mode = req.query["hub.mode"];
  const token = req.query["hub.verify_token"];
  const challenge = req.query["hub.challenge"];

  if (mode === "subscribe" && token === VERIFY_TOKEN) {
    console.log("✅ [WhatsApp Webhook] Verified successfully");
    res.status(200).send(challenge);
  } else if (!mode && !token) {
    res.status(400).json({
      error: "Missing verification params",
      hint: "Meta calls this URL with hub.mode, hub.verify_token, hub.challenge. Set WHATSAPP_VERIFY_TOKEN in .env and use the same value in Meta Developer Console → WhatsApp → Configuration → Webhook.",
    });
  } else {
    console.warn("❌ [WhatsApp Webhook] Verification failed – wrong mode or token (expected token:", VERIFY_TOKEN ? "set" : "missing", ")");
    res.status(403).send("Forbidden");
  }
});

/* ----------------------------------------
   POST – Incoming webhook events (messages, status updates)
   Must return 200 quickly; process async if needed.
----------------------------------------- */
router.post("/", (req, res) => {
  // Always respond 200 so Meta doesn't retry
  res.status(200).send("OK");

  const body = req.body;
  if (!body.object || body.object !== "whatsapp_business_account") {
    return;
  }

  const entries = body.entry || [];
  for (const entry of entries) {
    const changes = entry.changes || [];
    for (const change of changes) {
      const value = change.value;
      if (!value) continue;

      // Status updates (sent, delivered, read)
      const statuses = value.statuses || [];
      for (const s of statuses) {
        console.log(
          `[WhatsApp] Status: ${s.status} for ${s.recipient_id} (id: ${s.id})`
        );
      }

      // Incoming messages
      const messages = value.messages || [];
      for (const msg of messages) {
        const from = msg.from;
        const type = msg.type;
        const id = msg.id;
        const timestamp = msg.timestamp;

        if (type === "text") {
          const text = msg.text?.body || "";
          console.log(`[WhatsApp] Message from ${from}: ${text.slice(0, 80)}`);
          // Optional: auto-reply, forward to support, store in DB, etc.
        } else {
          console.log(`[WhatsApp] Message from ${from} type=${type} id=${id}`);
        }
      }

      // Optional: handle button replies, reactions, etc. via value.messages[].button, .reaction, etc.
    }
  }
});

export default router;
