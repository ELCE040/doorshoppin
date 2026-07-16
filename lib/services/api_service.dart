import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; // for debugPrint
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import '../config/api_config.dart';
import '../models/dashboard_model.dart';
import '../models/order_model.dart';

class SessionExpiredException implements Exception {
  final String message;
  const SessionExpiredException([
    this.message = 'Session expired. Please sign in again.',
  ]);

  @override
  String toString() => message;
}

class ApiService {
  static String? _token;
  static VoidCallback? _sessionExpiredHandler;
  static bool _didNotifySessionExpiry = false;

  static void setSessionExpiredHandler(VoidCallback? handler) {
    _sessionExpiredHandler = handler;
    _didNotifySessionExpiry = false;
  }

  static void setToken(String? token) {
    _token = token;
    if (token != null && token.isNotEmpty) {
      _didNotifySessionExpiry = false;
    }
  }

  static void _notifySessionExpiredOnce() {
    if (_didNotifySessionExpiry) return;
    _didNotifySessionExpiry = true;
    _sessionExpiredHandler?.call();
  }

  static String _extractErrorMessage(Map<String, dynamic> json) {
    final v = json['error'] ?? json['message'] ?? json['detail'] ?? json['msg'];
    return v?.toString() ?? '';
  }

  static bool _looksLikeSessionExpired(int statusCode, String messageLower) {
    if (messageLower.contains('session expired')) return true;
    if (messageLower.contains('jwt') && messageLower.contains('expired'))
      return true;
    if (messageLower.contains('token') && messageLower.contains('expired'))
      return true;
    if (statusCode == 401 && messageLower.contains('invalid token'))
      return true;
    if (statusCode == 401 && messageLower.contains('unauthorized')) return true;
    if (statusCode == 401 && messageLower.contains('not authenticated'))
      return true;
    if (statusCode == 401 && messageLower.contains('authentication required'))
      return true;
    if (statusCode == 401 && messageLower.trim().isEmpty) return true;
    return false;
  }

  static void _maybeThrowSessionExpired(
    int statusCode,
    Map<String, dynamic> data,
    String context,
  ) {
    if (context == 'adminLogin') return;
    final messageLower = _extractErrorMessage(data).toLowerCase();
    if (_looksLikeSessionExpired(statusCode, messageLower)) {
      debugPrint(
        '[ApiService] session expired in $context (status=$statusCode, msg=$messageLower)',
      );
      _notifySessionExpiredOnce();
      throw const SessionExpiredException();
    }
  }

