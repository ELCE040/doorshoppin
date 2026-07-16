import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';
import 'orders_list_screen.dart';
import 'products_screen.dart';
import 'vendors_screen.dart';
import 'hr_screen.dart';
import 'notifications_screen.dart';

const Color appGreen = Color(0xFF28b244);

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  static const routeName = '/main';

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _currentIndex = 0;
  bool _isManager = false;
  bool _loadingRole = true;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final isManager = await AuthService.isManager();
    if (mounted) {
      final count = isManager ? 5 : 4;
      setState(() {
        _isManager = isManager;
        _loadingRole = false;
        if (_currentIndex >= count) _currentIndex = count - 1;
      });
    }
  }

  Widget _body() {
    if (_loadingRole) {
      return const Center(child: CircularProgressIndicator(color: appGreen));
    }
    switch (_currentIndex) {
      case 0:
        return DashboardScreen(showAppBar: false, onNavigateToOrders: () => setState(() => _currentIndex = 1));
      case 1:
        return const OrdersListScreen(showAppBar: false);
      case 2:
        return const ProductsScreen(showAppBar: false);
      case 3:
        return const VendorsScreen(showAppBar: false);
      case 4:
        return const HrScreen(showAppBar: false);
      default:
        return DashboardScreen(showAppBar: false, onNavigateToOrders: () => setState(() => _currentIndex = 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingRole) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: const Center(child: CircularProgressIndicator(color: appGreen)),
      );
    }
    final navItems = <_NavItem>[
      _NavItem(icon: Icons.home, label: 'Home'),
      _NavItem(icon: Icons.receipt_long, label: 'Orders'),
      _NavItem(icon: Icons.inventory_2, label: 'Products'),
      _NavItem(icon: Icons.storefront, label: 'Stores'),
      if (_isManager) _NavItem(icon: Icons.people, label: 'HR'),
    ];
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          _appBarTitle(),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: appGreen,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Notifications',
            onPressed: () async {
              await Navigator.of(context).pushNamed(NotificationsScreen.routeName);
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthService.logout();
              if (!mounted) return;
              Navigator.of(context).pushReplacementNamed(LoginScreen.routeName);
            },
          ),
        ],
      ),
      body: _body(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _effectiveIndex(_currentIndex, navItems.length),
        onTap: (i) => setState(() => _currentIndex = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: appGreen,
        unselectedItemColor: Colors.grey,
        items: navItems
            .map((e) => BottomNavigationBarItem(icon: Icon(e.icon), label: e.label))
            .toList(),
      ),
    );
  }

  int _effectiveIndex(int logical, int count) {
    if (count <= 0) return 0;
    return logical.clamp(0, count - 1).toInt();
  }

  String _appBarTitle() {
    if (_loadingRole) return 'DoorShoppin';
    switch (_currentIndex) {
      case 0:
        return 'Home';
      case 1:
        return 'Orders';
      case 2:
        return 'Products';
      case 3:
        return 'Stores';
      case 4:
        return 'HR';
      default:
        return 'DoorShoppin';
    }
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  _NavItem({required this.icon, required this.label});
}
