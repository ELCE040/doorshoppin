import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../config/api_config.dart';
import '../services/api_service.dart';

/// Fixed categories for filter and form (Drinks, Kids, Stationery).
List<String> get _productCategories => List.from(ApiConfig.productCategories);

const Color appGreen = Color(0xFF28b244);

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key, this.showAppBar = true});

  static const routeName = '/products';
  final bool showAppBar;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;
  String? _error;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategory;

  List<Map<String, dynamic>> get _filteredProducts {
    var list = _products;
    if (_selectedCategory != null && _selectedCategory!.isNotEmpty && _selectedCategory != 'all') {
      list = list.where((p) => (p['category']?.toString() ?? '').toLowerCase() == _selectedCategory!.toLowerCase()).toList();
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((p) {
        final name = (p['name']?.toString() ?? '').toLowerCase();
        final desc = (p['description']?.toString() ?? '').toLowerCase();
        final cat = (p['category']?.toString() ?? '').toLowerCase();
        return name.contains(q) || desc.contains(q) || cat.contains(q);
      }).toList();
    }
    return list;
  }

  /// Use fixed categories: Drinks, Kids, Stationery (from ApiConfig).
  List<String> get _categories => _productCategories;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(() => setState(() => _searchQuery = _searchController.text));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await ApiService.getAdminProducts();
      setState(() { _products = list; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  void _openProductPage(Map<String, dynamic> product) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => ProductDetailPage(product: product)),
    );
    if (result != null && mounted) _load();
  }

  void _showAddProduct() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const _ProductFormScreen()),
    );
    if (result != null && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Products', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
                      Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _load,
                        style: ElevatedButton.styleFrom(backgroundColor: appGreen, foregroundColor: Colors.white),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search products...',
                          prefixIcon: const Icon(Icons.search, color: appGreen),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onTap: () {},
                      ),
                    ),
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          _CategoryChip(
                            label: 'All',
                            selected: _selectedCategory == null || _selectedCategory == 'all',
                            onTap: () => setState(() => _selectedCategory = null),
                          ),
                          ..._categories.map((c) => _CategoryChip(
                                label: c,
                                selected: _selectedCategory?.toLowerCase() == c.toLowerCase(),
                                onTap: () => setState(() => _selectedCategory = c),
                              )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        color: appGreen,
                        child: _filteredProducts.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
                                    const SizedBox(height: 16),
                                    Text(
                                      _searchQuery.isNotEmpty || (_selectedCategory != null && _selectedCategory != 'all')
                                          ? 'No products match'
                                          : 'No products',
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                                    ),
                                    if (_products.isEmpty) ...[
                                      const SizedBox(height: 8),
                                      ElevatedButton.icon(
                                        onPressed: _showAddProduct,
                                        icon: const Icon(Icons.add),
                                        label: const Text('Add product'),
                                        style: ElevatedButton.styleFrom(backgroundColor: appGreen, foregroundColor: Colors.white),
                                      ),
                                    ],
                                  ],
                                ),
                              )
                            : GridView.builder(
                                padding: const EdgeInsets.all(12),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 0.72,
                                ),
                                itemCount: _filteredProducts.length,
                                itemBuilder: (context, i) {
                                  final p = _filteredProducts[i];
                                  return _ProductGridCard(
                                    product: p,
                                    onTap: () => _openProductPage(p),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
      floatingActionButton: !_loading && _error == null
          ? FloatingActionButton(
              onPressed: _showAddProduct,
              backgroundColor: appGreen,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: appGreen.withOpacity(0.3),
        checkmarkColor: appGreen,
      ),
    );
  }
}

