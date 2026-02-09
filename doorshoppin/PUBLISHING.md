# Publishing DoorShoppin to Google Play Store and Uptodown

This guide covers how to build release artifacts and submit DoorShoppin to **Google Play Console** and **Uptodown**.

---

## 0. Application ID and Firebase (optional for production)

The app currently uses **`com.example.doorshoppin`**, which matches your existing `google-services.json`, so debug and release builds work as-is.

**If you want a production-style ID** (e.g. `com.doorshoppin.app`) before publishing:

1. Open [Firebase Console](https://console.firebase.google.com/) → your project **doorshoppin-7f073** → **Project settings** → **Your apps**.
2. **Add app** → **Android** → package name **`com.doorshoppin.app`** → register.
3. Download the new **google-services.json** and replace `android/app/google-services.json` (or merge the new `client` into the existing file).
4. In `android/app/build.gradle.kts` set `namespace` and `applicationId` to `com.doorshoppin.app`.
5. Move `MainActivity.kt` to package `com.doorshoppin.app` (folder `kotlin/com/doorshoppin/app/`).

You can also publish with **`com.example.doorshoppin`**; Play Store accepts it.

---

## 1. Release signing (required for Play Store and recommended for Uptodown)

### Create an upload keystore (one-time)

From the project root (`doorshoppin`), run:

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

- Store the keystore file somewhere safe (e.g. `doorshoppin/upload-keystore.jks` or a secure folder). **Never commit it to Git.**
- Remember the passwords and alias; you need them for every future update.
- **Google Sign-In:** After creating the keystore, get its SHA-1:  
  `keytool -list -v -keystore upload-keystore.jks -alias upload`  
  Add that SHA-1 in Firebase Console → Project settings → Your apps → your Android app (e.g. **com.example.doorshoppin** or **com.doorshoppin.app**) → Add fingerprint.

### Configure Gradle to use the keystore

1. Copy the example file:
   - **Windows:** `copy android\key.properties.example android\key.properties`
   - **macOS/Linux:** `cp android/key.properties.example android/key.properties`

2. Edit `android/key.properties` and set:
   - `storePassword` = password for the keystore
   - `keyPassword` = password for the key
   - `keyAlias` = `upload` (or the alias you used)
   - `storeFile` = path to the `.jks` file **relative to the `android` folder**, e.g. `../upload-keystore.jks` if the keystore is in the project root

3. Ensure `key.properties` and `*.jks` / `*.keystore` are not committed (they are in `android/.gitignore`).

---

## 2. Build release artifacts

From the project root:

```bash
flutter clean
flutter pub get
```

### For Google Play (recommended: App Bundle)

```bash
flutter build appbundle --release
```

- Output: `build/app/outputs/bundle/release/app-release.aab`
- Upload this **.aab** in Play Console (Production or testing tracks).

### For Uptodown or direct APK distribution

```bash
flutter build apk --release
```

- Output: `build/app/outputs/flutter-apk/app-release.apk`
- For smaller per-ABI APKs: `flutter build apk --release --split-per-abi`
  - `app-armeabi-v7a-release.apk`
  - `app-arm64-v8a-release.apk`

---

## 3. Google Play Console checklist

1. **Developer account**
   - Create/use a Google Play Developer account (one-time fee).
   - [Play Console](https://play.google.com/console)

2. **Create the app**
   - Click “Create app”, choose “DoorShoppin”, set default language and type (App).

3. **Store listing**
   - **App name:** DoorShoppin  
   - **Short description:** up to 80 characters  
   - **Full description:** up to 4000 characters (features, delivery, payment, etc.)  
   - **Graphics:**
     - App icon: 512×512 PNG (e.g. from `assets/images/logo.png`)  
     - Feature graphic: 1024×500 PNG or JPG  
     - Screenshots: at least 2 (phone); 7" and 10" if you support tablets  

4. **Content rating**
   - Complete the questionnaire in Play Console (e.g. “Everyone” or “Teen” depending on content).

5. **Privacy policy**
   - Play Store requires a **public URL** to your privacy policy (how you use data, location, payments, etc.).  
   - Add the URL in: App content → Privacy policy.

6. **App content**
   - Declare if you use ads, in-app purchases, or collect sensitive data.  
   - If you use location: ensure the store listing and in-app disclosures match your privacy policy.

7. **Upload the AAB**
   - Release → Production (or Testing) → Create new release → Upload `app-release.aab`.  
   - Set release name (e.g. “1.0.0 (1)”) and release notes.

8. **Pricing and distribution**
   - Choose countries and whether the app is free/paid.

9. **Signing**
   - Use **Play App Signing** (recommended). Play will use your upload key to enroll the app; from then on you only need to upload AABs signed with the same upload keystore.

---

## 4. Uptodown checklist

1. **Developer account**
   - Register at [Uptodown](https://www.uptodown.com/) and use the developer section to add your app.

2. **App information**
   - Name: DoorShoppin  
   - Category (e.g. Shopping)  
   - Short and long description (you can reuse/adapt from Play Store)  
   - Optional: link to your website or Play Store listing  

3. **Upload**
   - Upload the **APK** (`app-release.apk` or the split APKs).  
   - Uptodown typically accepts APK; check their current rules for AAB.

4. **Screenshots and icon**
   - Provide app icon and screenshots as per Uptodown’s size requirements.

5. **Updates**
   - For each new version, bump `version` in `pubspec.yaml` (e.g. `1.0.0+1` → `1.0.1+2`), build a new release APK, and upload it in the Uptodown developer panel.

---

## 5. Version and build number

- **Version:** Edit `pubspec.yaml` → `version: 1.0.0+1`  
  - `1.0.0` = version name (user-facing)  
  - `1` = version code / build number (integer, must increase each upload to Play or Uptodown)  
- For each release, increase at least the build number, e.g. `1.0.0+2`, then `1.0.1+3`.

---

## 6. Quick reference

| Item              | Location / Command |
|------------------|---------------------|
| App ID            | `com.example.doorshoppin` (android/app/build.gradle.kts) |
| Version           | `pubspec.yaml` → `version` |
| Release AAB       | `flutter build appbundle --release` → `build/app/outputs/bundle/release/app-release.aab` |
| Release APK       | `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk` |
| Signing config    | `android/key.properties` (from `key.properties.example`) |
| ProGuard rules    | `android/app/proguard-rules.pro` |

---

## 7. Before first publish

- [ ] Keystore created and `android/key.properties` configured  
- [ ] Privacy policy URL ready and added (Play Console)  
- [ ] Store listing text and graphics ready (Play + Uptodown)  
- [ ] Content rating and app content declarations done (Play)  
- [ ] Test the release build: `flutter run --release` or install `app-release.apk` on a device  

After that, upload the **.aab** to Play Console and the **.apk** to Uptodown as described above.
