import express from "express";
import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";
import { getDatabase, query } from "../config/database.js";
import { v4 as uuidv4 } from "uuid";
import { createFirebaseCustomToken } from "../config/firebase-admin.js";
import { sendOtpSms, isSmsConfigured } from "../config/sms.js";

/** Optional WhatsApp module – loads dynamically so server starts even if config/whatsapp.js is missing. */
let whatsappModule = null;
async function getWhatsApp() {
  if (whatsappModule !== null) return whatsappModule;
  try {
    whatsappModule = await import("../config/whatsapp.js");
    return whatsappModule;
  } catch (e) {
    console.warn("⚠️ config/whatsapp.js not found – WhatsApp OTP disabled. Deploy the file to enable.");
    whatsappModule = {
      sendOtpWhatsApp: async () => ({ ok: false, error: "WhatsApp not configured" }),
      isWhatsAppConfigured: () => false,
    };
    return whatsappModule;
  }
}

const router = express.Router();

/* ----------------------------------------
   PHONE OTP STORE (no reCAPTCHA flow)
   In-memory: { phoneNormalized -> { code, expiresAt } }
   Optional: set env TEST_PHONE_OTP=123456 to use fixed code for all numbers (dev only)
----------------------------------------- */
const otpStore = new Map();
const OTP_EXPIRY_MS = 10 * 60 * 1000; // 10 minutes
const OTP_LENGTH = 6;

function normalizePhoneForStorage(phone) {
  const digits = String(phone).replace(/\D/g, "");
  return digits ? `+${digits}` : "";
}

function generateOtp() {
  return String(Math.floor(100000 + Math.random() * 900000)).slice(0, OTP_LENGTH);
}

function cleanupExpiredOtps() {
  const now = Date.now();
  for (const [key, data] of otpStore.entries()) {
    if (data.expiresAt < now) otpStore.delete(key);
  }
}

/* ----------------------------------------
   HEALTH CHECK
----------------------------------------- */
router.get("/health", (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.status(200).json({
    status: "OK",
    message: "Doorshoppin Auth service is running",
    timestamp: new Date().toISOString()
  });
});

/* ----------------------------------------
   REGISTER USER (supports email or phone)
----------------------------------------- */
router.post("/register", async (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  
  try {
    const { name, email, phone, password } = req.body;

    // Validate - must have either email or phone
    if (!name || !password) {
      return res.status(400).json({ error: "Name and password are required" });
    }

    if (!email && !phone) {
      return res.status(400).json({ error: "Either email or phone number is required" });
    }

    if (password.length < 6) {
      return res.status(400).json({ error: "Password must be at least 6 characters" });
    }

    // Validate email if provided
    if (email) {
      const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
      if (!emailRegex.test(email)) {
        return res.status(400).json({ error: "Invalid email format" });
      }
    }

    // Validate phone if provided
    if (phone && phone.length < 8) {
      return res.status(400).json({ error: "Invalid phone number format" });
    }

    // Check existing user (email or phone must be unique)
    let checkSql = "";
    let checkParams = [];

    if (email && phone) {
      checkSql = "SELECT id FROM users WHERE email = ? OR phone = ?";
      checkParams = [email.toLowerCase(), phone];
    } else if (email) {
      checkSql = "SELECT id FROM users WHERE email = ?";
      checkParams = [email.toLowerCase()];
    } else {
      checkSql = "SELECT id FROM users WHERE phone = ?";
      checkParams = [phone];
    }

    const existingUsers = await query(checkSql, checkParams);
    
    if (existingUsers.length > 0) {
      return res.status(400).json({ error: "User with this email or phone already exists" });
    }

    // Hash password
    const hashedPassword = await bcrypt.hash(password, 10);

    // Generate firebase_uid (required field, but we can use a UUID for non-firebase users)
    const firebaseUid = uuidv4();

    // Create new user
    const insertSql = `
      INSERT INTO users (firebase_uid, name, email, password, phone, created_at)
      VALUES (?, ?, ?, ?, ?, NOW())
    `;

    const result = await query(insertSql, [
      firebaseUid,
      name,
      email ? email.toLowerCase() : null,
      hashedPassword,
      phone || null,
    ]);

    const userId = result.insertId;

    // Generate token
    const token = jwt.sign(
      {
        userId: userId.toString(),
        email: email ? email.toLowerCase() : null,
      },
      process.env.JWT_SECRET,
      { expiresIn: "7d" }
    );

    return res.status(201).json({
      message: "User registered successfully",
      token,
      user: {
        id: userId,
        name: name,
        email: email ? email.toLowerCase() : null,
        phone: phone || null,
      },
    });
  } catch (err) {
    console.error("❌ Registration Error:", err);
    return res.status(500).json({
      error: "Internal server error",
      message: err.message || "An unexpected error occurred",
    });
  }
});

