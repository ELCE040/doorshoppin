import 'package:flutter/material.dart';
import '../config/api_config.dart';

/// Displays a product image with a fallback URL for Node uploads.
class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.imagePath,
    required this.placeholder,
    required this.fit,
    this.width,
    this.height,
    this.loadingBuilder,
  });

  final String? imagePath;
  final Widget placeholder;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    final urls = ApiConfig.productImageUrls(imagePath);
    if (urls.isEmpty) return placeholder;
    return _buildNetwork(urls, 0);
  }

  Widget _buildNetwork(List<String> urls, int index) {
    return Image.network(
      urls[index],
      fit: fit,
      width: width,
      height: height,
      loadingBuilder: loadingBuilder,
      errorBuilder: (_, __, ___) {
        if (index + 1 < urls.length) {
          return _buildNetwork(urls, index + 1);
        }
        return placeholder;
      },
    );
  }
}
