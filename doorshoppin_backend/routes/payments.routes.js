import express from "express";
import dotenv from "dotenv";
import { query } from "../config/database.js";

dotenv.config();

const router = express.Router();

const PAYCHANGU_BASE_URL = "https://api.paychangu.com";

// Read at request time so env is definitely loaded (server may load .env after this module)
function getPayChanguSecretKey() {
  const key = process.env.PAYCHANGU_SECRET_KEY || "";
  return key.trim();
}

// Safe debug: never log the full key. Use only for troubleshooting.
function debugAuthHeader(secretKey) {
  if (!secretKey) return "Authorization: (missing)";
  const prefix = secretKey.substring(0, 7);
  const suffix = secretKey.length > 10 ? secretKey.slice(-4) : "****";
  return `Authorization: Bearer ${prefix}...${suffix} (length=${secretKey.length})`;
}
// Informational only – environment is determined by the key from dashboard
const ENVIRONMENT = process.env.PAYCHANGU_ENV || "live";

// Optional operator ref IDs can be configured via env vars
const AIRTEL_OPERATOR_REF_ID =
  process.env.PAYCHANGU_AIRTEL_REF_ID ||
  "20be6c20-adeb-4b5b-a7ba-0769820df4fb"; // Default example for Airtel MWK
const TNM_OPERATOR_REF_ID = process.env.PAYCHANGU_TNM_REF_ID || "";

/**
 * Normalize Malawi phone to 9-digit format for PayChangu (no leading 0, no +265).
 * PayChangu requires exactly 9 digits, e.g. 997851901. Invalid mobile → no charge_id.
 * Accepts: 0997851901 (10 digits, leading 0) or 997851901 (9 digits) or +265997851901.
 */
function normalizePhoneToPayChangu(phone) {
  if (phone == null || phone === "") return null;
  const digits = String(phone).replace(/\D/g, "");
  if (digits.length === 10 && digits.startsWith("0")) return digits.slice(1);
  if (digits.length === 12 && digits.startsWith("265")) return digits.slice(3);
  if (digits.length === 9) return digits;
  if (digits.length > 9) return digits.slice(-9);
  return null;
}

function safeJsonParse(value) {
  if (!value || typeof value !== "string") return null;
  try {
    return JSON.parse(value);
  } catch (_) {
    return { raw: value };
  }
}

function buildPaymentResponseWithOutcome(previousResponse, outcome) {
  const previous = safeJsonParse(previousResponse);
  return JSON.stringify({
    ...(previous && typeof previous === "object" ? previous : {}),
    doorShoppinPayment: {
      ...(previous?.doorShoppinPayment || {}),
      ...outcome,
      recordedAt: new Date().toISOString(),
    },
  });
}

function normalizeTransactionStatus(status) {
  const value = String(status || "").toLowerCase();
  if (["completed", "success", "received"].includes(value)) return "success";
  if (["cancelled", "canceled"].includes(value)) return "canceled";
  if (value === "pending") return "pending";
  return "failed";
}

function paymentOutcomeReason(status) {
  const value = String(status || "").toLowerCase();
  if (["cancelled", "canceled"].includes(value)) return "provider_cancelled";
  if (value === "pending") return "provider_pending";
  if (["completed", "success", "received"].includes(value)) return "provider_success";
  return "provider_failed";
}

/* ----------------------------------------
   Payment mode for app (sandbox vs live) – backend decides via PAYCHANGU_ENV / key
   GET /api/payments/mode
---------------------------------------- */
router.get("/mode", (req, res) => {
  const paymentMode = process.env.PAYCHANGU_ENV || "live";
  res.json({ paymentMode });
});