/* ----------------------------------------
   LOGIN USER (supports email or phone)
----------------------------------------- */
router.post("/login", async (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  
  try {
    const { email, phone, password } = req.body;

    // Validate - must have either email or phone
    if (!password) {
      return res.status(400).json({ error: "Password is required" });
    }

    if (!email && !phone) {
      return res.status(400).json({ error: "Either email or phone number is required" });
    }

    // Find user by email or phone
    let sql = "";
    let params = [];

    if (email) {
      sql = "SELECT id, name, email, password, phone FROM users WHERE email = ?";
      params = [email.toLowerCase()];
    } else {
      sql = "SELECT id, name, email, password, phone FROM users WHERE phone = ?";
      params = [phone];
    }

    const users = await query(sql, params);

    if (users.length === 0) {
      return res.status(401).json({ error: "Invalid credentials" });
    }

    const user = users[0];

    // Password check
    const match = await bcrypt.compare(password, user.password);
    if (!match) {
      return res.status(401).json({ error: "Invalid credentials" });
    }

    // Update last_login
    await query("UPDATE users SET last_login = NOW() WHERE id = ?", [user.id]);

    // Get user ID
    const userId = user.id.toString();

    // Generate token
    const token = jwt.sign(
      {
        userId: userId,
        email: user.email,
      },
      process.env.JWT_SECRET,
      { expiresIn: "7d" }
    );

    return res.json({
      message: "Login successful",
      token,
      user: {
        id: userId,
        name: user.name,
        email: user.email,
        phone: user.phone,
      },
    });
  } catch (err) {
    console.error("❌ Login Error:", err);
    return res.status(500).json({
      error: "Internal server error",
      message: err.message,
    });
  }
});

/* ----------------------------------------
   PHONE AUTH WITHOUT reCAPTCHA
   Request OTP: store a 6-digit code (no SMS required for dev; set TEST_PHONE_OTP for fixed code)
   Verify OTP: return Firebase custom token → app uses signInWithCustomToken (no captcha)
----------------------------------------- */
router.post("/phone/request-otp", async (req, res) => {
  res.setHeader("Content-Type", "application/json");
  try {
    const { phone } = req.body || {};
    const normalized = normalizePhoneForStorage(phone);
    if (!normalized || normalized.length < 10) {
      return res.status(400).json({
        success: false,
        error: "Invalid phone number. Use E.164 (e.g. +265991234567).",
      });
    }

    cleanupExpiredOtps();

    const fixedCode = process.env.TEST_PHONE_OTP;
    const code = fixedCode && fixedCode.length === 6 ? fixedCode : generateOtp();
    otpStore.set(normalized, {
      code,
      expiresAt: Date.now() + OTP_EXPIRY_MS,
    });

    // Prefer WhatsApp if configured, then SMS; otherwise log only (dev)
    const whatsapp = await getWhatsApp();
    let sent = false;
    if (whatsapp.isWhatsAppConfigured()) {
      const waResult = await whatsapp.sendOtpWhatsApp(normalized, code);
      if (waResult.ok) sent = true;
      else console.error(`[Phone OTP] WhatsApp failed for ${normalized}:`, waResult.error);
    }
    if (!sent && isSmsConfigured()) {
      const smsResult = await sendOtpSms(normalized, code);
      if (!smsResult.ok) {
        console.error(`[Phone OTP] SMS failed for ${normalized}:`, smsResult.error);
        return res.status(500).json({
          success: false,
          error: "Failed to send verification code. Please try again or contact support.",
        });
      }
      sent = true;
    }
    if (!sent) {
      console.log(`[Phone OTP] ${normalized} → code: ${code} (expires in 10 min). Set WHATSAPP_* or VONAGE_* to send.`);
      if (whatsapp.isWhatsAppConfigured() || isSmsConfigured()) {
        return res.status(500).json({
          success: false,
          error: "Failed to send verification code. Please try again or contact support.",
        });
      }
    }

    return res.status(200).json({ success: true });
  } catch (err) {
    console.error("❌ request-otp error:", err);
    return res.status(500).json({
      success: false,
      error: err.message || "Failed to request OTP",
    });
  }
});

router.post("/phone/verify-otp", async (req, res) => {
  res.setHeader("Content-Type", "application/json");
  try {
    const { phone, code } = req.body || {};
    const normalized = normalizePhoneForStorage(phone);
    if (!normalized || normalized.length < 10) {
      return res.status(400).json({
        success: false,
        error: "Invalid phone number.",
      });
    }
    if (!code || String(code).length !== 6) {
      return res.status(400).json({
        success: false,
        error: "Invalid or missing 6-digit code.",
      });
    }

    cleanupExpiredOtps();

    const stored = otpStore.get(normalized);
    if (!stored) {
      return res.status(400).json({
        success: false,
        error: "No OTP found for this number or it expired. Request a new code.",
      });
    }
    if (stored.code !== String(code).trim()) {
      return res.status(400).json({
        success: false,
        error: "Wrong code. Please try again.",
      });
    }

    otpStore.delete(normalized);

    const uid = "phone_" + normalized.replace(/\D/g, "");
    const customToken = await createFirebaseCustomToken(uid, {
      phone_number: normalized,
    });

    return res.status(200).json({
      success: true,
      token: customToken,
    });
  } catch (err) {
    console.error("❌ verify-otp error:", err);
    return res.status(500).json({
      success: false,
      error: err.message || "Verification failed",
    });
  }
});

export default router;
export { router };
