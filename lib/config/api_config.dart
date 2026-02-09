class ApiConfig {
  static const String baseUrl = 'https://doorshoppin.com/doorshoppin_backend/api';
  static const String siteBaseUrl = 'https://doorshoppin.com';
  
  /// Where Node backend serves uploads (for images uploaded via management app).
  static const String backendOrigin = 'https://doorshoppin.com/doorshoppin_backend';

  /// Fixed product categories (filter chips and add/edit form).
  static const List<String> productCategories = ['Drinks', 'Kids', 'Stationery', 'Groceries'];

  /// PHP endpoint for adding product (multipart: name, description, category, price, image).
  static const String phpUploadProductUrl = 'https://doorshoppin.com/admin/upload_product.php';

  /// Node API upload filename pattern: product_<timestamp>_<random>.<ext>
  static final RegExp _nodeUploadPattern = RegExp(r'^product_\d+_[a-zA-Z0-9]+\.[a-zA-Z0-9]+$');

  /// Full URL for product images.
  /// 
  /// **Node-uploaded images (product_<timestamp>_<random>.ext):**
  /// - Route: GET /uploads/:filename
  /// - URL: https://doorshoppin.com/doorshoppin_backend/uploads/product_xxx.jpg
  /// - Server validates filename matches Node pattern and file exists
  /// 
  /// **Legacy PHP images (other paths):**
  /// - Route: /admin/uploads/xxx
  /// - URL: https://doorshoppin.com/admin/uploads/xxx.jpg
  /// 
  /// Appends a cache-busting query param so updated images show immediately.
  static String productImageUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.trim().isEmpty) return '';
    
    String s = imageUrl.trim();
    final bool isNodeUpload = _isNodeUpload(s);
    
    // Handle absolute URLs
    if (s.startsWith('http://') || s.startsWith('https://')) {
      if (isNodeUpload) {
        // Node-uploaded image: normalize to /uploads/filename format
        s = _extractNodeFilename(s);
        if (s.isNotEmpty) {
          s = '/uploads/$s';
        }
      } else {
        // Legacy PHP image: ensure it uses /admin/uploads/
        if (s.contains('/uploads/') && !s.contains('/admin/uploads/')) {
          s = s.replaceFirst('/uploads/', '/admin/uploads/');
        }
        // Extract just the path from full URL
        final match = RegExp(r'https?://[^/]+(.*)').firstMatch(s);
        if (match != null) {
          s = match.group(1) ?? s;
        }
      }
      return _buildImageUrl(s, isNodeUpload, s);
    }
    
    // Handle relative paths
    final path = s.startsWith('/') ? s : '/$s';
    
    if (isNodeUpload) {
      // Node upload: construct /uploads/filename
      final filename = _extractNodeFilename(path);
      final uploadPath = filename.isNotEmpty ? '/uploads/$filename' : path;
      return _buildImageUrl(uploadPath, true, path);
    } else {
      // Legacy PHP upload: ensure /admin/uploads/
      final normalizedPath = path.startsWith('/admin/uploads/')
          ? path
          : (path.startsWith('/uploads/') ? '/admin$path' : path);
      return _buildImageUrl(normalizedPath, false, path);
    }
  }

  /// Checks if a path/URL contains a Node-uploaded filename.
  /// Node pattern: product_<timestamp>_<random>.<ext>
  static bool _isNodeUpload(String s) {
    // Extract just the filename from path or URL
    final filename = _extractFilename(s);
    return _nodeUploadPattern.hasMatch(filename);
  }

  /// Extracts the filename from a path or full URL.
  /// Examples:
  ///   'product_1707123456_abc.jpg' → 'product_1707123456_abc.jpg'
  ///   '/uploads/product_1707123456_abc.jpg' → 'product_1707123456_abc.jpg'
  ///   'https://example.com/uploads/product_1707123456_abc.jpg' → 'product_1707123456_abc.jpg'
  static String _extractFilename(String s) {
    final parts = s.split('/');
    return parts.isNotEmpty ? parts.last.split('?').first : '';
  }

  /// Extracts a Node upload filename from a path or URL.
  /// Returns empty string if the filename doesn't match Node pattern.
  static String _extractNodeFilename(String s) {
    final filename = _extractFilename(s);
    if (_nodeUploadPattern.hasMatch(filename)) {
      return filename;
    }
    return '';
  }

  /// Builds the final image URL with appropriate base and cache-busting.
  static String _buildImageUrl(String path, bool isNodeUpload, String originalPath) {
    final base = isNodeUpload ? backendOrigin : siteBaseUrl;
    final fullUrl = base + path;
    return _appendCacheBuster(fullUrl, originalPath);
  }

  /// Appends ?v=<path> so each distinct path has a distinct URL.
  /// This ensures updated images show immediately without browser cache issues.
  /// Example: /uploads/product_123.jpg?v=%2Fuploads%2Fproduct_123.jpg
  static String _appendCacheBuster(String baseUrl, String pathSegment) {
    final sep = baseUrl.contains('?') ? '&' : '?';
    return '$baseUrl${sep}v=${Uri.encodeComponent(pathSegment)}';
  }
}