import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/stored_notification.dart';
import '../screens/order_detail_screen.dart';
import 'api_service.dart';
import 'auth_service.dart';

const String _storageKey = 'admin_notifications';

class NotificationService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  static GlobalKey<NavigatorState>? navigatorKey;
  static void Function(String title, String body)? onShowInAppBanner;

  static Future<void> initialize(
    GlobalKey<NavigatorState>? key, {
    void Function(String title, String body)? onShowInAppBannerCallback,
  }) async {
    debugPrint('[NotificationService] initialize');
    navigatorKey = key;
    onShowInAppBanner = onShowInAppBannerCallback;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);
    await _local.initialize(initSettings, onDidReceiveNotificationResponse: _onNotificationTap);
    requestPermission();
    _onForegroundMessage();
    _onBackgroundMessage();
    debugPrint('[NotificationService] initialize done');
  }

  static void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty && navigatorKey?.currentContext != null) {
      try {
        final orderId = int.tryParse(payload);
        if (orderId != null) {
          navigatorKey!.currentState?.pushNamed(OrderDetailScreen.routeName, arguments: orderId);
        }
      } catch (_) {}
    }
  }

  static Future<void> requestPermission() async {
    final settings = await _fcm.requestPermission(alert: true, badge: true, sound: true);
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      await _registerTokenWithBackend();
    }
  }

  static Future<void> _registerTokenWithBackend() async {
    try {
      debugPrint('[NotificationService] _registerTokenWithBackend');
      final token = await _fcm.getToken();
      if (token == null) {
        debugPrint('[NotificationService] no FCM token');
        return;
      }
      final adminId = await AuthService.getAdminId();
      if (adminId == null) {
        debugPrint('[NotificationService] no adminId, skip FCM register');
        return;
      }
      await ApiService.registerFcmToken(token, adminId);
      debugPrint('[NotificationService] FCM registered for adminId=$adminId');
    } catch (e) {
      debugPrint('[NotificationService] _registerTokenWithBackend error: $e');
    }
  }

  static void _onForegroundMessage() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final title = message.notification?.title ?? 'New order';
      final body = message.notification?.body ?? '';
      final orderIdRaw = message.data['orderId'] ?? message.data['order_id'];
      final orderId = orderIdRaw != null ? int.tryParse(orderIdRaw.toString()) : null;
      onShowInAppBanner?.call(title, body);
      _showLocalNotification(title: title, body: body, payload: orderId?.toString());
      _storeNotification(title, body, orderId);
    });
  }

  static void _onBackgroundMessage() {
    FirebaseMessaging.onBackgroundMessage(_backgroundHandler);
  }

  @pragma('vm:entry-point')
  static Future<void> _backgroundHandler(RemoteMessage message) async {
    final title = message.notification?.title ?? 'New order';
    final body = message.notification?.body ?? '';
    final orderIdRaw = message.data['orderId'] ?? message.data['order_id'];
    final orderId = orderIdRaw != null ? int.tryParse(orderIdRaw.toString()) : null;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(initSettings);
    await _showLocalNotificationStatic(title: title, body: body, payload: orderId?.toString(), plugin: plugin);
    await storeNotificationFromBackground(title, body, orderId);
  }

  /// Called from background isolate to persist notification so it appears in the list when app is opened.
  @pragma('vm:entry-point')
  static Future<void> storeNotificationFromBackground(String title, String body, int? orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      final list = raw != null
          ? (jsonDecode(raw) as List<dynamic>?)
              ?.map((e) => StoredNotification.fromJson(e as Map<String, dynamic>))
              .toList() ?? <StoredNotification>[]
          : <StoredNotification>[];
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      list.insert(0, StoredNotification(
        id: id,
        title: title,
        body: body,
        orderId: orderId,
        date: DateTime.now().toIso8601String(),
        read: false,
      ));
      while (list.length > 200) list.removeLast();
      await prefs.setString(_storageKey, jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  static Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const android = AndroidNotificationDetails(
      'admin_orders',
      'Order notifications',
      channelDescription: 'New orders and updates',
      importance: Importance.high,
      priority: Priority.high,
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
    );
    const details = NotificationDetails(android: android);
    await _local.show(DateTime.now().millisecondsSinceEpoch ~/ 1000, title, body, details, payload: payload);
  }

  static Future<void> _showLocalNotificationStatic({
    required String title,
    required String body,
    String? payload,
    required FlutterLocalNotificationsPlugin plugin,
  }) async {
    const android = AndroidNotificationDetails(
      'admin_orders',
      'Order notifications',
      channelDescription: 'New orders and updates',
      importance: Importance.high,
      priority: Priority.high,
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
    );
    const details = NotificationDetails(android: android);
    await plugin.show(DateTime.now().millisecondsSinceEpoch ~/ 1000, title, body, details, payload: payload);
  }

  /// Call after admin login to register FCM token
  static Future<void> registerAfterLogin() async {
    debugPrint('[NotificationService] registerAfterLogin');
    await _registerTokenWithBackend();
    debugPrint('[NotificationService] registerAfterLogin done');
  }

  static Future<void> _storeNotification(String title, String body, int? orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      final list = raw != null
          ? (jsonDecode(raw) as List<dynamic>?)
              ?.map((e) => StoredNotification.fromJson(e as Map<String, dynamic>))
              .toList() ?? <StoredNotification>[]
          : <StoredNotification>[];
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      list.insert(0, StoredNotification(
        id: id,
        title: title,
        body: body,
        orderId: orderId,
        date: DateTime.now().toIso8601String(),
        read: false,
      ));
      while (list.length > 200) list.removeLast();
      await prefs.setString(_storageKey, jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('[NotificationService] _storeNotification error: $e');
    }
  }

  /// List of stored notifications (newest first). Used by notifications page.
  static Future<List<StoredNotification>> getStoredNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List<dynamic>?;
      if (list == null) return [];
      return list.map((e) => StoredNotification.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> clearAllStoredNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {}
  }
}
