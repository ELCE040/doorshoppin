# API Setup Guide for Flutter App

## Step 1: Update API Base URL

Open `lib/config/api_config.dart` and update the `baseUrl`:

```dart
static const String baseUrl = 'https://yourdomain.com/api';
```

### For Different Environments:

- **Production**: `https://yourdomain.com/api`
- **Android Emulator**: `http://10.0.2.2:3001/api`
- **iOS Simulator**: `http://localhost:3001/api`
- **Physical Device**: `http://YOUR_COMPUTER_IP:3001/api`

## Step 2: Install Dependencies

Run:
```bash
flutter pub get
```

## Step 3: Test the Connection

1. Make sure your backend server is running
2. Test the health endpoint: `https://yourdomain.com/api/health`
3. Run the Flutter app
4. Products should load from the database

## Features Implemented

✅ **HomeScreen**: Fetches products from API
✅ **ProductDetailsScreen**: Fetches product details and related products
✅ **Category Filtering**: Filter products by category
✅ **Loading States**: Shows loading indicator while fetching
✅ **Error Handling**: Shows error message with retry button
✅ **Image Support**: Displays product images if available

## API Endpoints Used

- `GET /api/products` - Get all products
- `GET /api/products?category=Groceries` - Filter by category
- `GET /api/products/:id` - Get product by ID
- `GET /api/products/:id/related` - Get related products

## Troubleshooting

### Products not loading?
1. Check API base URL in `api_config.dart`
2. Verify backend server is running
3. Check network permissions in `AndroidManifest.xml`:
   ```xml
   <uses-permission android:name="android.permission.INTERNET"/>
   ```

### Getting connection errors?
- For Android emulator, use `http://10.0.2.2:3001/api`
- For physical device, use your computer's IP address
- Make sure backend CORS allows your app origin

### Images not showing?
- Products need `imageUrl` or `image_path` field in database
- Images should be accessible via HTTP/HTTPS
- Check image URLs are valid
