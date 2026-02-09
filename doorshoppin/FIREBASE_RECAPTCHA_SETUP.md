# Firebase reCAPTCHA Configuration Guide

## Your reCAPTCHA Site Key
```
6Ld_T1AsAAAAADlv72bLULUJmDAvf0jXGUTppXA1
```

## Step 1: Configure in Firebase Console

### Option A: Using Firebase Console (Recommended)

1. **Go to Firebase Console**
   - Visit: https://console.firebase.google.com
   - Select your project: `doorshoppin-7f073`

2. **Navigate to Authentication Settings**
   - Click on **Authentication** in the left sidebar
   - Click on the **Settings** tab
   - Scroll down to **reCAPTCHA Enterprise** section

3. **Add reCAPTCHA Site Key**
   - Click **Add site key** or **Configure**
   - Enter your site key: `6Ld_T1AsAAAAADlv72bLULUJmDAvf0jXGUTppXA1`
   - Select **reCAPTCHA v2** (if prompted)
   - Save the configuration

### Option B: Using Firebase CLI

If you prefer using command line:

```bash
# Make sure you're logged in
firebase login

# Set the reCAPTCHA site key (if Firebase CLI supports it)
# Note: This might need to be done through Console
```

## Step 2: Enable Phone Authentication

1. **Go to Authentication → Sign-in method**
2. **Enable Phone Authentication**
   - Click on **Phone** provider
   - Toggle **Enable** to ON
   - Save

## Step 3: Enable Billing (Required for Phone Auth)

Phone authentication requires Firebase Blaze plan:

1. **Go to Project Settings → Usage and billing**
2. **Upgrade to Blaze Plan**
   - Click **Modify plan**
   - Select **Blaze Plan** (Pay as you go)
   - Complete billing setup

**Note:** Blaze plan has a free tier, so you won't be charged unless you exceed free limits.

## Step 4: Verify Configuration

After configuration, test phone authentication:

1. Run your app
2. Try phone authentication
3. Check debug logs for any errors

## Troubleshooting

### Error: "BILLING_NOT_ENABLED"
- **Solution:** Enable billing/Blaze plan in Firebase Console

### Error: "No Recaptcha Enterprise siteKey configured"
- **Solution:** Add the reCAPTCHA site key in Firebase Console → Authentication → Settings

### Error: "Invalid reCAPTCHA key"
- **Solution:** Verify the key is correct and matches your Firebase project domain

## Additional Notes

- The reCAPTCHA key is configured server-side in Firebase Console
- No code changes are needed once configured in Console
- The key will be automatically used by Firebase Auth SDK
- Make sure your app's package name matches Firebase project configuration

## Support

If you continue to have issues:
1. Check Firebase Console → Authentication → Settings for any error messages
2. Verify your `google-services.json` is up to date
3. Ensure your app's SHA-1 fingerprint is added to Firebase Console
