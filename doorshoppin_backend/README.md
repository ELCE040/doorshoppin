# Doorshoppin Backend API

Backend API for the Doorshoppin grocery delivery Flutter app.

## Setup

1. **Install dependencies:**
   ```bash
   npm install
   ```

2. **Create `.env` file:**
   ```env
   DB_HOST=localhost
   DB_PORT=3306
   DB_USER=your_mysql_username
   DB_PASSWORD=your_mysql_password
   DB_NAME=doorbuvi_door_shopping
   JWT_SECRET=your_jwt_secret_key
   PORT=3001
   CORS_ORIGIN=*
   NODE_ENV=development
   ```

3. **Seed sample products (optional):**
   ```bash
   npm run seed
   ```
   Note: This will only insert products if the products table is empty.

4. **Start the server:**
   ```bash
   npm start
   # or for development with auto-reload:
   npm run dev
   ```

## API Endpoints

### Authentication
- `POST /api/auth/register` - Register with email or phone
- `POST /api/auth/login` - Login with email or phone
- `GET /api/auth/health` - Health check

### Products
- `GET /api/products` - Get all products (with filters)
- `GET /api/products/:id` - Get product by ID
- `GET /api/products/category/:category` - Get products by category
- `GET /api/products/search/:query` - Search products
- `GET /api/products/:id/related` - Get related products

### Orders
- `POST /api/orders` - Create order (supports guest orders)
- `GET /api/orders/my-orders` - Get user orders (authenticated)
- `GET /api/orders/:id` - Get order by ID
- `GET /api/orders/track/:orderId` - Track order by orderId
- `PATCH /api/orders/:id/status` - Update order status

## Database

Uses MySQL database `doorbuvi_door_shopping` with tables:
- `users` - User accounts (with firebase_uid, email, phone, password)
- `products` - Product catalog (id, name, description, category, price, image_path)
- `orders` - Customer orders (id, user_id, status, total_amount, order_tracking_id, address, latitude, longitude)
- `temp_orders` - Temporary cart/order data
- `transactions` - Payment transactions
- `promotions` - Promotional offers
- `delivery_settings` - Delivery fee settings

## Documentation

See `API_DOCUMENTATION.md` for detailed API documentation.
