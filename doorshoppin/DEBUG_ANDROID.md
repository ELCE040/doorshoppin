# Debug on Android console

How to see payment (and other) debug logs when running the app on an Android device or emulator.

---

## 1. Run from terminal (easiest)

From the project root (`doorshoppin`):

```bash
flutter run
```

All `print()` and `debugPrint()` output appears in this same terminal. Payment logs look like:

- `💳 [PaymentScreen] Starting mobile money payment...`
- `💳 [PaymentService] Initiating mobile money via backend`
- `📥 [PaymentScreen] Backend initiate result: ...`
- `🧪 PayChangu mode: sandbox` or `live`

---

## 2. Android Studio / VS Code

- **Run** the app (green play or F5).
- Open the **Run** or **Debug Console** tab at the bottom.
- Flutter logs appear there. Same lines as above.

---

## 3. ADB logcat (device already running)

If the app was started from Android Studio or installed separately, use logcat:

**All Flutter logs:**

```bash
adb logcat -s flutter
```

**Only payment-related lines (Windows PowerShell):**

```powershell
adb logcat | Select-String "PaymentScreen|PaymentService|PayChangu|charge_id|initiate|verify"
```

**Only payment-related lines (Windows CMD):**

```cmd
adb logcat | findstr "PaymentScreen PaymentService PayChangu charge_id initiate verify"
```

**Only payment-related lines (macOS/Linux):**

```bash
adb logcat | grep -E "PaymentScreen|PaymentService|PayChangu|charge_id|initiate|verify"
```

---

## 4. Clear logcat then reproduce

To avoid old messages:

```bash
adb logcat -c
```

Then trigger a payment in the app and run one of the `adb logcat` commands above.

---

## Quick reference

| Where you run the app | Where logs appear |
|------------------------|--------------------|
| `flutter run`          | Same terminal      |
| Android Studio Run     | Run/Debug Console  |
| VS Code Run/Debug       | Debug Console      |
| App already on device  | `adb logcat -s flutter` or filtered command above |

Payment logs use tags like `[PaymentScreen]` and `[PaymentService]` so you can filter for them in logcat.
