import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'main_shell_screen.dart';

const Color appGreen = Color(0xFF28b244);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  static const routeName = '/login';

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  /// Show a short message for network/DNS errors instead of raw exception.
  static String _userFriendlyNetworkError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('failed host lookup') ||
        msg.contains('no address associated with hostname') ||
        msg.contains('socketexception')) {
      return 'Cannot reach server. Check your internet connection (Wi‑Fi or mobile data) and try again.';
    }
    if (msg.contains('connection refused') || msg.contains('connection reset')) {
      return 'Server unavailable. Please try again later.';
    }
    if (msg.contains('connection timed out') || msg.contains('timed out')) {
      return 'Connection timed out. Check your network and try again.';
    }
    if (msg.contains('network is unreachable')) {
      return 'No internet connection. Turn on Wi‑Fi or mobile data.';
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    debugPrint('[LoginScreen] _login called, username length: ${username.length}, password length: ${password.length}');
    if (username.isEmpty || password.isEmpty) {
      debugPrint('[LoginScreen] validation failed: empty username or password');
      setState(() => _error = 'Enter username and password');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      debugPrint('[LoginScreen] calling ApiService.adminLogin');
      final data = await ApiService.adminLogin(username, password);
      final admin = data['admin'] as Map<String, dynamic>? ?? {};
      final adminId = admin['id'] is int ? admin['id'] as int : int.tryParse(admin['id']?.toString() ?? '');
      final name = admin['username']?.toString() ?? username;
      // Accept boolean true, 1, or string "true" (backend may serialize differently)
      var isManagerRaw = admin['isManager'] ?? admin['is_manager'];
      var isManager = isManagerRaw == true ||
          isManagerRaw == 1 ||
          (isManagerRaw is String && isManagerRaw.toString().toLowerCase() == 'true');
      // If login response omitted isManager (e.g. old backend), fetch from GET /api/admin/me
      if (isManagerRaw == null && adminId != null && adminId > 0) {
        debugPrint('[LoginScreen] isManager missing in login response, fetching /admin/me');
        final me = await ApiService.getAdminMe();
        if (me != null) {
          final meRaw = me['isManager'] ?? me['is_manager'];
          isManager = meRaw == true ||
              meRaw == 1 ||
              (meRaw is String && meRaw.toString().toLowerCase() == 'true');
          debugPrint('[LoginScreen] from /me: isManager=$isManager (raw: $meRaw)');
        }
      }
      debugPrint('[LoginScreen] response adminId: $adminId, name: $name, isManager: $isManager (raw: $isManagerRaw)');
      if (adminId != null && adminId > 0) {
        await AuthService.saveLogin(data['token']?.toString() ?? '', adminId, name, isManager: isManager);
        await NotificationService.registerAfterLogin();
        if (!mounted) return;
        debugPrint('[LoginScreen] navigating to main shell');
        Navigator.of(context).pushReplacementNamed(MainShellScreen.routeName);
      } else {
        debugPrint('[LoginScreen] invalid response: adminId=$adminId');
        setState(() {
          _loading = false;
          _error = 'Invalid response';
        });
      }
    } catch (e, st) {
      debugPrint('[LoginScreen] exception: $e');
      debugPrint('[LoginScreen] stack: $st');
      setState(() {
        _loading = false;
        _error = _userFriendlyNetworkError(e);
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/logo.png',
                  width: 48,
                  height: 48,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(Icons.store, size: 48, color: appGreen),
                ),
                const SizedBox(height: 16),
                Text(
                  'DoorShoppin Management',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: appGreen,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Admin sign in',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: 'Username',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: appGreen, width: 2)),
                  ),
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: appGreen, width: 2)),
                  ),
                  onSubmitted: (_) => _login(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: appGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Sign in'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
