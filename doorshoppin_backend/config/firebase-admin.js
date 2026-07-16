/**
 * Firebase Admin SDK - used for FCM (Firebase Cloud Messaging) on the backend.
 * Requires: service account JSON file path in FIREBASE_SERVICE_ACCOUNT_PATH or GOOGLE_APPLICATION_CREDENTIALS.
 */
import admin from "firebase-admin";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

let initialized = false;

/**
 * Initialize Firebase Admin. Call once at startup.
 * Uses FIREBASE_SERVICE_ACCOUNT_PATH or GOOGLE_APPLICATION_CREDENTIALS (path to JSON).
 */
export function initializeFirebaseAdmin() {
  if (initialized) return admin;

  const credPath =
    process.env.FIREBASE_SERVICE_ACCOUNT_PATH ||
    process.env.GOOGLE_APPLICATION_CREDENTIALS;

  if (!credPath) {
    console.warn(
      "⚠️ FIREBASE_SERVICE_ACCOUNT_PATH or GOOGLE_APPLICATION_CREDENTIALS not set; FCM will be disabled"
    );
    return null;
  }

  const resolvedPath = path.isAbsolute(credPath)
    ? credPath
    : path.resolve(__dirname, "..", credPath);

  try {
    admin.initializeApp({
      credential: admin.credential.cert(resolvedPath),
    });
    initialized = true;
    console.log("✅ Firebase Admin initialized (FCM enabled)");
    return admin;
  } catch (err) {
    console.error("❌ Firebase Admin init failed:", err.message);
    return null;
  }
}

/**
 * Create a Firebase custom token for the given uid (e.g. for phone auth without reCAPTCHA).
 * Caller must ensure Firebase Admin is initialized.
 * @param {string} uid - Firebase Auth UID (e.g. "phone_265991234567")
 * @param {Record<string, unknown>} [claims] - Optional custom claims (e.g. { phone_number: "+265..." })
 * @returns {Promise<string>} - Custom token for signInWithCustomToken on the client
 */
export async function createFirebaseCustomToken(uid, claims = {}) {
  if (!admin.apps.length) {
    throw new Error("Firebase Admin not initialized");
  }
  return admin.auth().createCustomToken(uid, claims);
}

/**
 * Send FCM notification to a single device token.
 * Uses FCM HTTP v1 API: POST .../v1/projects/{project_id}/messages:send
 * @param {string} token - FCM device token
 * @param {string} title - Notification title
 * @param {string} body - Notification body
 * @param {Record<string, string>} [data] - Optional data payload (e.g. type, orderId)
 * @param {{ validateOnly?: boolean }} [opts] - validateOnly: test without delivering (FCM REST validate_only; SDK dryRun)
 * @returns {Promise<boolean>} - true if sent successfully
 */
export async function sendFcmNotification(token, title, body, data = {}, opts = {}) {
  if (!initialized) {
    initializeFirebaseAdmin();
  }
  if (!admin.apps.length) {
    console.warn("⚠️ FCM skipped: Firebase Admin not initialized");
    return false;
  }

  try {
    const message = {
      token,
      notification: { title, body },
      data: Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, String(v)])
      ),
      android: { priority: "high" },
      apns: { payload: { aps: { sound: "default" } } },
    };
    await admin.messaging().send(message, opts.validateOnly === true);
    console.log("✅ FCM sent:", title);
    return true;
  } catch (err) {
    if (err.code === "messaging/invalid-registration-token" || err.code === "messaging/registration-token-not-registered") {
      console.warn("⚠️ FCM token invalid or expired:", err.message);
    } else {
      console.error("❌ FCM send error:", err.message);
    }
    return false;
  }
}

const ADMIN_TOPIC = "admin_orders";

/**
 * Subscribe an FCM registration token to the admin topic so it receives admin_orders notifications.
 * Call this when the admin panel (or admin app) registers with is_admin: true.
 * @param {string} token - FCM device/browser token
 * @returns {Promise<boolean>} - true if subscribed successfully
 */
export async function subscribeTokenToAdminTopic(token) {
  if (!initialized) {
    initializeFirebaseAdmin();
  }
  if (!admin.apps.length) {
    console.warn("⚠️ FCM skipped: Firebase Admin not initialized");
    return false;
  }
  try {
    const response = await admin.messaging().subscribeToTopic([token], ADMIN_TOPIC);
    const ok = response.successCount > 0;
    if (ok) console.log("✅ Admin token subscribed to topic:", ADMIN_TOPIC);
    else console.warn("⚠️ subscribeToAdminTopic: successCount 0", response);
    return ok;
  } catch (err) {
    console.error("❌ subscribeToAdminTopic error:", err.message);
    return false;
  }
}

/**
 * Send an FCM notification to an admin topic so all admin devices receive it.
 * Admin apps should subscribe to this topic (e.g. \"admin_orders\").
 * Uses FCM HTTP v1 API: POST .../v1/projects/{project_id}/messages:send
 * @param {{ validateOnly?: boolean }} [opts] - validateOnly: test without delivering (FCM REST validate_only; SDK dryRun)
 */
export async function sendFcmToAdminTopic(title, body, data = {}, opts = {}) {
  if (!initialized) {
    initializeFirebaseAdmin();
  }
  if (!admin.apps.length) {
    console.warn("⚠️ FCM skipped: Firebase Admin not initialized");
    return false;
  }

  try {
    const message = {
      topic: ADMIN_TOPIC,
      notification: { title, body },
      data: Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, String(v)])
      ),
      android: { priority: "high" },
      apns: { payload: { aps: { sound: "default" } } },
    };
    await admin.messaging().send(message, opts.validateOnly === true);
    console.log("✅ FCM admin topic sent:", title);
    return true;
  } catch (err) {
    console.error("❌ FCM admin topic send error:", err.message);
    return false;
  }
}
