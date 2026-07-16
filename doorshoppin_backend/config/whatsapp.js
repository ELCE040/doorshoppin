/**
 * WhatsApp Cloud API (Meta) – send OTP and optional messaging.
 * Set WHATSAPP_ACCESS_TOKEN, WHATSAPP_PHONE_NUMBER_ID in .env.
 * For webhook verification set WHATSAPP_VERIFY_TOKEN.
 * API: https://developers.facebook.com/docs/whatsapp/cloud-api
 */

const WHATSAPP_GRAPH_BASE = "https://graph.facebook.com/v21.0";

function isWhatsAppConfigured() {
  return !!(
    process.env.WHATSAPP_ACCESS_TOKEN &&
    process.env.WHATSAPP_PHONE_NUMBER_ID
  );
}

/**
 * Recipient phone: E.164 without '+' (e.g. 265991234567).
 */
function toWhatsAppRecipient(e164) {
  return String(e164).replace(/\D/g, "");
}

/**
 * Send OTP via WhatsApp.
 * Uses a message template if WHATSAPP_OTP_TEMPLATE_NAME is set (required for users who haven't messaged in 24h).
 * Otherwise sends a plain text message (only works within 24h conversation window).
 *
 * @param {string} toE164 - Recipient phone E.164 (e.g. +265991234567)
 * @param {string} code - 6-digit OTP code
 * @returns {Promise<{ ok: boolean, error?: string, messageId?: string }>}
 */
export async function sendOtpWhatsApp(toE164, code) {
  if (!isWhatsAppConfigured()) {
    return { ok: false, error: "WhatsApp not configured" };
  }

  const to = toWhatsAppRecipient(toE164);
  if (!to || to.length < 10) {
    return { ok: false, error: "Invalid phone number" };
  }

  const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID;
  const url = `${WHATSAPP_GRAPH_BASE}/${phoneNumberId}/messages`;
  const token = process.env.WHATSAPP_ACCESS_TOKEN;

  const templateName = process.env.WHATSAPP_OTP_TEMPLATE_NAME;
  const templateLang = process.env.WHATSAPP_OTP_TEMPLATE_LANG || "en";

  let body;

  if (templateName) {
    // Template message (works outside 24h window; template must be approved in Meta Business Manager)
    body = {
      messaging_product: "whatsapp",
      to,
      type: "template",
      template: {
        name: templateName,
        language: { code: templateLang },
        components: [
          {
            type: "body",
            parameters: [{ type: "text", text: code }],
          },
        ],
      },
    };
  } else {
    // Plain text (only works within 24h of user's last message)
    body = {
      messaging_product: "whatsapp",
      to,
      type: "text",
      text: {
        body: `Your DoorShoppin verification code is: ${code}. Valid for 10 minutes.`,
      },
    };
  }

  try {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(body),
    });

    const data = await res.json().catch(() => ({}));

    if (!res.ok) {
      const errMsg =
        data.error?.message || data.error?.error_user_msg || res.statusText;
      console.error("❌ WhatsApp API error:", res.status, errMsg);
      return { ok: false, error: errMsg };
    }

    const messageId = data.messages?.[0]?.id;
    console.log(
      `✅ WhatsApp OTP sent to ${toE164}${messageId ? ` (id: ${messageId})` : ""}`
    );
    return { ok: true, messageId };
  } catch (err) {
    const msg = err.message || String(err);
    console.error("❌ WhatsApp send error:", msg);
    return { ok: false, error: msg };
  }
}

export { isWhatsAppConfigured };
