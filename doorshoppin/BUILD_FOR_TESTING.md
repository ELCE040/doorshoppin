# Build DoorShoppin APK for Testing (Family & Friends)

Use these steps to build an APK you can send to testers. Run commands in a terminal from the project folder: `doorshoppin`.

---

## Option A: Release APK (recommended for sharing)

1. **Open terminal** in the project folder:
   ```bash
   cd c:\Users\lusin\AndroidStudioProjects\doorshoppin
   ```

2. **Clean and get dependencies:**
   ```bash
   flutter clean
   flutter pub get
   ```

3. **Build the release APK:**
   ```bash
   flutter build apk --release
   ```

4. **Find your APK:**
   - Path: `build\app\outputs\flutter-apk\app-release.apk`
   - Full path: `c:\Users\lusin\AndroidStudioProjects\doorshoppin\build\app\outputs\flutter-apk\app-release.apk`

5. **Share the file:**
   - Send `app-release.apk` via WhatsApp, email, Google Drive, or any file sharing.
   - Testers install it on their Android phone (Settings → Security → allow “Install from unknown sources” if prompted).

---

## Option B: If release build fails (AAPT / resource errors)

Try a **debug APK** for testing (larger file but works the same for testers):

```bash
flutter clean
flutter pub get
flutter build apk --debug
```

- APK location: `build\app\outputs\flutter-apk\app-debug.apk`
- Share `app-debug.apk` the same way.

---

## Option C: Smaller APKs per device type (split APKs)

To generate one APK per CPU type (smaller downloads):

```bash
flutter build apk --release --split-per-abi
```

You get:
- `app-armeabi-v7a-release.apk` (older 32-bit phones)
- `app-arm64-v8a-release.apk` (most current phones)

Send the one that matches the tester’s device (or send both and they pick one).

---

## Build from Android Studio (often more stable)

If the command-line build fails or the Gradle daemon crashes:

1. Open the **doorshoppin** project in **Android Studio**.
2. Wait for Gradle sync to finish.
3. Menu: **Build → Flutter → Build APK**.
4. When it finishes, click **locate** in the notification, or open:
   - `build\app\outputs\flutter-apk\app-release.apk`

You can send that APK to testers the same way.

---

## Troubleshooting

- **“Gradle daemon disappeared” / JVM crash**  
  1. Stop Gradle daemons: in project folder run  
     `.\android\gradlew.bat -p android --stop`  
  2. Close Android Studio and any other IDEs.  
  3. Run the build again, or use **Build → Flutter → Build APK** from Android Studio.

- **“Gradle build failed”**  
  Run: `.\android\gradlew.bat -p android clean` then try the build again.

- **“AAPT / file not found” (release only)**  
  Use Option B (debug APK) for testing, or build from Android Studio (Build → Flutter → Build APK).

- **“Install blocked” on tester’s phone**  
  They need to allow installation from your source (e.g. Chrome, Files, WhatsApp) in Settings → Security (or App permissions).

---

**Summary:** After a successful build, the file you send is **`app-release.apk`** (or **`app-debug.apk`**) from **`build\app\outputs\flutter-apk\`**.
