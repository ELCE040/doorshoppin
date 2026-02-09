# Logo Image

Place your doorshoppin logo image here as `logo.png`.

## Requirements:
- **File name**: `logo.png`
- **Recommended size**: 1024x1024 pixels (square) - for best quality on all devices
- **Format**: PNG with transparent background (preferred)
- **File size**: Keep under 1MB for best performance

## How to add:
1. Create or obtain your doorshoppin logo
2. Save it as `logo.png` (1024x1024 pixels recommended)
3. Place it in this `assets/images/` folder
4. Run the following commands to generate app icons:
   ```bash
   flutter pub get
   flutter pub run flutter_launcher_icons
   ```
5. Rebuild the app:
   ```bash
   flutter clean
   flutter run
   ```

## What this logo is used for:
- ✅ **App Launcher Icon** - The icon that appears on device home screen after installation
- ✅ **Splash Screen** - The logo shown when app starts
- ✅ **All Platforms** - Android, iOS, Web, Windows, macOS

If no logo is provided, the app will use the default Flutter icon for launcher and a shopping cart icon for splash screen.
