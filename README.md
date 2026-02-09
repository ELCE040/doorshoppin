# DoorShoppin Management

Admin Flutter app for DoorShoppin: view orders, get push notifications when customers place or pay for orders, and open directions from your location to the delivery address.

## Features

- **Admin login** – Sign in with admin username/password (same as PHP admin panel).
- **Orders list** – All orders with status, customer, total, address.
- **Order detail** – Full order info, items, delivery address, and a map of the delivery location.
- **Directions** – "Get directions" opens Google Maps with route from your current location to the customer's delivery point.
- **Push notifications** – When a customer places an order or pays, the admin app receives a notification (FCM topic `admin_orders`).

## Setup

1. **Backend** – Ensure the Node backend is running and exposes:
   - `POST /api/admin/login` (username, password)
   - `GET /api/admin/orders` (list all orders)
   - `GET /api/orders/:id` (order detail)
   - `POST /api/fcm/register` (with `is_admin: true`, `admin_id`, `fcm_token`)

2. **API URL** – In `lib/config/api_config.dart`, set `baseUrl` to your backend (e.g. `https://doorshoppin.com/doorshoppin_backend/api`).

3. **Firebase (for push)** – In [Firebase Console](https://console.firebase.google.com), add an Android app with package name `com.doorshoppin.doorshoppin_management`, then download `google-services.json` and replace `android/app/google-services.json`. Use the same Firebase project as the customer app so the `admin_orders` topic works.

4. **Google Maps** – For the map and directions you need a Maps API key. Add it in `android/app/src/main/AndroidManifest.xml` inside the `<application>` tag:
   ```xml
   <meta-data
       android:name="com.google.android.geo.API_KEY"
       android:value="YOUR_GOOGLE_MAPS_API_KEY"/>
   ```

## Run

```bash
flutter pub get
flutter run
```

Login with the same admin credentials you use in the PHP admin panel (e.g. username `admin`, password from your DB).
