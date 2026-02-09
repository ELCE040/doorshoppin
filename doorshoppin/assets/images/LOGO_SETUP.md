# App Launcher Icon Setup

This guide explains how to set up your custom app icon (the icon that appears on the device home screen after installation).

## Quick Setup:

1. **Add your logo image**:
   - Place your logo as `assets/images/logo.png`
   - Recommended size: **1024x1024 pixels** (square)
   - Format: PNG with transparent background (preferred)
   - File size: Keep under 1MB

2. **Generate app icons**:
   ```bash
   flutter pub get
   flutter pub run flutter_launcher_icons
   ```

3. **Rebuild the app**:
   ```bash
   flutter clean
   flutter run
   ```

## What This Does:

The `flutter_launcher_icons` package will automatically:
- Generate all required icon sizes for Android (mdpi, hdpi, xhdpi, xxhdpi, xxxhdpi)
- Generate all required icon sizes for iOS
- Generate web favicon
- Generate Windows icon
- Generate macOS icon

## Current Configuration:

- **Android**: ✅ Enabled
- **iOS**: ✅ Enabled  
- **Web**: ✅ Enabled (with theme color #1ABC9C)
- **Windows**: ✅ Enabled
- **macOS**: ✅ Enabled

## Notes:

- If you don't have a logo image yet, the app will use the default Flutter icon
- Once you add `logo.png` and run the generation command, all platforms will use your custom icon
- The icon will appear on the device home screen/app drawer after installation
