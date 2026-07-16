/**
 * POST /api/whatsapp/send-media
 * Uploads a file to WhatsApp Cloud API and sends it to a contact.
 * Body: multipart/form-data — file, to, type (image|document|audio|video), caption?
 *
 * Add to server.js:
 *   import sendMediaRoute from './routes/whatsapp.sendmedia.js';
 *   app.use('/api/whatsapp', sendMediaRoute);
 *
 * Requires: npm install multer node-fetch (or use native fetch in Node 18+)
 */

import express from 'express';
import multer from 'multer';
import { query } from '../config/database.js';
import jwt from 'jsonwebtoken';

const router = express.Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 16 * 1024 * 1024 } }); // 16MB max

const GRAPH_BASE = 'https://graph.facebook.com/v21.0';

function authenticateAdmin(req, res, next) {
  try {
    const token = (req.headers.authorization || '').replace('Bearer ', '');
    if (!token) return res.status(401).json({ success: false, error: 'Unauthorized' });
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    if (!decoded.adminId) return res.status(401).json({ success: false, error: 'Admin only' });
    req.adminId = decoded.adminId;
    next();
  } catch {
    return res.status(401).json({ success: false, error: 'Invalid token' });
  }
}

/**
 * POST /api/whatsapp/send-media
 */
router.post('/send-media', authenticateAdmin, upload.single('file'), async (req, res) => {
  try {
    const { to, type, caption } = req.body;
    const file = req.file;

    if (!to || !file) {
      return res.status(400).json({ success: false, error: 'to and file are required' });
    }

    const phone = String(to).replace(/\D/g, '');
    const accessToken = process.env.WHATSAPP_ACCESS_TOKEN;
    const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID;

    if (!accessToken || !phoneNumberId) {
      return res.status(500).json({ success: false, error: 'WhatsApp not configured' });
    }

    // Step 1: Upload media to WhatsApp
    const uploadForm = new FormData();
    uploadForm.append('messaging_product', 'whatsapp');
    uploadForm.append('file', new Blob([file.buffer], { type: file.mimetype }), file.originalname);

    const uploadRes = await fetch(`${GRAPH_BASE}/${phoneNumberId}/media`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${accessToken}` },
      body: uploadForm,
    });

    const uploadData = await uploadRes.json().catch(() => ({}));
    if (!uploadRes.ok) {
      const err = uploadData.error?.message || uploadRes.statusText;
      return res.status(uploadRes.status).json({ success: false, error: err });
    }

    const mediaId = uploadData.id;
    if (!mediaId) return res.status(500).json({ success: false, error: 'No media ID returned' });

    // Step 2: Determine WhatsApp message type from mimetype
    const mime = file.mimetype;
    let waType = type || 'document';
    if (mime.startsWith('image/')) waType = 'image';
    else if (mime.startsWith('video/')) waType = 'video';
    else if (mime.startsWith('audio/')) waType = 'audio';

    // Step 3: Send the media message
    const msgPayload = {
      messaging_product: 'whatsapp',
      to: phone,
      type: waType,
      [waType]: {
        id: mediaId,
        ...(caption && (waType === 'image' || waType === 'video') ? { caption } : {}),
        ...(waType === 'document' ? { filename: file.originalname } : {}),
      },
    };

    const sendRes = await fetch(`${GRAPH_BASE}/${phoneNumberId}/messages`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${accessToken}` },
      body: JSON.stringify(msgPayload),
    });

    const sendData = await sendRes.json().catch(() => ({}));
    if (!sendRes.ok) {
      const err = sendData.error?.message || sendRes.statusText;
      return res.status(sendRes.status).json({ success: false, error: err });
    }

    const waMessageId = sendData.messages?.[0]?.id || null;

    // Step 4: Save to database
    await query(
      `INSERT INTO whatsapp_messages (wa_message_id, contact_phone, direction, message_type, body, media_url, status, wa_timestamp)
       VALUES (?, ?, 'outbound', ?, ?, ?, 'sent', NOW())`,
      [waMessageId, phone, waType, caption || file.originalname, mediaId]
    );

    return res.json({ success: true, messageId: waMessageId });
  } catch (err) {
    console.error('[WhatsApp SendMedia] Error:', err.message);
    return res.status(500).json({ success: false, error: err.message });
  }
});

export default router;
