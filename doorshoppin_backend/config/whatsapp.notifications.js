/**
 * WhatsApp Order Notifications
 * Sends WhatsApp messages to customers at key order lifecycle events.
 *
 * Usage: import { notifyOrderPlaced, notifyOrderStatus } from './whatsapp.notifications.js';
 *
 * Drop this file in: doorshoppin_backend/config/whatsapp.notifications.js
 */

const GRAPH_BASE = 'https://graph.facebook.com/v21.0';

function isConfigured() {
  return !!(process.env.WHATSAPP_ACCESS_TOKEN && process.env.WHATSAPP_PHONE_NUMBER_ID);
}

/**
 * Send a plain text WhatsApp message to a phone number.
 * Only works within the 24h customer service window.
 * For first-contact messages use a pre-approved template instead.
 */
async function sendWhatsApp(toPhone, message) {
  if (!isConfigured()) {
    console.warn('[WA Notify] WhatsApp not configured — skipping');
    return { ok: false };
  }

  // Normalise: strip non-digits, ensure starts with country code
  const to = String(toPhone).replace(/\D/g, '');
  if (!to || to.length < 9) {
    console.warn('[WA Notify] Invalid phone number:', toPhone);
    return { ok: false };
  }

  const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID;
  const token = process.env.WHATSAPP_ACCESS_TOKEN;

  try {
    const res = await fetch(`${GRAPH_BASE}/${phoneNumberId}/messages`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        to,
        type: 'text',
        text: { body: message, preview_url: false },
      }),
    });

    const data = await res.json().catch(() => ({}));

    if (!res.ok) {
      const err = data.error?.message || res.statusText;
      console.error('[WA Notify] Send failed:', err);
      return { ok: false, error: err };
    }

    const messageId = data.messages?.[0]?.id;
    console.log(`[WA Notify] ✅ Sent to ${to} (id: ${messageId})`);
    return { ok: true, messageId };
  } catch (err) {
    console.error('[WA Notify] Error:', err.message);
    return { ok: false, error: err.message };
  }
}

// ─────────────────────────────────────────────────────────────
// NOTIFICATION TEMPLATES
// Customise the messages below to match your brand voice.
// ─────────────────────────────────────────────────────────────

/**
 * Sent immediately when a new order is placed.
 * Call this right after the order is saved to the database.
 *
 * @param {string} phone - Customer phone (any format)
 * @param {object} order - { trackingId, total, paymentMethod, name, items[] }
 */
export async function notifyOrderPlaced(phone, order) {
  const { trackingId, total, paymentMethod, name, items = [] } = order;
  const isCash = paymentMethod === 'cash';
  const itemSummary = items.slice(0, 3).map(i => `• ${i.name} x${i.quantity}`).join('\n');
  const moreItems = items.length > 3 ? `\n• +${items.length - 3} more item(s)` : '';

  const message = [
    `🛒 *Order Confirmed!*`,
    ``,
    `Hi ${name}, your DoorShoppin order has been placed successfully.`,
    ``,
    `📦 *Order:* ${trackingId}`,
    `💰 *Total:* MWK ${Number(total).toLocaleString()}`,
    `💳 *Payment:* ${isCash ? 'Cash on Delivery' : 'Mobile Money'}`,
    ``,
    `*Items:*`,
    itemSummary + moreItems,
    ``,
    isCash
      ? `Our rider will collect payment on delivery. Please have the exact amount ready.`
      : `Your payment has been received. We are preparing your order now.`,
    ``,
    `Track your order or contact us: https://doorshoppin.com`,
  ].join('\n');

  return sendWhatsApp(phone, message);
}

/**
 * Sent when an admin updates the order status.
 * Call this inside the admin PATCH /orders/:id/status route.
 *
 * @param {string} phone - Customer phone
 * @param {object} order - { trackingId, status, name, estimatedTime? }
 */
export async function notifyOrderStatus(phone, order) {
  const { trackingId, status, name, estimatedTime } = order;

  const STATUS_MESSAGES = {
    confirmed: {
      emoji: '✅',
      title: 'Order Confirmed',
      body: `Great news! Your order *${trackingId}* has been confirmed and we are preparing it now.`,
    },
    preparing: {
      emoji: '👨‍🍳',
      title: 'Order Being Prepared',
      body: `Your order *${trackingId}* is currently being prepared.`,
    },
    ready: {
      emoji: '📦',
      title: 'Order Ready',
      body: `Your order *${trackingId}* is packed and ready${estimatedTime ? `, estimated delivery in ${estimatedTime}` : ''}.`,
    },
    out_for_delivery: {
      emoji: '🏍️',
      title: 'Out for Delivery',
      body: `Your order *${trackingId}* is on its way! Our rider is heading to your location${estimatedTime ? ` — ETA ${estimatedTime}` : ''}.`,
    },
    delivered: {
      emoji: '🎉',
      title: 'Order Delivered',
      body: `Your order *${trackingId}* has been delivered. Enjoy!\n\nThank you for choosing DoorShoppin. We hope to see you again soon! 😊`,
    },
    cancelled: {
      emoji: '❌',
      title: 'Order Cancelled',
      body: `Your order *${trackingId}* has been cancelled. If you have questions, reply to this message or contact us at https://doorshoppin.com`,
    },
  };

  const template = STATUS_MESSAGES[status];
  if (!template) {
    console.warn('[WA Notify] Unknown status:', status);
    return { ok: false };
  }

  const message = [
    `${template.emoji} *${template.title}*`,
    ``,
    `Hi ${name},`,
    template.body,
    ``,
    `Need help? Just reply to this message — we're happy to assist.`,
  ].join('\n');

  return sendWhatsApp(phone, message);
}

/**
 * Sent when payment is confirmed via PayChangu webhook.
 *
 * @param {string} phone - Customer phone
 * @param {object} order - { trackingId, total, name }
 */
export async function notifyPaymentConfirmed(phone, order) {
  const { trackingId, total, name } = order;

  const message = [
    `💚 *Payment Received*`,
    ``,
    `Hi ${name}, we have received your payment of *MWK ${Number(total).toLocaleString()}* for order *${trackingId}*.`,
    ``,
    `Your order is now being processed. We will notify you when it is on its way.`,
  ].join('\n');

  return sendWhatsApp(phone, message);
}
