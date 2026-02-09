import 'package:flutter/material.dart';
import '../models/stored_notification.dart';
import '../services/notification_service.dart';
import 'order_detail_screen.dart';

const Color appGreen = Color(0xFF28b244);

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  static const routeName = '/notifications';

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<StoredNotification> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await NotificationService.getStoredNotifications();
    if (mounted) {
      setState(() {
        _notifications = list;
        _loading = false;
      });
    }
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all notifications?'),
        content: const Text(
          'This will remove all notifications from the list. You can still view orders from the Orders tab.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear all', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await NotificationService.clearAllStoredNotifications();
      if (mounted) setState(() => _notifications = []);
    }
  }

  String _formatDate(String isoDate) {
    try {
      final d = DateTime.tryParse(isoDate);
      if (d == null) return isoDate;
      final now = DateTime.now();
      if (d.year == now.year && d.month == now.month && d.day == now.day) {
        return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      }
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: appGreen,
        foregroundColor: Colors.white,
        actions: [
          if (_notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear all',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: appGreen))
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'No notifications yet',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'New orders will appear here',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: appGreen,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      final n = _notifications[index];
                      final hasOrder = n.orderId != null;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: hasOrder ? appGreen.withOpacity(0.4) : Colors.grey.shade300,
                            width: 1,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: appGreen.withOpacity(0.15),
                            child: Icon(
                              hasOrder ? Icons.receipt_long : Icons.notifications,
                              color: appGreen,
                            ),
                          ),
                          title: Text(
                            n.title,
                            style: TextStyle(
                              fontWeight: n.read ? FontWeight.normal : FontWeight.w600,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                n.body,
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatDate(n.date),
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                              ),
                            ],
                          ),
                          trailing: hasOrder
                              ? const Icon(Icons.arrow_forward_ios, size: 14, color: appGreen)
                              : null,
                          onTap: () {
                            if (n.orderId != null) {
                              Navigator.of(context).pushNamed(
                                OrderDetailScreen.routeName,
                                arguments: n.orderId,
                              );
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
