import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AuthService {
  static const _keyToken = 'admin_token';
  static const _keyAdminId = 'admin_id';
  static const _keyUsername = 'admin_username';
  static const _keyIsManager = 'admin_is_manager';

  static Future<void> saveLogin(String token, int adminId, String username, {bool isManager = false}) async {
    debugPrint('[AuthService] saveLogin adminId=$adminId username=$username isManager=$isManager');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
    await prefs.setInt(_keyAdminId, adminId);
    await prefs.setString(_keyUsername, username);
    await prefs.setBool(_keyIsManager, isManager);
    ApiService.setToken(token);
    debugPrint('[AuthService] saveLogin done');
  }

  static Future<bool> isManager() async {
    final prefs = await SharedPreferences.getInstance();
    final isManager = prefs.getBool(_keyIsManager) ?? false;
    debugPrint('[AuthService] isManager: $isManager');
    return isManager;
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyToken);
    final hasToken = token != null && token.isNotEmpty;
    debugPrint('[AuthService] isLoggedIn: hasToken=$hasToken');
    if (!hasToken) return false;
    ApiService.setToken(token);
    return true;
  }

  static Future<int?> getAdminId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyAdminId);
  }

  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUsername);
  }

  static Future<void> logout() async {
    debugPrint('[AuthService] logout');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyAdminId);
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyIsManager);
    ApiService.setToken(null);
    debugPrint('[AuthService] logout done');
  }
}