class _ProductGridCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onTap;

  const _ProductGridCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final imageUrl = ApiConfig.productImageUrl(product['imageUrl']?.toString() ?? product['image_path']?.toString());
    final price = product['price'] is num ? (product['price'] as num).toDouble() : double.tryParse(product['price']?.toString() ?? '') ?? 0.0;
    final category = product['category']?.toString() ?? '';

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: imageUrl.isEmpty
                  ? Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.inventory_2, size: 48, color: appGreen),
                    )
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          color: Colors.grey.shade200,
                          child: Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded / (loadingProgress.expectedTotalBytes!)
                                  : null,
                              color: appGreen,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image_outlined, size: 48, color: appGreen),
                      ),
                    ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        product['name']?.toString() ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      if (category.isNotEmpty)
                        Text(
                          category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      Text(
                        'MK ${price.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: appGreen, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Product detail page: view + Edit + Delete. Tapping from grid opens this.
class ProductDetailPage extends StatelessWidget {
  const ProductDetailPage({super.key, required this.product});

  final Map<String, dynamic> product;

  @override
  Widget build(BuildContext context) {
    final imageUrl = ApiConfig.productImageUrl(product['imageUrl']?.toString() ?? product['image_path']?.toString());
    final price = product['price'] is num ? (product['price'] as num).toDouble() : double.tryParse(product['price']?.toString() ?? '') ?? 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(product['name']?.toString() ?? 'Product'),
        backgroundColor: appGreen,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') _openEdit(context);
              else if (v == 'delete') _confirmDelete(context);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (imageUrl.isEmpty)
              Container(
                height: 220,
                color: Colors.grey.shade200,
                child: const Center(child: Icon(Icons.inventory_2, size: 80, color: appGreen)),
              )
            else
              SizedBox(
                height: 220,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      height: 220,
                      color: Colors.grey.shade200,
                      child: Center(
                        child: CircularProgressIndicator(color: appGreen),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => Container(
                    height: 220,
                    color: Colors.grey.shade200,
                    child: const Center(child: Icon(Icons.broken_image_outlined, size: 80, color: appGreen)),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((product['category']?.toString() ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        product['category']?.toString() ?? '',
                        style: TextStyle(color: appGreen, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                  Text(
                    product['name']?.toString() ?? '',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'MK ${price.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: appGreen),
                  ),
                  if ((product['description']?.toString() ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      product['description']?.toString() ?? '',
                      style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openEdit(context),
                          icon: const Icon(Icons.edit),
                          label: const Text('Edit'),
                          style: OutlinedButton.styleFrom(foregroundColor: appGreen, side: const BorderSide(color: appGreen)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _confirmDelete(context),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openEdit(BuildContext context) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => _ProductFormScreen(product: product)),
    );
    if (result != null && context.mounted) Navigator.of(context).pop(result);
  }

  void _confirmDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('Remove "${product['name']}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    final id = product['id'] is int ? product['id'] as int : int.tryParse(product['id']?.toString() ?? '');
    if (id == null) return;
    try {
      await ApiService.deleteProduct(id);
      if (context.mounted) Navigator.of(context).pop(<String, dynamic>{});
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }
}

class _ProductFormScreen extends StatefulWidget {
  const _ProductFormScreen({this.product});

  final Map<String, dynamic>? product;

  @override
  State<_ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<_ProductFormScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  String? _selectedCategory; // One of Drinks, Kids, Stationery (from ApiConfig.productCategories)
  bool _saving = false;
  String? _error;
  String? _pickedFilePath;
  String? _existingImagePath;
  // Initial values when editing, so we can do "image only" update when nothing else changed.
  String? _initialName;
  String? _initialDesc;
  String? _initialCategory;
  String? _initialPrice;

  List<String> get _categoryOptions {
    final list = List<String>.from(_productCategories);
    final existing = widget.product?['category']?.toString()?.trim();
    if (existing != null && existing.isNotEmpty && !list.any((c) => c.toLowerCase() == existing.toLowerCase())) {
      list.add(existing); // keep existing category when editing product with other category
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      _initialName = p['name']?.toString()?.trim() ?? '';
      _initialDesc = p['description']?.toString()?.trim() ?? '';
      _initialCategory = p['category']?.toString()?.trim() ?? '';
      _initialPrice = p['price'] != null ? (p['price'] is num ? (p['price'] as num).toString() : p['price'].toString()).trim() : '';
      _name.text = _initialName ?? '';
      _desc.text = _initialDesc ?? '';
      final cat = p['category']?.toString()?.trim();
      _selectedCategory = cat?.isNotEmpty == true ? cat : _productCategories.isNotEmpty ? _productCategories.first : null;
      _price.text = p['price'] != null ? (p['price'] is num ? (p['price'] as num).toString() : p['price'].toString()) : '';
      _existingImagePath = p['imageUrl']?.toString() ?? p['image_path']?.toString();
    } else {
      _selectedCategory = _productCategories.isNotEmpty ? _productCategories.first : null;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
      if (x != null && mounted) setState(() => _pickedFilePath = x.path);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name required');
      return;
    }
    final description = _desc.text.trim();
    final category = _selectedCategory?.trim() ?? '';
    final price = double.tryParse(_price.text.trim());
    if (price == null || price < 0) {
      setState(() => _error = 'Valid price required');
      return;
    }
    if (widget.product == null) {
      if (_pickedFilePath == null) {
        setState(() => _error = 'Please pick an image from your device');
        return;
      }
      if (description.isEmpty) {
        setState(() => _error = 'Description is required');
        return;
      }
      if (category.isEmpty) {
        setState(() => _error = 'Category is required');
        return;
      }
    }
    setState(() { _saving = true; _error = null; });
    try {
      if (widget.product != null) {
        final id = widget.product!['id'] is int ? widget.product!['id'] as int : int.tryParse(widget.product!['id']?.toString() ?? '');
        if (id == null) throw Exception('Invalid product id');
        // When user only changed the image (picked new image, no text changes), send only image_path.
        final imageOnly = _pickedFilePath != null &&
            name == (_initialName ?? '') &&
            description == (_initialDesc ?? '') &&
            category == (_initialCategory ?? '') &&
            _price.text.trim() == (_initialPrice ?? '');
        debugPrint('[ProductForm] save edit id=$id imageOnly=$imageOnly');
        if (imageOnly) {
          final imagePath = await ApiService.uploadProductImage(_pickedFilePath!);
          await ApiService.updateProduct(id, imagePath: imagePath);
        } else {
          // Full update: only send image_path when user picked a new image; otherwise omit.
          String? imagePath;
          if (_pickedFilePath != null) {
            imagePath = await ApiService.uploadProductImage(_pickedFilePath!);
          }
          await ApiService.updateProduct(id, name: name, description: description, category: category, price: price, imagePath: imagePath);
        }
      } else {
        await ApiService.createProductViaPhp(
          name: name,
          description: description,
          category: category,
          price: price,
          imageFilePath: _pickedFilePath!,
        );
      }
      if (mounted) Navigator.of(context).pop(<String, dynamic>{});
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPreview = _pickedFilePath != null || (_existingImagePath != null && _existingImagePath!.trim().isNotEmpty);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.product == null ? 'Add product' : 'Edit product'),
        backgroundColor: appGreen,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Product image', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _saving ? null : _pickImage,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: appGreen.withOpacity(0.5)),
                ),
                clipBehavior: Clip.antiAlias,
                child: hasPreview
                    ? _pickedFilePath != null
                        ? Image.file(File(_pickedFilePath!), fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                        : Image.network(
                            ApiConfig.productImageUrl(_existingImagePath),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (_, __, ___) => _placeholder(),
                          )
                    : _placeholder(),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _saving ? null : _pickImage,
              icon: const Icon(Icons.photo_library, size: 20),
              label: Text(_pickedFilePath != null ? 'Change image' : 'Pick image from device'),
              style: TextButton.styleFrom(foregroundColor: appGreen),
            ),
            const SizedBox(height: 16),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name *'), textCapitalization: TextCapitalization.words),
            const SizedBox(height: 12),
            TextField(controller: _desc, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedCategory != null && _categoryOptions.contains(_selectedCategory) ? _selectedCategory : (_categoryOptions.isNotEmpty ? _categoryOptions.first : null),
              decoration: const InputDecoration(labelText: 'Category *'),
              items: _categoryOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: _saving ? null : (v) => setState(() => _selectedCategory = v),
            ),
            const SizedBox(height: 12),
            TextField(controller: _price, decoration: const InputDecoration(labelText: 'Price (MWK) *'), keyboardType: TextInputType.number),
            if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: Colors.red))],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(backgroundColor: appGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _saving ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate, size: 56, color: Colors.grey.shade500),
          const SizedBox(height: 8),
          Text('Tap to pick image', style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}
