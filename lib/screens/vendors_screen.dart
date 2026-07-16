import 'package:flutter/material.dart';
import '../services/api_service.dart';

const Color appGreen = Color(0xFF28b244);

class VendorsScreen extends StatefulWidget {
  const VendorsScreen({super.key, this.showAppBar = true});

  static const routeName = '/vendors';
  final bool showAppBar;

  @override
  State<VendorsScreen> createState() => _VendorsScreenState();
}

class _VendorsScreenState extends State<VendorsScreen> {
  List<Map<String, dynamic>> _vendors = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'all') return _vendors;
    return _vendors.where((v) => (v['type']?.toString() ?? '') == _filter).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ApiService.getVendors(includeInactive: true);
      if (!mounted) return;
      setState(() {
        _vendors = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _openForm([Map<String, dynamic>? vendor]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _VendorDialog(vendor: vendor),
    );
    if (result != null && mounted) _load();
  }

  Future<void> _toggleActive(Map<String, dynamic> vendor) async {
    final id = vendor['id'] is int ? vendor['id'] as int : int.tryParse(vendor['id']?.toString() ?? '');
    if (id == null) return;
    try {
      await ApiService.updateVendor(id, active: !(vendor['active'] == true || vendor['active'] == 1));
      if (mounted) _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Stores', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              backgroundColor: appGreen,
              foregroundColor: Colors.white,
              actions: [
                IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load),
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
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'all', label: Text('All'), icon: Icon(Icons.apps)),
                          ButtonSegment(value: 'store', label: Text('Stores'), icon: Icon(Icons.storefront)),
                          ButtonSegment(value: 'restaurant', label: Text('Restaurants'), icon: Icon(Icons.restaurant)),
                        ],
                        selected: {_filter},
                        onSelectionChanged: (v) => setState(() => _filter = v.first),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        color: appGreen,
                        child: _filtered.isEmpty
                            ? ListView(
                                children: [
                                  const SizedBox(height: 120),
                                  Icon(Icons.storefront, size: 64, color: Colors.grey.shade400),
                                  const SizedBox(height: 12),
                                  Center(child: Text('No stores or restaurants', style: TextStyle(color: Colors.grey.shade600))),
                                ],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                                itemCount: _filtered.length,
                                itemBuilder: (context, i) {
                                  final v = _filtered[i];
                                  final type = v['type']?.toString() ?? 'store';
                                  final active = v['active'] == true || v['active'] == 1;
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: active ? appGreen.withOpacity(0.16) : Colors.grey.shade200,
                                        child: Icon(type == 'restaurant' ? Icons.restaurant : Icons.storefront, color: active ? appGreen : Colors.grey),
                                      ),
                                      title: Text(v['name']?.toString() ?? ''),
                                      subtitle: Text([
                                        type == 'restaurant' ? 'Restaurant' : 'Store',
                                        if ((v['phone']?.toString() ?? '').isNotEmpty) v['phone'].toString(),
                                        if (!active) 'Inactive',
                                      ].join(' - ')),
                                      trailing: PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == 'edit') _openForm(v);
                                          if (value == 'active') _toggleActive(v);
                                        },
                                        itemBuilder: (_) => [
                                          const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                          PopupMenuItem(value: 'active', child: Text(active ? 'Deactivate' : 'Activate')),
                                        ],
                                      ),
                                      onTap: () => _openForm(v),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: appGreen,
        icon: const Icon(Icons.add_business),
        label: const Text('Add'),
      ),
    );
  }
}

class _VendorDialog extends StatefulWidget {
  const _VendorDialog({this.vendor});

  final Map<String, dynamic>? vendor;

  @override
  State<_VendorDialog> createState() => _VendorDialogState();
}

class _VendorDialogState extends State<_VendorDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  String _type = 'store';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final v = widget.vendor;
    if (v != null) {
      _name.text = v['name']?.toString() ?? '';
      _phone.text = v['phone']?.toString() ?? '';
      _address.text = v['address']?.toString() ?? '';
      _type = v['type']?.toString() == 'restaurant' ? 'restaurant' : 'store';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = widget.vendor?['id'] is int ? widget.vendor!['id'] as int : int.tryParse(widget.vendor?['id']?.toString() ?? '');
      if (id == null) {
        await ApiService.createVendor(name: name, type: _type, phone: _phone.text.trim(), address: _address.text.trim());
      } else {
        await ApiService.updateVendor(id, name: name, type: _type, phone: _phone.text.trim(), address: _address.text.trim());
      }
      if (mounted) Navigator.pop(context, <String, dynamic>{});
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.vendor == null ? 'Add store' : 'Edit store'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'store', label: Text('Store'), icon: Icon(Icons.storefront)),
                ButtonSegment(value: 'restaurant', label: Text('Restaurant'), icon: Icon(Icons.restaurant)),
              ],
              selected: {_type},
              onSelectionChanged: _saving ? null : (v) => setState(() => _type = v.first),
            ),
            const SizedBox(height: 12),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name *')),
            const SizedBox(height: 12),
            TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone')),
            const SizedBox(height: 12),
            TextField(controller: _address, decoration: const InputDecoration(labelText: 'Address'), maxLines: 2),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: appGreen),
          child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'),
        ),
      ],
    );
  }
}
