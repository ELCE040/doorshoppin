import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

const Color appGreen = Color(0xFF28b244);

class HrScreen extends StatefulWidget {
  const HrScreen({super.key, this.showAppBar = true});

  static const routeName = '/hr';
  final bool showAppBar;

  @override
  State<HrScreen> createState() => _HrScreenState();
}

class _HrScreenState extends State<HrScreen> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _admins = [];
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  bool _usersLoading = false;
  String? _error;
  int? _currentAdminId;
  late TabController _tabController;

  Future<void> _loadAdmins() async {
    setState(() { _loading = true; _error = null; });
    try {
      _currentAdminId = await AuthService.getAdminId();
      final list = await ApiService.getHrAdmins();
      setState(() { _admins = list; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _loadUsers() async {
    setState(() => _usersLoading = true);
    try {
      final list = await ApiService.getAppUsers();
      setState(() { _users = list; _usersLoading = false; });
    } catch (e) {
      setState(() { _usersLoading = false; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _load() async {
    await _loadAdmins();
    if (_tabController.index == 1) _loadUsers();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _users.isEmpty && !_usersLoading) _loadUsers();
    });
    _loadAdmins();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showAddAdmin() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => const _AddAdminDialog(),
    );
    if (result != null && mounted) _loadAdmins();
  }

  void _showSendNotification() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => const _SendNotificationDialog(),
    );
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message']?.toString() ?? 'Notification sent')),
      );
    }
  }

  Future<void> _changePassword(Map<String, dynamic> admin) async {
    final id = admin['id'] is int ? admin['id'] as int : int.tryParse(admin['id']?.toString() ?? '');
    if (id == null) return;
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change password: ${admin['username']}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'New password (min 6)'),
          obscureText: true,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (controller.text.length >= 6) Navigator.pop(ctx, true);
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
    if (result != true || controller.text.length < 6 || !mounted) return;
    try {
      await ApiService.changeHrAdminPassword(id, controller.text);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _deleteAdmin(Map<String, dynamic> admin) async {
    final id = admin['id'] is int ? admin['id'] as int : int.tryParse(admin['id']?.toString() ?? '');
    if (id == null) return;
    if (id == _currentAdminId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot delete yourself')));
      return;
    }
    if ((admin['role'] ?? '').toString().toLowerCase() == 'manager') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot delete a manager')));
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove admin?'),
        content: Text('Remove "${admin['username']}"? They will no longer be able to sign in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await ApiService.deleteHrAdmin(id);
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin removed'))); _loadAdmins(); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('HR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              backgroundColor: appGreen,
              foregroundColor: Colors.white,
              bottom: TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: const [
                  Tab(text: 'Admins', icon: Icon(Icons.admin_panel_settings, size: 20)),
                  Tab(text: 'Users', icon: Icon(Icons.people, size: 20)),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: (_loading && _tabController.index == 0) || (_usersLoading && _tabController.index == 1)
                      ? null
                      : () => _tabController.index == 0 ? _loadAdmins() : _loadUsers(),
                ),
              ],
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAdminsTab(),
          _buildUsersTab(),
        ],
      ),
      floatingActionButton: _buildFab(),
    );
  }

  Widget _buildAdminsTab() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: appGreen));
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadAdmins,
              style: ElevatedButton.styleFrom(backgroundColor: appGreen, foregroundColor: Colors.white),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAdmins,
      color: appGreen,
      child: _admins.isEmpty
          ? const Center(child: Text('No admins'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _admins.length,
              itemBuilder: (context, i) {
                final a = _admins[i];
                final id = a['id'] is int ? a['id'] as int : int.tryParse(a['id']?.toString() ?? '');
                final isManager = (a['role'] ?? '').toString().toLowerCase() == 'manager';
                final isSelf = id == _currentAdminId;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isManager ? appGreen : Colors.grey,
                      child: Text((a['username']?.toString().substring(0, 1).toUpperCase() ?? '?')),
                    ),
                    title: Text(a['username']?.toString() ?? ''),
                    subtitle: Text('${a['email'] ?? ''}${isManager ? ' • Manager' : ''}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'password') _changePassword(a);
                        else if (v == 'delete') _deleteAdmin(a);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'password', child: Text('Change password')),
                        if (!isSelf && !isManager) const PopupMenuItem(value: 'delete', child: Text('Remove admin')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildUsersTab() {
    if (_usersLoading && _users.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: appGreen));
    }
    return RefreshIndicator(
      onRefresh: _loadUsers,
      color: appGreen,
      child: _users.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No registered users yet', style: TextStyle(color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('Users appear here when they sign in on the DoorShoppin app.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _users.length,
              itemBuilder: (context, i) {
                final u = _users[i];
                final email = u['email']?.toString() ?? '';
                final phone = u['phone']?.toString() ?? '';
                final name = u['name']?.toString();
                final hasFcm = u['hasFcmToken'] == true || u['hasFcmToken'] == 1;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: appGreen.withOpacity(0.2),
                      child: Icon(Icons.person, color: appGreen),
                    ),
                    title: Text(name != null && name.isNotEmpty ? name : (email.isNotEmpty ? email : phone.isNotEmpty ? phone : 'User #${u['id']}')),
                    subtitle: Text(
                      [if (email.isNotEmpty) email, if (phone.isNotEmpty) phone].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: hasFcm
                        ? Tooltip(
                            message: 'Can receive notifications',
                            child: Icon(Icons.notifications_active, color: appGreen, size: 20),
                          )
                        : null,
                  ),
                );
              },
            ),
    );
  }

  Widget? _buildFab() {
    if (_tabController.index == 1) {
      return FloatingActionButton.extended(
        onPressed: _showSendNotification,
        backgroundColor: appGreen,
        icon: const Icon(Icons.notifications),
        label: const Text('Send notification'),
      );
    }
    if (_loading || _error != null) return null;
    return FloatingActionButton(
      onPressed: _showAddAdmin,
      backgroundColor: appGreen,
      child: const Icon(Icons.person_add),
    );
  }
}