/* ----------------------------------------
   DEBUG: safe check that PayChangu env is loaded (no secrets exposed)
   GET /api/payments/debug
---------------------------------------- */
router.get("/debug", (req, res) => {
  const key = getPayChanguSecretKey();
  res.json({
    ok: true,
    message: "PayChangu config check (safe, no secrets)",
    paychangu: {
      secretKeyPresent: key.length > 0,
      secretKeyLength: key.length,
      secretKeyPrefix: key ? `${key.substring(0, 7)}...` : null,
      env: process.env.PAYCHANGU_ENV || "(not set)",
      airtelRefId: AIRTEL_OPERATOR_REF_ID ? "set" : "missing",
      tnmRefId: TNM_OPERATOR_REF_ID ? "set" : "missing",
    },
    hint: key.length === 0
      ? "Add PAYCHANGU_SECRET_KEY to .env in doorshoppin_backend and restart the server."
      : "Key is loaded. If PayChangu still says 'Secret key missing', check key value in dashboard.",
  });
});

/* ----------------------------------------
   DIRECT MOBILE MONEY CHARGE (no hosted checkout)
---------------------------------------- */
router.post("/initiate", async (req, res) => {
  try {
    const {
      txRef: clientTxRef,
      amount,
      currency,
      phoneNumber,
      provider,
      firstName,
      lastName,
      email,
      callbackUrl,
    } = req.body;

    // txRef is optional – generate one if not provided
    const txRef =
      typeof clientTxRef === "string" && clientTxRef.trim().length > 0
        ? clientTxRef.trim()
        : `DS_${Date.now()}`;

    if (!amount || !currency || !phoneNumber || !provider) {
      return res.status(400).json({
        success: false,
        error: "amount, currency, phoneNumber and provider are required",
      });
    }

    const secretKey = getPayChanguSecretKey();
    if (!secretKey) {
      console.error("❌ [Payments] PAYCHANGU_SECRET_KEY is missing. Add it to .env and restart the server.");
      return res.status(500).json({
        success: false,
        error: "PayChangu secret key is not configured on the server",
      });
    }

    // Map provider to mobile_money_operator_ref_id
    let operatorRefId = null;
    if (provider === "airtel") {
      operatorRefId = AIRTEL_OPERATOR_REF_ID;
    } else if (provider === "tnm") {
      operatorRefId = TNM_OPERATOR_REF_ID || null;
    }

    if (!operatorRefId) {
      return res.status(500).json({
        success: false,
        error:
          "Mobile Money operator ref_id not configured for selected provider",
      });
    }

    // PayChangu requires exactly 9 digits (no leading 0). Invalid format → PayChangu won't generate charge_id.
    const mobileForPayChangu = normalizePhoneToPayChangu(phoneNumber);
    if (!mobileForPayChangu) {
      return res.status(400).json({
        success: false,
        error: "Invalid phone number. Use 9 digits (e.g. 0991234567 or 991234567).",
      });
    }

    // PayChangu Direct MoMo: amount must be integer MWK only (no decimals, no tambala). Round if client sends decimal.
    const amountMwkInteger = Math.round(parseFloat(amount));
    if (!Number.isFinite(amountMwkInteger) || amountMwkInteger < 1) {
      return res.status(400).json({
        success: false,
        error: "Invalid amount. Must be a positive number (MWK, integer).",
      });
    }

    // For Direct Charges we generate and send charge_id (required by PayChangu). txRef stays for internal reference.
    const chargeId = `PC_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;

    const requestBody = {
      mobile: mobileForPayChangu,
      mobile_money_operator_ref_id: operatorRefId,
      amount: amountMwkInteger,
      charge_id: chargeId,
      reference: txRef,
      email: email || "customer@doorshoppin.com",
      first_name: firstName || "Customer",
      last_name: lastName || "Doorshoppin",
    };

    // Debug: exact values PayChangu will see (no secrets)
    console.log("💳 [Payments] Initiating direct MoMo charge with PayChangu");
    console.log("   📌 charge_id (for verify):", chargeId);
    console.log("   📌 txRef (internal):", txRef);
    console.log("   📱 Sending mobile to PayChangu (9 digits):", mobileForPayChangu, "| raw input:", phoneNumber);
    console.log("   💰 Amount (integer MWK):", amountMwkInteger);
    console.log("   🏦 Operator ref_id:", operatorRefId);
    console.log("   🔑 Secret key length:", secretKey.length);
    console.log("   📦 Request body:", JSON.stringify(requestBody));
    console.log("   🧪 Environment:", ENVIRONMENT);
    console.log("   🔐 Auth:", debugAuthHeader(secretKey));

    const response = await fetch(
      `${PAYCHANGU_BASE_URL}/mobile-money/payments/initialize`,
      {
      method: "POST",
      headers: {
        Authorization: `Bearer ${secretKey}`,
        Accept: "application/json",
        "Content-Type": "application/json",
      },
        body: JSON.stringify(requestBody),
    });

    const text = await response.text();
    let data = {};
    try {
      data = JSON.parse(text);
    } catch (e) {
      console.error(
        "❌ [Payments] Failed to parse direct MoMo response JSON:",
        e,
        "raw:",
        text
      );
      return res.status(500).json({
        success: false,
        error: "Invalid response from PayChangu direct MoMo endpoint",
      });
    }

    // Debug: full PayChangu response (no secrets)
    console.log("⬅️ [Payments] PayChangu HTTP status:", response.status);
    console.log("⬅️ [Payments] PayChangu response (full):", JSON.stringify(data, null, 2));
    if (data.status === "failed" || response.status >= 400) {
      console.error("❌ [Payments] PayChangu error message:", data?.message ?? "(none)");
      if (data?.errors) console.error("❌ [Payments] PayChangu errors:", JSON.stringify(data.errors));
      if (data?.data && typeof data.data === "object") {
        Object.keys(data.data).forEach((k) => {
          if (Array.isArray(data.data[k])) console.error(`   PayChangu field "${k}":`, data.data[k]);
        });
      }
    }
    console.log("   PayChangu mode:", data?.data?.mode ?? "unknown");

    // For direct charges, verify PayChangu echoed back our charge_id
    const paychanguData = data?.data || {};
    const returnedChargeId = paychanguData.charge_id != null ? String(paychanguData.charge_id) : null;

    // Verify PayChangu returned our charge_id
    if (!returnedChargeId || returnedChargeId.trim() === "") {
      const paychanguError =
        data?.message ||
        (data?.errors && JSON.stringify(data.errors)) ||
        (data?.data?.mobile && Array.isArray(data.data.mobile) ? data.data.mobile.join("; ") : null) ||
        (data?.data && typeof data.data === "object" ? JSON.stringify(data.data) : null);
      console.error("❌ [Payments] PayChangu did not return charge_id.");
      console.error("   PayChangu message:", data?.message);
      console.error("   PayChangu errors:", data?.errors);
      console.error("   PayChangu data:", data?.data);
      return res.status(500).json({
        success: false,
        error: "PayChangu failed to initialize payment",
        debug: paychanguError ? { paychangu: paychanguError } : undefined,
      });
    }
    console.log("   📌 chargeId returned by PayChangu:", returnedChargeId);
    console.log("   ✓ Charge ID matches:", returnedChargeId === chargeId);

    const apiStatus = (data.status || "").toString().toLowerCase();
    const paymentMode = data?.data?.mode ?? ENVIRONMENT ?? "unknown";
    const providerRef = data?.data?.ref_id != null ? String(data.data.ref_id) : null;
    const paymentResponseJson = JSON.stringify(data);

    // Store transaction with full details (matches transactions table schema)
    try {
      await query(
        `INSERT INTO transactions (
          transaction_id, charge_id, user_id, user_email, phone_number,
          first_name, last_name, amount, method, payment_provider, payment_mode,
          provider_reference, payment_response, status, created_at
        ) VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())`,
        [
          txRef,
          chargeId,
          email || null,
          mobileForPayChangu || null,
          firstName || null,
          lastName || null,
          amountMwkInteger,
          "mobile",
          "paychangu",
          paymentMode,
          providerRef,
          paymentResponseJson,
          apiStatus === "success" ? "pending" : apiStatus,
        ]
      );
    } catch (dbErr) {
      console.error("⚠️ [Payments] Failed to insert initial transaction:", dbErr);
    }

    return res.status(200).json({
      success: true,
      message: "Payment initiated",
      txRef,
      chargeId,  // Return the charge_id we generated
      paymentMode: paymentMode,
      environment: ENVIRONMENT,
      data,
    });
  } catch (error) {
    console.error("❌ [Payments] Error initiating payment:", error?.response?.data || error.message);
    return res.status(500).json({
      success: false,
      error: "Failed to initiate payment",
      message: error.message,
      details: error?.response?.data,
    });
  }
});

/* ----------------------------------------
   RECORD APP-SIDE PAYMENT OUTCOME
   Used when customer cancels/back-outs before PayChangu returns final status.
---------------------------------------- */
router.post("/:chargeId/outcome", async (req, res) => {
  try {
    const { chargeId } = req.params;
    const {
      status = "canceled",
      reason = "customer_cancelled",
      source = "app",
    } = req.body || {};

    if (!chargeId || typeof chargeId !== "string" || chargeId.trim() === "") {
      return res.status(400).json({
        success: false,
        error: "chargeId is required",
      });
    }

    const normalizedStatus = normalizeTransactionStatus(status);
    const trimmedChargeId = chargeId.trim();
    const rows = await query(
      "SELECT status, payment_response FROM transactions WHERE charge_id = ? LIMIT 1",
      [trimmedChargeId]
    );

    if (rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: "Transaction not found",
      });
    }

    const currentStatus = normalizeTransactionStatus(rows[0].status);
    if (currentStatus === "success") {
      return res.json({
        success: true,
        message: "Payment already completed; outcome not changed",
        status: currentStatus,
      });
    }

    const paymentResponseJson = buildPaymentResponseWithOutcome(
      rows[0].payment_response,
      {
        status: normalizedStatus,
        reason,
        source,
        providerStatus: rows[0].status,
      }
    );

    await query(
      "UPDATE transactions SET status = ?, payment_response = ?, updated_at = NOW() WHERE charge_id = ?",
      [normalizedStatus, paymentResponseJson, trimmedChargeId]
    );

    return res.json({
      success: true,
      message: "Payment outcome recorded",
      status: normalizedStatus,
      reason,
    });
  } catch (error) {
    console.error("❌ [Payments] Error recording payment outcome:", error.message);
    return res.status(500).json({
      success: false,
      error: "Failed to record payment outcome",
      message: error.message,
    });
  }
});

/* ----------------------------------------
   VERIFY DIRECT MOBILE MONEY CHARGE BY charge_id
   Use charge_id from /initiate response (our txRef echoed back, or PayChangu id).
---------------------------------------- */
router.get("/verify/:chargeId", async (req, res) => {
  try {
    const { chargeId } = req.params;

    if (!chargeId || typeof chargeId !== "string" || chargeId.trim() === "") {
      return res.status(400).json({
        success: false,
        error: "chargeId is required",
      });
    }
    const trimmedChargeId = chargeId.trim();

    const secretKey = getPayChanguSecretKey();
    if (!secretKey) {
      console.error("❌ [Payments] PAYCHANGU_SECRET_KEY is missing. Add it to .env and restart the server.");
      return res.status(500).json({
        success: false,
        error: "PayChangu secret key is not configured on the server",
      });
    }

    console.log("🔎 [Payments] Verifying direct MoMo charge:", trimmedChargeId);
    console.log("   🧪 Environment:", ENVIRONMENT);

    // Direct MoMo verify: GET /mobile-money/payments/{chargeId}/verify – ONLY charge_id works
    const url = `${PAYCHANGU_BASE_URL}/mobile-money/payments/${encodeURIComponent(
      trimmedChargeId
    )}/verify`;

    const response = await fetch(url, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${secretKey}`,
        Accept: "application/json",
        "Content-Type": "application/json",
      },
    });

    const text = await response.text();
    let verifyResponse = {};
    try {
      verifyResponse = JSON.parse(text);
    } catch (e) {
      console.error(
        "❌ [Payments] Failed to parse direct MoMo verify JSON:",
        e,
        text
      );
      return res.status(500).json({
        success: false,
        error: "Invalid response from PayChangu direct MoMo verify endpoint",
      });
    }

    console.log("⬅️ [Payments] Direct MoMo verify response:", verifyResponse);

    const status = (verifyResponse.status || "").toString().toLowerCase();
    // PayChangu may put status at data.status or data.data.status (nested)
    const dataStatus = (
      verifyResponse.data?.data?.status ??
      verifyResponse.data?.status ??
      ""
    )
      .toString()
      .toLowerCase();

    // Preserve the provider status instead of collapsing cancelled into failed.
    const providerStatus = dataStatus || status;
    let finalStatus = normalizeTransactionStatus(providerStatus);
    let outcomeReason = paymentOutcomeReason(providerStatus);

    let existingPaymentResponse = null;
    let existingTransactionStatus = null;
    let existingRawTransactionStatus = null;
    try {
      const existingRows = await query(
        "SELECT status, payment_response FROM transactions WHERE charge_id = ? LIMIT 1",
        [trimmedChargeId]
      );
      existingPaymentResponse = existingRows?.[0]?.payment_response || null;
      existingRawTransactionStatus = String(existingRows?.[0]?.status || "").toLowerCase();
      existingTransactionStatus = normalizeTransactionStatus(existingRows?.[0]?.status);
      const previousOutcome = safeJsonParse(existingPaymentResponse)?.doorShoppinPayment;
      if (
        finalStatus === "success" &&
        ["completed", "received"].includes(existingRawTransactionStatus)
      ) {
        finalStatus = existingRawTransactionStatus;
      }
      if (
        finalStatus !== "success" &&
        (
          (existingTransactionStatus === "canceled" && previousOutcome?.reason === "customer_cancelled") ||
          (existingTransactionStatus === "failed" && previousOutcome?.reason === "timed_out")
        )
      ) {
        finalStatus = existingTransactionStatus;
        outcomeReason = previousOutcome.reason;
      }
    } catch (dbErr) {
      console.warn("⚠️ [Payments] Could not load existing payment outcome:", dbErr.message);
    }

    const isSuccess = finalStatus === "success" || finalStatus === "completed" || finalStatus === "received";

    const verifyData = verifyResponse?.data || {};
    const providerRef = verifyData.ref_id != null ? String(verifyData.ref_id) : null;
    const paymentResponseJson = buildPaymentResponseWithOutcome(
      existingPaymentResponse || JSON.stringify(verifyResponse),
      {
        status: finalStatus,
        reason: outcomeReason,
        source: "paychangu_verify",
        providerStatus: providerStatus || "unknown",
        paychanguVerify: verifyResponse,
      }
    );

    // Update local transaction with final status and full verify response
    try {
      await query(
        `UPDATE transactions SET status = ?, provider_reference = COALESCE(?, provider_reference), payment_response = ?, updated_at = NOW() WHERE charge_id = ?`,
        [finalStatus, providerRef, paymentResponseJson, trimmedChargeId]
      );
    } catch (dbErr) {
      console.error("⚠️ [Payments] Failed to update transaction status:", dbErr);
    }

    const paymentMode = verifyResponse?.data?.mode ?? "unknown";

    return res.status(200).json({
      success: isSuccess,
      status: finalStatus,
      environment: ENVIRONMENT,
      paymentMode,
      data: verifyResponse,
    });
  } catch (error) {
    console.error("❌ [Payments] Error verifying payment:", error?.response?.data || error.message);
    return res.status(500).json({
      success: false,
      error: "Failed to verify payment",
      message: error.message,
      details: error?.response?.data,
    });
  }
});

export default router;
