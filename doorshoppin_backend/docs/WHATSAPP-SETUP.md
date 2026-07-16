# WhatsApp Cloud API – OTP & Webhook Setup

Doorshoppin can send verification codes via **WhatsApp Cloud API** (Meta) and receive webhook events.

## 1. Meta Developer Console

1. Go to [Meta for Developers](https://developers.facebook.com/) and create or select an app.
2. Add the **WhatsApp** product to the app (Dashboard → Add Product → WhatsApp).
3. Open **WhatsApp → API Setup**:
   - **From**: Add a phone number (or use the test number). Note the **Phone number ID**.
   - **Access token**: Use “Temporary” for testing, or create a **System User** and generate a permanent token for production.

## 2. Environment variables

Copy from `.env.example` and set in `.env`:

| Variable | Description |
|----------|-------------|
| `WHATSAPP_ACCESS_TOKEN` | Token from API Setup (temporary or permanent). |
| `WHATSAPP_PHONE_NUMBER_ID` | Phone number ID from “From” in API Setup. |
| `WHATSAPP_VERIFY_TOKEN` | Any string you choose; must match the value you enter in the webhook config in Meta. |
| `WHATSAPP_OTP_TEMPLATE_NAME` | (Optional) Name of an approved OTP template for users outside the 24h window. |
| `WHATSAPP_OTP_TEMPLATE_LANG` | (Optional) Template language code, e.g. `en`. Default `en`. |

Without a template, the app sends a **plain text** OTP. That only works if the user has messaged you in the last 24 hours. For first-time or cold users, create and use an **OTP template** (see below).

## 3. Webhook configuration in Meta

1. In your app: **WhatsApp → Configuration**.
2. Under **Webhook**:
   - **Callback URL**: `https://YOUR_DOMAIN/api/webhooks/whatsapp`  
     If the API is under a path (e.g. `https://example.com/doorshoppin_backend`), use:  
     `https://example.com/doorshoppin_backend/api/webhooks/whatsapp`
   - **Verify token**: Same string as `WHATSAPP_VERIFY_TOKEN` in `.env`.
3. Click **Verify and save**.
4. Subscribe to **messages** (and optionally **message_deliveries**, **message_reads**) so your backend receives incoming messages and status updates.

Meta will send a **GET** request to your callback URL with `hub.mode=subscribe`, `hub.verify_token=YOUR_TOKEN`, `hub.challenge=NUMBER`. The server responds with `hub.challenge` to complete verification.

## 4. OTP template (recommended for production)

For users who have not messaged you in the last 24 hours, WhatsApp requires an **approved template**.

1. **Meta Business Manager** → **WhatsApp Manager** → **Message templates** → Create.
2. Create a template, e.g.:
   - **Name**: `otp_verification` (use this in `WHATSAPP_OTP_TEMPLATE_NAME`).
   - **Category**: Utility or Authentication (if available).
   - **Body**: `Your DoorShoppin verification code is {{1}}. Valid for 10 minutes.`
   - **Language**: e.g. English.
3. Submit for approval. After approval, set in `.env`:
   - `WHATSAPP_OTP_TEMPLATE_NAME=otp_verification`
   - `WHATSAPP_OTP_TEMPLATE_LANG=en`

The backend sends the 6-digit code as the first (and only) body parameter.

## 5. Behaviour

- **Request OTP** (`POST /api/auth/phone/request-otp`): If WhatsApp is configured, the backend tries WhatsApp first. If that fails or WhatsApp is not configured, it falls back to SMS (Vonage) if configured. If neither is set, the code is only logged (dev).
- **Webhook** (`GET` / `POST` `/api/webhooks/whatsapp`):  
  - **GET**: Used by Meta for verification; returns the challenge when the verify token matches.  
  - **POST**: Receives incoming messages and status updates; responds with `200 OK` and logs events. You can extend the handler to auto-reply or store messages.

## 6. Local testing (ngrok)

Meta must reach your server over HTTPS. For local development:

1. Run [ngrok](https://ngrok.com/): `ngrok http 3001`
2. Use the ngrok URL in the webhook: `https://xxxx.ngrok.io/api/webhooks/whatsapp` (or with `/doorshoppin_backend` if applicable).
3. Use the same `WHATSAPP_VERIFY_TOKEN` in Meta and in `.env`.

After saving, “Verify and save” in Meta should succeed and incoming messages will appear in your server logs.
