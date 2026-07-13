import 'package:flutter/material.dart';

import 'cover_image_provider.dart';

class CoverImage extends StatelessWidget {
  const CoverImage({
    required this.path,
    required this.fit,
    this.errorBuilder,
    super.key,
  });

  final String path;
  final BoxFit fit;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    if (_isRemote(path)) {
      return Image.network(path, fit: fit, errorBuilder: errorBuilder);
    }

    final ImageProvider<Object>? provider = coverImageProviderForPath(path);
    if (provider == null) {
      return _buildFallback(
        context,
        StateError('Unsupported or empty local cover path: $path'),
      );
    }

    return Image(image: provider, fit: fit, errorBuilder: errorBuilder);
  }

  bool _isRemote(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  Widget _buildFallback(BuildContext context, Object error) {
    if (errorBuilder != null) {
      return errorBuilder!(context, error, null);
    }
    return const SizedBox.shrink();
  }
}
