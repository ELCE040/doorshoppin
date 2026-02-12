import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'screens/login_screen.dart';
import 'screens/orders_list_screen.dart';
import 'screens/order_detail_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/main_shell_screen.dart';
import 'screens/notifications_screen.dart';

const Color appGreen = Color(0xFF28b244);

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ApiService.setSessionExpiredHandler(_handleSessionExpired);
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await NotificationService.initialize(navigatorKey, onShowInAppBannerCallback: showTopNotificationBanner);
  } catch (e) {
    debugPrint('Firebase init: $e');
  }
  runApp(const DoorShoppinManagementApp());
}

void _handleSessionExpired() {
  debugPrint('[App] Session expired. Logging out and returning to login screen.');
  AuthService.logout().whenComplete(() {
    final nav = navigatorKey.currentState;
    if (nav == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigatorKey.currentState?.pushNamedAndRemoveUntil(LoginScreen.routeName, (_) => false);
      });
      return;
    }
    nav.pushNamedAndRemoveUntil(LoginScreen.routeName, (_) => false);
  });
}

/// Shows a WhatsApp-style notification banner at the top, then auto-dismisses.
void showTopNotificationBanner(String title, String body) {
  final overlay = navigatorKey.currentState?.overlay;
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _TopNotificationBannerOverlay(
      title: title,
      body: body,
      onDismiss: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

/// WhatsApp-style top banner: slide + fade, rounded corners, shadow, logo, auto-dismiss.
class _TopNotificationBannerOverlay extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback onDismiss;

  const _TopNotificationBannerOverlay({
    required this.title,
    required this.body,
    required this.onDismiss,
  });

  @override
  State<_TopNotificationBannerOverlay> createState() =>
      _TopNotificationBannerOverlayState();
}

class _TopNotificationBannerOverlayState extends State<_TopNotificationBannerOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(_controller);
    _controller.forward();
    HapticFeedback.lightImpact();
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      _controller.reverse().then((_) => widget.onDismiss());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: widget.onDismiss,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: appGreen.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(Icons.store_rounded, color: appGreen, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.body,
                            style: const TextStyle(fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DoorShoppinManagementApp extends StatelessWidget {
  const DoorShoppinManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'DoorShoppin Management',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: appGreen, brightness: Brightness.light).copyWith(
          primary: appGreen,
          onPrimary: Colors.white,
          primaryContainer: appGreen.withOpacity(0.2),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey.shade50,
        appBarTheme: const AppBarTheme(
          backgroundColor: appGreen,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(backgroundColor: appGreen, foregroundColor: Colors.white),
        ),
      ),
      routes: {
        LoginScreen.routeName: (_) => const LoginScreen(),
        MainShellScreen.routeName: (_) => const MainShellScreen(),
        DashboardScreen.routeName: (_) => const DashboardScreen(),
        OrdersListScreen.routeName: (_) => const OrdersListScreen(),
        OrderDetailScreen.routeName: (_) => const OrderDetailScreen(),
        NotificationsScreen.routeName: (_) => const NotificationsScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == OrderDetailScreen.routeName && settings.arguments is int) {
          return MaterialPageRoute(
            builder: (_) => const OrderDetailScreen(),
            settings: settings,
          );
        }
        return null;
      },
      home: const _SplashRedirect(),
    );
  }
}

class _SplashRedirect extends StatefulWidget {
  const _SplashRedirect();

  @override
  State<_SplashRedirect> createState() => _SplashRedirectState();
}

class _SplashRedirectState extends State<_SplashRedirect> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _redirect());
  }

  Future<void> _redirect() async {
    debugPrint('[App] _redirect: checking AuthService.isLoggedIn()');
    final loggedIn = await AuthService.isLoggedIn();
    debugPrint('[App] _redirect: loggedIn=$loggedIn');
    if (!mounted) return;
    if (loggedIn) {
      debugPrint('[App] _redirect: pushing MainShell');
      navigatorKey.currentState?.pushReplacementNamed(MainShellScreen.routeName);
    } else {
      debugPrint('[App] _redirect: pushing Login');
      navigatorKey.currentState?.pushReplacementNamed(LoginScreen.routeName);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo.png',
              width: 56,
              height: 56,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(Icons.store, size: 56, color: appGreen),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: appGreen),
          ],
        ),
      ),
    );
  }
}
