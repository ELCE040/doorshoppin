import 'package:flutter/material.dart';
import '../models/order_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'order_detail_screen.dart';

const Color appGreen = Color(0xFF28b244);

class OrdersListScreen extends StatefulWidget {
  const OrdersListScreen({super.key, this.showAppBar = true});

  static const routeName = '/orders';
  final bool showAppBar;

  @override
  State<OrdersListScreen> createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends State<OrdersListScreen> {
  List<OrderModel> _orders = [];
  bool _loading = true;
  String? _error;

  Future<void> _loadOrders() async {
    debugPrint('[OrdersList] _loadOrders start');
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ApiService.getAdminOrders();
      debugPrint('[OrdersList] _loadOrders success count=${list.length}');
      setState(() {
        _orders = list;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[OrdersList] _loadOrders error: $e');
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    debugPrint('[OrdersList] initState, loading orders');
    _loadOrders();
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending': return Colors.orange;
      case 'processing': return Colors.blue;
      case 'delivering': return Colors.indigo;
      case 'out_for_delivery': return Colors.indigo;
      case 'completed': return appGreen;
      case 'delivered': return appGreen;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending': return Icons.schedule;
      case 'processing': return Icons.autorenew;
      case 'delivering': return Icons.local_shipping;
      case 'out_for_delivery': return Icons.local_shipping;
      case 'completed': return Icons.check_circle;
      case 'delivered': return Icons.check_circle;
      case 'cancelled': return Icons.cancel;
      default: return Icons.receipt_long;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Orders', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              backgroundColor: appGreen,
              foregroundColor: Colors.white,
              actions: [
                IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _loadOrders),
                IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () async {
                    await AuthService.logout();
                    if (!mounted) return;
                    Navigator.of(context).pushReplacementNamed(LoginScreen.routeName);
                  },
                ),
              ],
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: appGreen))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadOrders,
                        style: ElevatedButton.styleFrom(backgroundColor: appGreen, foregroundColor: Colors.white),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _orders.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text('No orders yet', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadOrders,
                      color: appGreen,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _orders.length,
                        itemBuilder: (context, index) {
                          final order = _orders[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: _statusColor(order.status).withOpacity(0.5), width: 2),
                            ),
                            child: InkWell(
                              onTap: () => Navigator.of(context).pushNamed(OrderDetailScreen.routeName, arguments: order.id),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(_statusIcon(order.status), color: _statusColor(order.status), size: 28),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                order.orderTrackingId ?? '#${order.id}',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                              ),
                                              Text(
                                                order.customerName ?? 'Guest',
                                                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: _statusColor(order.status).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            order.status,
                                            style: TextStyle(
                                              color: _statusColor(order.status),
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'MK ${order.totalAmount.toStringAsFixed(2)}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: appGreen, fontSize: 15),
                                    ),
                                    if (order.address != null && order.address!.isNotEmpty)
                                      Text(
                                        order.address!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
