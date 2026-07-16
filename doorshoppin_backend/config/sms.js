/**
 * SMS sending for OTP (Vonage / Nexmo).
 * Set VONAGE_API_KEY, VONAGE_API_SECRET, VONAGE_BRAND_NAME in .env to send real SMS.
 * If not set, sendOtpSms returns { ok: false } and the backend falls back to logging the code.
 * API: https://developer.vonage.com/messaging/sms/overview
 */

const VONAGE_SMS_URL = "https://rest.nexmo.com/sms/json";

function isSmsConfigured() {
  return !!(
    process.env.VONAGE_API_KEY &&
    process.env.VONAGE_API_SECRET &&
    process.env.VONAGE_BRAND_NAME
  );
}

/**
 * Send OTP by SMS to the given E.164 phone number using Vonage SMS API.
 * @param {string} toE164 - Recipient phone (e.g. +265997851901)
 * @param {string} code - 6-digit OTP code
 * @returns {Promise<{ ok: boolean, error?: string }>}
 */
export async function sendOtpSms(toE164, code) {
  if (!isSmsConfigured()) {
    return { ok: false, error: "SMS not configured" };
  }

  const from = process.env.VONAGE_BRAND_NAME; // Alphanumeric sender (e.g. "DoorShoppin")
  const to = toE164.replace(/\D/g, ""); // Vonage expects digits only
  const text = `Your DoorShoppin verification code is: ${code}. Valid for 10 minutes.`;

  const auth = Buffer.from(
    `${process.env.VONAGE_API_KEY}:${process.env.VONAGE_API_SECRET}`
  ).toString("base64");

  const body = new URLSearchParams({
    from: from,
    to: to,
    text: text,
  }).toString();

  try {
    const res = await fetch(VONAGE_SMS_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Authorization: `Basic ${auth}`,
      },
      body,
    });

    const data = await res.json().catch(() => ({}));

    if (!res.ok) {
      const errMsg = data["error-text"] || data["error"] || res.statusText;
      console.error("❌ Vonage SMS HTTP error:", res.status, errMsg);
      return { ok: false, error: errMsg };
    }

    const messages = data.messages || [];
    const first = messages[0];
    if (first && first.status === "0") {
      console.log(`✅ SMS sent to ${toE164} (message-id: ${first["message-id"] || "ok"})`);
      return { ok: true };
    }

    const errMsg = first ? (first["error-text"] || first.status) : "No response";
    console.error("❌ Vonage SMS API error:", errMsg);
    return { ok: false, error: errMsg };
  } catch (err) {
    const msg = err.message || String(err);
    console.error("❌ SMS send error:", msg);
    return { ok: false, error: msg };
  }
}

export { isSmsConfigured };