class _AddAdminDialog extends StatefulWidget {
  const _AddAdminDialog();

  @override
  State<_AddAdminDialog> createState() => _AddAdminDialogState();
}

class _AddAdminDialogState extends State<_AddAdminDialog> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final u = _username.text.trim();
    final e = _email.text.trim();
    final p = _password.text;
    if (u.isEmpty || e.isEmpty) {
      setState(() => _error = 'Username and email required');
      return;
    }
    if (p.length < 6) {
      setState(() => _error = 'Password at least 6 characters');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ApiService.addHrAdmin(username: u, email: e, password: p);
      if (mounted) Navigator.of(context).pop(<String, dynamic>{});
    } catch (err) {
      if (mounted) setState(() { _error = err.toString().replaceFirst('Exception: ', ''); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add admin'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _username, decoration: const InputDecoration(labelText: 'Username'), textCapitalization: TextCapitalization.none),
            const SizedBox(height: 12),
            TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 12),
            TextField(controller: _password, decoration: const InputDecoration(labelText: 'Password (min 6)'), obscureText: true),
            if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: Colors.red))],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: _saving ? null : _submit, child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Add')),
      ],
    );
  }
}

class _SendNotificationDialog extends StatefulWidget {
  const _SendNotificationDialog();

  @override
  State<_SendNotificationDialog> createState() => _SendNotificationDialogState();
}

class _SendNotificationDialogState extends State<_SendNotificationDialog> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Title is required');
      return;
    }
    if (body.isEmpty) {
      setState(() => _error = 'Message is required');
      return;
    }
    setState(() { _sending = true; _error = null; });
    try {
      final result = await ApiService.sendNotificationToUsers(title: title, body: body);
      final sent = result['sent'] ?? 0;
      final total = result['total'] ?? 0;
      final message = result['message']?.toString() ?? 'Sent to $sent of $total users';
      if (mounted) Navigator.of(context).pop(<String, dynamic>{'message': message});
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _sending = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send notification to users'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'All DoorShoppin app users with notifications enabled will receive this message (e.g. new products, promotions).',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. New products uploaded',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyController,
              decoration: const InputDecoration(
                labelText: 'Message',
                hintText: 'e.g. Check out our latest arrivals!',
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: Colors.red))],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _sending ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _sending ? null : _send,
          style: FilledButton.styleFrom(backgroundColor: appGreen),
          child: _sending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Send'),
        ),
      ],
    );
  }
}
