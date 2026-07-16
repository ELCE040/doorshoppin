class ApiConfig {
  static const String baseUrl = 'https://doorshoppin.com/doorshoppin_backend/api';
  static const String siteBaseUrl = 'https://doorshoppin.com';

  /// Fixed product categories (filter chips and add/edit form).
  static const List<String> productCategories = [
    'Drinks',
    'Kids',
    'Stationery',
    'Groceries',
  ];

  /// Node API upload filename pattern: product_<timestamp>_<random>.<ext>
  static final RegExp _nodeUploadPattern = RegExp(
    r'^product_\d+_[a-zA-Z0-9]+\.[a-zA-Z0-9]+$',
  );

  /// Full URL for product images.
  ///
  /// Product images are stored in the public admin uploads folder:
  /// https://doorshoppin.com/admin/uploads/<filename>
  ///
  /// This normalizes old values like:
  /// - uploads/foo.jpg
  /// - /uploads/foo.jpg
  /// - /admin/uploads/foo.jpg
  /// - https://doorshoppin.com/doorshoppin_backend/uploads/foo.jpg
  static String productImageUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.trim().isEmpty) return '';

    var s = imageUrl.trim();
    if (s.startsWith('http://') || s.startsWith('https://')) {
      final match = RegExp(r'https?://[^/]+(.*)').firstMatch(s);
      if (match != null) s = match.group(1) ?? s;
    }

    final path = s.startsWith('/') ? s : '/$s';
    final filename = _extractUploadedFilename(path);
    final normalizedPath = filename.isNotEmpty ? '/admin/uploads/$filename' : path;

    return _appendCacheBuster(
      siteBaseUrl + normalizedPath,
      normalizedPath,
    );
  }

  static String _extractFilename(String s) {
    final parts = s.split('/');
    return parts.isNotEmpty ? parts.last.split('?').first : '';
  }

  static String _extractUploadedFilename(String s) {
    final filename = _extractFilename(s);
    final lower = s.toLowerCase();
    final hasImageExtension = RegExp(
      r'\.(jpg|jpeg|png|webp|gif|avif)$',
      caseSensitive: false,
    ).hasMatch(filename);

    if (lower.contains('/uploads/') ||
        lower.contains('/admin/uploads/') ||
        _nodeUploadPattern.hasMatch(filename) ||
        (hasImageExtension && !s.substring(1).contains('/'))) {
      return filename;
    }
    return '';
  }

  static String _appendCacheBuster(String baseUrl, String pathSegment) {
    final sep = baseUrl.contains('?') ? '&' : '?';
    return '$baseUrl${sep}v=${Uri.encodeComponent(pathSegment)}';
  }
}