  /// Parse response body as JSON. Throws a clear message if server returned HTML (e.g. 503 proxy error).
  static Map<String, dynamic> _parseJson(
    String body,
    int statusCode, [
    String context = 'request',
  ]) {
    final raw = body;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      if (statusCode == 401 && context != 'adminLogin') {
        _notifySessionExpiredOnce();
        throw const SessionExpiredException();
      }
      if (statusCode >= 500)
        throw Exception(
          'Server unavailable ($statusCode). Please try again later.',
        );
      return {};
    }
    if (trimmed.startsWith('<')) {
      if (statusCode == 401 && context != 'adminLogin') {
        _notifySessionExpiredOnce();
        throw const SessionExpiredException();
      }
      if (statusCode == 503) {
        throw Exception(
          'Server temporarily unavailable. Please try again in a few moments.',
        );
      }
      throw Exception(
        'Server returned an error ($statusCode). Please try again later.',
      );
    }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>? ?? {};
      _maybeThrowSessionExpired(statusCode, data, context);
      return data;
    } on SessionExpiredException {
      rethrow;
    } catch (_) {
      if (statusCode >= 500)
        throw Exception(
          'Server unavailable ($statusCode). Please try again later.',
        );
      throw Exception('Invalid server response. Please try again.');
    }
  }

  static Map<String, String> get _headers {
    final h = {'Content-Type': 'application/json'};
    if (_token != null && _token!.isNotEmpty) {
      h['Authorization'] = 'Bearer $_token';
    }
    return h;
  }

  /// Admin login
  static Future<Map<String, dynamic>> adminLogin(
    String username,
    String password,
  ) async {
    final url = '${ApiConfig.baseUrl}/admin/login';
    debugPrint('[Admin Login] POST $url | username length: ${username.length}');
    try {
      final res = await http.post(
        Uri.parse(url),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );
      final rawBody = res.body is String
          ? res.body as String
          : res.body.toString();
      debugPrint(
        '[Admin Login] status: ${res.statusCode} | body length: ${rawBody.length}',
      );
      if (rawBody.isNotEmpty && rawBody.length < 500) {
        debugPrint('[Admin Login] body: $rawBody');
      }
      final data = _parseJson(rawBody, res.statusCode, 'adminLogin');
      if (res.statusCode == 200 && data['success'] == true) {
        setToken(data['token']?.toString());
        debugPrint('[Admin Login] success, admin id: ${data['admin']?['id']}');
        return data;
      }
      final errMsg = data['error']?.toString() ?? 'Login failed';
      debugPrint('[Admin Login] failed: $errMsg');
      throw Exception(errMsg);
    } catch (e, st) {
      debugPrint('[Admin Login] request error: $e');
      debugPrint('[Admin Login] stack: $st');
      rethrow;
    }
  }

  /// Get current admin profile (id, username, email, isManager). Use when login response omits isManager.
  static Future<Map<String, dynamic>?> getAdminMe() async {
    final url = '${ApiConfig.baseUrl}/admin/me';
    debugPrint('[ApiService] getAdminMe GET $url');
    try {
      final res = await http.get(Uri.parse(url), headers: _headers);
      final data = _parseJson(res.body, res.statusCode, 'getAdminMe');
      if (res.statusCode == 200 && data['success'] == true) {
        final admin = data['admin'] as Map<String, dynamic>?;
        debugPrint(
          '[ApiService] getAdminMe success id=${admin?['id']} isManager=${admin?['isManager']}',
        );
        return admin;
      }
      debugPrint('[ApiService] getAdminMe failed status=${res.statusCode}');
    } catch (e) {
      debugPrint('[ApiService] getAdminMe error: $e');
    }
    return null;
  }

  /// Dashboard stats (admin)
  static Future<DashboardModel> getDashboardStats() async {
    final url = '${ApiConfig.baseUrl}/admin/dashboard';
    debugPrint('[ApiService] getDashboardStats GET $url');
    final res = await http.get(Uri.parse(url), headers: _headers);
    final data = _parseJson(res.body, res.statusCode, 'getDashboardStats');
    if (res.statusCode != 200 || data['success'] != true) {
      debugPrint('[ApiService] getDashboardStats failed: ${data['error']}');
      throw Exception(data['error']?.toString() ?? 'Failed to load dashboard');
    }
    debugPrint('[ApiService] getDashboardStats success');
    return DashboardModel.fromJson(data);
  }

  /// List all orders (admin)
  static Future<List<OrderModel>> getAdminOrders() async {
    final url = '${ApiConfig.baseUrl}/admin/orders';
    debugPrint('[ApiService] getAdminOrders GET $url');
    final res = await http.get(Uri.parse(url), headers: _headers);
    debugPrint(
      '[ApiService] getAdminOrders status=${res.statusCode} bodyLength=${res.body.length}',
    );
    final data = _parseJson(res.body, res.statusCode, 'getAdminOrders');
    if (res.statusCode != 200 || data['success'] != true) {
      debugPrint('[ApiService] getAdminOrders failed: ${data['error']}');
      throw Exception(data['error']?.toString() ?? 'Failed to load orders');
    }
    final list = data['data'] as List<dynamic>? ?? [];
    debugPrint('[ApiService] getAdminOrders success count=${list.length}');
    return list
        .map((e) => OrderModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Get single order by id (from orders API)
  static Future<OrderModel> getOrderById(int id) async {
    final url = '${ApiConfig.baseUrl}/orders/$id';
    debugPrint('[ApiService] getOrderById GET $url');
    final res = await http.get(Uri.parse(url), headers: _headers);
    debugPrint('[ApiService] getOrderById status=${res.statusCode}');
    final data = _parseJson(res.body, res.statusCode, 'getOrderById');
    if (res.statusCode != 200 || data['success'] != true) {
      debugPrint('[ApiService] getOrderById failed: ${data['error']}');
      throw Exception(data['error']?.toString() ?? 'Failed to load order');
    }
    final orderJson = data['data'] as Map<String, dynamic>? ?? {};
    return OrderModel.fromJson(orderJson);
  }

  /// Update order status (admin). Backend notifies the order owner via FCM.
  static Future<void> updateAdminOrderStatus(int orderId, String status) async {
    final url = '${ApiConfig.baseUrl}/admin/orders/$orderId/status';
    debugPrint('[ApiService] updateAdminOrderStatus PATCH $url status=$status');
    final res = await http.patch(
      Uri.parse(url),
      headers: _headers,
      body: jsonEncode({'status': status}),
    );
    final data = _parseJson(res.body, res.statusCode, 'updateAdminOrderStatus');
    if (res.statusCode != 200 || data['success'] != true) {
      debugPrint(
        '[ApiService] updateAdminOrderStatus failed: ${data['error']}',
      );
      throw Exception(
        data['error']?.toString() ?? 'Failed to update order status',
      );
    }
    debugPrint(
      '[ApiService] updateAdminOrderStatus success orderId=$orderId status=$status',
    );
  }

  /// Register FCM token for admin (subscribe to admin_orders topic)
  static Future<void> registerFcmToken(String fcmToken, int adminId) async {
    final url = '${ApiConfig.baseUrl}/fcm/register';
    debugPrint('[ApiService] registerFcmToken POST $url adminId=$adminId');
    final res = await http.post(
      Uri.parse(url),
      headers: _headers,
      body: jsonEncode({
        'fcm_token': fcmToken,
        'is_admin': true,
        'admin_id': adminId,
      }),
    );
    debugPrint('[ApiService] registerFcmToken status=${res.statusCode}');
    if (res.statusCode != 200) {
      final data = _parseJson(res.body, res.statusCode, 'registerFcmToken');
      debugPrint('[ApiService] registerFcmToken failed: ${data['error']}');
      throw Exception(data['error']?.toString() ?? 'FCM register failed');
    }
    debugPrint('[ApiService] registerFcmToken success');
  }

  // --- Admin products ---
  static Future<List<Map<String, dynamic>>> getAdminProducts({
    String? category,
    String? search,
    int? limit,
    int skip = 0,
  }) async {
    final effectiveLimit = limit ?? 999999;
    var url =
        '${ApiConfig.baseUrl}/admin/products?limit=$effectiveLimit&skip=$skip';
    if (category != null && category.isNotEmpty && category != 'all')
      url += '&category=${Uri.encodeComponent(category)}';
    if (search != null && search.isNotEmpty)
      url += '&search=${Uri.encodeComponent(search)}';
    debugPrint(
      '[ApiService] getAdminProducts GET category=$category search=${search != null}',
    );
    final res = await http.get(Uri.parse(url), headers: _headers);
    final data = _parseJson(res.body, res.statusCode, 'getAdminProducts');
    if (res.statusCode != 200 || data['success'] != true)
      throw Exception(data['error']?.toString() ?? 'Failed to load products');
    final list = data['data'] as List<dynamic>? ?? [];
    debugPrint('[ApiService] getAdminProducts success count=${list.length}');
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>> createProduct({
    required String name,
    String? description,
    String? category,
    required double price,
    String? imagePath,
  }) async {
    final url = '${ApiConfig.baseUrl}/admin/products';
    final res = await http.post(
      Uri.parse(url),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'description': description ?? '',
        'category': category ?? '',
        'price': price,
        'image_path': imagePath ?? '',
      }),
    );
    final data = _parseJson(res.body, res.statusCode, 'createProduct');
    if (res.statusCode != 201 && res.statusCode != 200)
      throw Exception(data['error']?.toString() ?? 'Failed to create product');
    return _dataAsProductMap(data['data'], fallbackId: null);
  }

  static Future<Map<String, dynamic>> updateProduct(
    int id, {
    String? name,
    String? description,
    String? category,
    double? price,
    String? imagePath,
  }) async {
    final url = '${ApiConfig.baseUrl}/admin/products/$id';
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (category != null) body['category'] = category;
    if (price != null) body['price'] = price;
    if (imagePath != null) body['image_path'] = imagePath;
    debugPrint(
      '[ApiService] updateProduct PUT id=$id bodyKeys=${body.keys.join(",")} imagePath=${imagePath != null}',
    );
    final res = await http.put(
      Uri.parse(url),
      headers: _headers,
      body: jsonEncode(body),
    );
    final data = _parseJson(res.body, res.statusCode, 'updateProduct');
    if (res.statusCode != 200)
      throw Exception(data['error']?.toString() ?? 'Failed to update product');
    debugPrint('[ApiService] updateProduct success id=$id');
    return _dataAsProductMap(data['data'], fallbackId: id);
  }

  /// Safely cast response data to Map; avoids "null is not subtype of Map" when server omits or nulls data.
  static Map<String, dynamic> _dataAsProductMap(
    dynamic raw, {
    int? fallbackId,
  }) {
    if (raw == null)
      return fallbackId != null
          ? <String, dynamic>{'id': fallbackId}
          : <String, dynamic>{};
    if (raw is! Map)
      return fallbackId != null
          ? <String, dynamic>{'id': fallbackId}
          : <String, dynamic>{};
    return Map<String, dynamic>.from(raw);
  }

  static Future<void> deleteProduct(int id) async {
    final url = '${ApiConfig.baseUrl}/admin/products/$id';
    debugPrint('[ApiService] deleteProduct DELETE id=$id');
    final res = await http.delete(Uri.parse(url), headers: _headers);
    if (res.statusCode != 200) {
      final data = _parseJson(res.body, res.statusCode, 'deleteProduct');
      throw Exception(data['error']?.toString() ?? 'Failed to delete product');
    }
    debugPrint('[ApiService] deleteProduct success id=$id');
  }

  // --- Vendors: stores and restaurants ---
  static Future<List<Map<String, dynamic>>> getVendors({
    String type = 'all',
    bool includeInactive = false,
  }) async {
    final url =
        '${ApiConfig.baseUrl}/admin/vendors?type=${Uri.encodeComponent(type)}&includeInactive=$includeInactive';
    final res = await http.get(Uri.parse(url), headers: _headers);
    final data = _parseJson(res.body, res.statusCode, 'getVendors');
    if (res.statusCode != 200 || data['success'] != true) {
      throw Exception(data['error']?.toString() ?? 'Failed to load stores');
    }
    final list = data['data'] as List<dynamic>? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>> createVendor({
    required String name,
    required String type,
    String? phone,
    String? address,
  }) async {
    final url = '${ApiConfig.baseUrl}/admin/vendors';
    final res = await http.post(
      Uri.parse(url),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'type': type,
        'phone': phone ?? '',
        'address': address ?? '',
      }),
    );
    final data = _parseJson(res.body, res.statusCode, 'createVendor');
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Exception(data['error']?.toString() ?? 'Failed to create store');
    }
    return Map<String, dynamic>.from(data['data'] as Map);
  }

  static Future<Map<String, dynamic>> updateVendor(
    int id, {
    String? name,
    String? type,
    String? phone,
    String? address,
    bool? active,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (type != null) body['type'] = type;
    if (phone != null) body['phone'] = phone;
    if (address != null) body['address'] = address;
    if (active != null) body['active'] = active;
    final url = '${ApiConfig.baseUrl}/admin/vendors/$id';
    final res = await http.put(
      Uri.parse(url),
      headers: _headers,
      body: jsonEncode(body),
    );
    final data = _parseJson(res.body, res.statusCode, 'updateVendor');
    if (res.statusCode != 200 || data['success'] != true) {
      throw Exception(data['error']?.toString() ?? 'Failed to update store');
    }
    return Map<String, dynamic>.from(data['data'] as Map);
  }

  static Future<void> deleteVendor(int id) async {
    final url = '${ApiConfig.baseUrl}/admin/vendors/$id';
    final res = await http.delete(Uri.parse(url), headers: _headers);
    if (res.statusCode != 200) {
      final data = _parseJson(res.body, res.statusCode, 'deleteVendor');
      throw Exception(data['error']?.toString() ?? 'Failed to remove store');
    }
  }

  static Future<List<Map<String, dynamic>>> getProductVendors(int productId) async {
    final url = '${ApiConfig.baseUrl}/admin/products/$productId/vendors';
    final res = await http.get(Uri.parse(url), headers: _headers);
    final data = _parseJson(res.body, res.statusCode, 'getProductVendors');
    if (res.statusCode != 200 || data['success'] != true) {
      throw Exception(data['error']?.toString() ?? 'Failed to load product stores');
    }
    final list = data['data'] as List<dynamic>? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<List<Map<String, dynamic>>> updateProductVendors(
    int productId,
    List<Map<String, dynamic>> vendors,
  ) async {
    final url = '${ApiConfig.baseUrl}/admin/products/$productId/vendors';
    final res = await http.put(
      Uri.parse(url),
      headers: _headers,
      body: jsonEncode({'vendors': vendors}),
    );
    final data = _parseJson(res.body, res.statusCode, 'updateProductVendors');
    if (res.statusCode != 200 || data['success'] != true) {
      throw Exception(data['error']?.toString() ?? 'Failed to update product stores');
    }
    final list = data['data'] as List<dynamic>? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Upload image file (from device). Returns path to use as product image_path.
  static Future<String> uploadProductImage(String filePath) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/admin/upload');
    debugPrint(
      '[ApiService] uploadProductImage POST file=${filePath.split(RegExp(r'[/\\]')).last}',
    );
    var request = http.MultipartRequest('POST', url);
    for (final e in _headers.entries) request.headers[e.key] = e.value;
    request.files.add(await http.MultipartFile.fromPath('image', filePath));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final data = _parseJson(res.body, res.statusCode, 'uploadProductImage');
    if (res.statusCode != 200 || data['success'] != true)
      throw Exception(data['error']?.toString() ?? 'Upload failed');
    final path = data['path']?.toString() ?? '';
    debugPrint('[ApiService] uploadProductImage success path=$path');
    return path;
  }

  /// Upload image bytes. Returns path to use as product image_path.
  static Future<String> uploadProductImageBytes(Uint8List bytes, String filename) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/admin/upload');
    debugPrint('[ApiService] uploadProductImageBytes POST file=$filename');
    // Derive MIME type from extension so the server's multer fileFilter accepts it.
    final ext = filename.split('.').last.toLowerCase();
    final mimeType = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png'           => 'image/png',
      'webp'          => 'image/webp',
      'gif'           => 'image/gif',
      'avif'          => 'image/avif',
      _               => 'image/jpeg',
    };
    var request = http.MultipartRequest('POST', url);
    for (final e in _headers.entries) request.headers[e.key] = e.value;
    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: filename,
        contentType: http_parser.MediaType.parse(mimeType),
      ),
    );
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final data = _parseJson(res.body, res.statusCode, 'uploadProductImage');
    if (res.statusCode != 200 || data['success'] != true)
      throw Exception(data['error']?.toString() ?? 'Upload failed');
    final path = data['path']?.toString() ?? '';
    debugPrint('[ApiService] uploadProductImageBytes success path=$path');
    return path;
  }

  // --- HR (manager only) ---
  static Future<List<Map<String, dynamic>>> getHrAdmins() async {
    final url = '${ApiConfig.baseUrl}/admin/hr/admins';
    final res = await http.get(Uri.parse(url), headers: _headers);
    final data = _parseJson(res.body, res.statusCode, 'getHrAdmins');
    if (res.statusCode != 200 || data['success'] != true)
      throw Exception(data['error']?.toString() ?? 'Failed to load admins');
    final list = data['data'] as List<dynamic>? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>> addHrAdmin({
    required String username,
    required String email,
    required String password,
  }) async {
    final url = '${ApiConfig.baseUrl}/admin/hr/admins';
    final res = await http.post(
      Uri.parse(url),
      headers: _headers,
      body: jsonEncode({
        'username': username,
        'email': email,
        'password': password,
      }),
    );
    final data = _parseJson(res.body, res.statusCode, 'addHrAdmin');
    if (res.statusCode != 201 && res.statusCode != 200)
      throw Exception(data['error']?.toString() ?? 'Failed to add admin');
    return _dataAsProductMap(data['data'], fallbackId: null);
  }

  static Future<void> deleteHrAdmin(int id) async {
    final url = '${ApiConfig.baseUrl}/admin/hr/admins/$id';
    final res = await http.delete(Uri.parse(url), headers: _headers);
    if (res.statusCode != 200) {
      final data = _parseJson(res.body, res.statusCode, 'deleteHrAdmin');
      throw Exception(data['error']?.toString() ?? 'Failed to delete admin');
    }
  }

  static Future<void> changeHrAdminPassword(
    int adminId,
    String newPassword,
  ) async {
    final url = '${ApiConfig.baseUrl}/admin/hr/admins/$adminId/password';
    final res = await http.put(
      Uri.parse(url),
      headers: _headers,
      body: jsonEncode({'newPassword': newPassword}),
    );
    if (res.statusCode != 200) {
      final data = _parseJson(
        res.body,
        res.statusCode,
        'changeHrAdminPassword',
      );
      throw Exception(data['error']?.toString() ?? 'Failed to change password');
    }
  }

  /// List all registered app users (DoorShoppin). Manager only.
  static Future<List<Map<String, dynamic>>> getAppUsers() async {
    final url = '${ApiConfig.baseUrl}/admin/hr/users';
    final res = await http.get(Uri.parse(url), headers: _headers);
    final data = _parseJson(res.body, res.statusCode, 'getAppUsers');
    if (res.statusCode != 200 || data['success'] != true) {
      throw Exception(data['error']?.toString() ?? 'Failed to load users');
    }
    final list = data['data'] as List<dynamic>? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Send notification to all app users (e.g. new products, promotions). Manager only.
  static Future<Map<String, dynamic>> sendNotificationToUsers({
    required String title,
    required String body,
  }) async {
    final url = '${ApiConfig.baseUrl}/admin/notifications/broadcast';
    final res = await http.post(
      Uri.parse(url),
      headers: _headers,
      body: jsonEncode({'title': title, 'body': body}),
    );
    final data = _parseJson(
      res.body,
      res.statusCode,
      'sendNotificationToUsers',
    );
    if (res.statusCode != 200 || data['success'] != true) {
      throw Exception(
        data['error']?.toString() ?? 'Failed to send notification',
      );
    }
    return Map<String, dynamic>.from(data);
  }
}
