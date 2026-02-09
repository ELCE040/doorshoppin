# Publishing DoorShoppin Management to Play Store and Uptodown

This guide covers building release artifacts and submitting **DoorShoppin Management** (admin app) to **Google Play Console** and **Uptodown**.

---

## 0. Before you build

- **Firebase:** This app already uses package `com.doorshoppin.doorshoppin_management` in your existing `google-services.json`; no change needed.
- **Google Maps API key:** In `android/app/src/main/AndroidManifest.xml`, replace `YOUR_GOOGLE_MAPS_API_KEY` with your real Maps API key from Google Cloud Console (same project as DoorShoppin, or a separate key restricted to this package).

---

## 1. Release signing (required for Play Store, recommended for Uptodown)

### Create an upload keystore (one-time)

From the project root (`DoorShoppin_Management`):

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

- Store the `.jks` file safely. **Never commit it to Git.**
- Remember the passwords and alias.

### Configure Gradle

1. Copy the example:  
   **Windows:** `copy android\key.properties.example android\key.properties`  
   **macOS/Linux:** `cp android/key.properties.example android/key.properties`

2. Edit `android/key.properties`:
   - `storePassword`, `keyPassword` = your keystore/key passwords  
   - `keyAlias` = `upload`  
   - `storeFile` = path to the `.jks` file **relative to the `android` folder**, e.g. `../upload-keystore.jks`

3. Do not commit `key.properties` or any `.jks` / `.keystore` (they are in `android/.gitignore`).

---

## 2. Build release artifacts

From the project root:

```bash
flutter clean
flutter pub get
```

### For Google Play (App Bundle)

```bash
flutter build appbundle --release
```

- Output: `build/app/outputs/bundle/release/app-release.aab`  
- Upload this **.aab** in Play Console.

### For Uptodown or direct APK

```bash
flutter build apk --release
```

- Output: `build/app/outputs/flutter-apk/app-release.apk`  
- For per-ABI APKs: `flutter build apk --release --split-per-abi`  
  - `app-armeabi-v7a-release.apk`, `app-arm64-v8a-release.apk`

---

## 3. Google Play Console checklist

1. **Developer account** at [Play Console](https://play.google.com/console).

2. **Create the app**  
   - Name: e.g. "DoorShoppin Management"  
   - Default language, type: App.

3. **Store listing**  
   - **App name:** DoorShoppin Management  
   - **Short description:** e.g. "Admin app for DoorShoppin – orders, products, dashboard."  
   - **Full description:** Describe admin features (orders, products, notifications, dashboard).  
   - **Graphics:** 512×512 icon, 1024×500 feature graphic, at least 2 phone screenshots.  
   - **Category:** e.g. Business or Productivity.

4. **Content rating**  
   - Complete the questionnaire (e.g. Everyone or relevant age group).

5. **Privacy policy**  
   - Add a **public URL** in App content → Privacy policy (required if you collect data).

6. **App content**  
   - Declare data collection, location use, etc., as applicable.

7. **Upload AAB**  
   - Release → Production (or Testing) → Create new release → Upload `app-release.aab` → Set release name and notes.

8. **Pricing and distribution**  
   - Choose countries; set free or paid.  
   - **Important:** This is an admin/management app – you may want to restrict to internal testers or a closed track; use Play Console’s testing tracks if you don’t want a public listing.

9. **Play App Signing**  
   - Use Play App Signing; upload AABs signed with your upload keystore.

---

## 4. Uptodown checklist

1. **Developer account** at [Uptodown](https://www.uptodown.com/).

2. **Add app**  
   - Name: DoorShoppin Management  
   - Category: e.g. Business  
   - Short and long description (can adapt from Play listing).

3. **Upload**  
   - Upload **APK** (`app-release.apk` or split APKs per their current rules).

4. **Screenshots and icon**  
   - Provide icon and screenshots per Uptodown’s requirements.

5. **Updates**  
   - For each version: bump `version` in `pubspec.yaml` (e.g. `1.0.0+1` → `1.0.1+2`), build new APK, upload in developer panel.

---

## 5. Version and build number

Edit `pubspec.yaml` → `version: 1.0.0+1`  
- First number = version name (user-facing).  
- After `+` = version code (integer; must increase for each Play/Uptodown upload).

Example: `1.0.1+2`, then `1.0.2+3`.

---

## 6. Quick reference

| Item        | Value / Command |
|------------|------------------|
| App ID     | `com.doorshoppin.doorshoppin_management` |
| Version    | `pubspec.yaml` → `version` |
| Release AAB| `flutter build appbundle --release` → `build/app/outputs/bundle/release/app-release.aab` |
| Release APK| `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk` |
| Signing    | `android/key.properties` (from `key.properties.example`) |
| ProGuard   | `android/app/proguard-rules.pro` |

---

## 7. Before first publish

- [ ] Google Maps API key set in `AndroidManifest.xml` (replace `YOUR_GOOGLE_MAPS_API_KEY`)  
- [ ] Keystore created and `android/key.properties` configured  
- [ ] Privacy policy URL ready (Play Console)  
- [ ] Store listing text and graphics ready  
- [ ] Content rating and app content declarations done (Play)  
- [ ] Test release build: `flutter run --release` or install `app-release.apk` on a device  

Then upload the **.aab** to Play Console and the **.apk** to Uptodown as described above.
