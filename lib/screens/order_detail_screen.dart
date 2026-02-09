import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/order_model.dart';
import '../services/api_service.dart';

const Color appGreen = Color(0xFF28b244);

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key});

  static const routeName = '/order_detail';

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

const List<String> _orderStatuses = [
  'pending',
  'processing',
  'out_for_delivery',
  'delivered',
  'cancelled',
];

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  OrderModel? _order;
  bool _loading = true;
  bool _updatingStatus = false;
  String? _error;
  Position? _currentPosition;
  GoogleMapController? _mapController;

  Future<void> _loadOrder(int id) async {
    debugPrint('[OrderDetail] _loadOrder id=$id');
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final order = await ApiService.getOrderById(id);
      debugPrint('[OrderDetail] _loadOrder success orderId=${order.id}');
      if (mounted) setState(() {
        _order = order;
        _loading = false;
      });
      _getCurrentLocation();
    } catch (e) {
      debugPrint('[OrderDetail] _loadOrder error: $e');
      if (mounted) setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      if (mounted) setState(() => _currentPosition = pos);
    } catch (_) {}
  }

  Future<void> _openDirections() async {
    if (_order == null || !_order!.hasLocation) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No delivery location for this order')));
      return;
    }
    final lat = _order!.latitude!;
    final lng = _order!.longitude!;
    final origin = _currentPosition != null
        ? '${_currentPosition!.latitude},${_currentPosition!.longitude}'
        : null;
    // Google Maps URL: destination required; origin optional (current location)
    final url = origin != null
        ? 'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$lat,$lng&travelmode=driving'
        : 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open Maps')));
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is int && (_order == null || _order!.id != args)) {
      _loadOrder(args);
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending': return Colors.orange;
      case 'processing': return Colors.blue;
      case 'out_for_delivery': return Colors.indigo;
      case 'delivered': return appGreen;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending': return Icons.schedule;
      case 'processing': return Icons.autorenew;
      case 'out_for_delivery': return Icons.local_shipping;
      case 'delivered': return Icons.check_circle;
      case 'cancelled': return Icons.cancel;
      default: return Icons.receipt_long;
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending': return 'Pending';
      case 'processing': return 'Processing';
      case 'out_for_delivery': return 'Out for delivery';
      case 'delivered': return 'Delivered';
      case 'cancelled': return 'Cancelled';
      default: return status;
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    if (_order == null || _updatingStatus) return;
    setState(() => _updatingStatus = true);
    try {
      await ApiService.updateAdminOrderStatus(_order!.id, newStatus);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status updated to ${_statusLabel(newStatus)}. Customer notified.')),
      );
      await _loadOrder(_order!.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingStatus = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Order'), backgroundColor: appGreen, foregroundColor: Colors.white),
        body: const Center(child: CircularProgressIndicator(color: appGreen)),
      );
    }
    if (_error != null || _order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Order'), backgroundColor: appGreen, foregroundColor: Colors.white),
        body: Center(child: Text(_error ?? 'Order not found')),
      );
    }

    final order = _order!;
    final hasLocation = order.hasLocation;
    final destLatLng = hasLocation ? LatLng(order.latitude!, order.longitude!) : null;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(order.orderTrackingId ?? 'Order #${order.id}'),
        backgroundColor: appGreen,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person, color: appGreen),
                        const SizedBox(width: 8),
                        Text(order.customerName ?? 'Guest', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _statusColor(order.status).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_statusIcon(order.status), size: 18, color: _statusColor(order.status)),
                              const SizedBox(width: 6),
                              Text(_statusLabel(order.status), style: TextStyle(color: _statusColor(order.status), fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Change status (customer will be notified)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _orderStatuses.map((s) {
                        final isCurrent = (order.status ?? '').toLowerCase() == s.toLowerCase();
                        return ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_statusIcon(s), size: 16, color: isCurrent ? _statusColor(s) : Colors.grey.shade600),
                              const SizedBox(width: 6),
                              Text(_statusLabel(s)),
                            ],
                          ),
                          selected: isCurrent,
                          onSelected: _updatingStatus ? null : (selected) {
                            if (!isCurrent) _updateStatus(s);
                          },
                          selectedColor: _statusColor(s).withOpacity(0.3),
                          labelStyle: TextStyle(
                            color: isCurrent ? _statusColor(s) : Colors.grey.shade700,
                            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                          ),
                        );
                      }).toList(),
                    ),
                    if (order.customerPhone != null) _row('Phone', order.customerPhone!),
                    if (order.customerEmail != null) _row('Email', order.customerEmail!),
                    if (order.address != null) _row('Address', order.address!),
                    if (order.placeDescription != null) _row('Place', order.placeDescription!),
                    const Divider(),
                    Text('MK ${order.totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: appGreen)),
                    if (order.paymentMethod != null) Text('Payment: ${order.paymentMethod}', style: TextStyle(color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: order.items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final item = order.items[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item.productName ?? 'Item'} x ${item.quantity}',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        Text('MK ${(item.subtotal ?? (item.unitPrice ?? 0) * item.quantity).toStringAsFixed(2)}', style: const TextStyle(color: appGreen)),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (hasLocation) ...[
              const SizedBox(height: 16),
              const Text('Delivery location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              SizedBox(
                height: 220,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(target: destLatLng!, zoom: 15),
                    markers: {
                      Marker(
                        markerId: const MarkerId('dest'),
                        position: destLatLng,
                        infoWindow: InfoWindow(title: order.address ?? 'Delivery'),
                      ),
                      if (_currentPosition != null)
                        Marker(
                          markerId: const MarkerId('me'),
                          position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                          infoWindow: const InfoWindow(title: 'You'),
                        ),
                    },
                    onMapCreated: (c) => _mapController = c,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openDirections,
                  icon: const Icon(Icons.directions),
                  label: const Text('Get directions (Google Maps)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: appGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text('No delivery coordinates for this order.', style: TextStyle(color: Colors.grey.shade600)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text('$label:', style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
