import 'package:flutter/material.dart';

import '../../../shared/presentation/media/cover_image.dart';
import '../../../shared/presentation/pad/app_design_tokens.dart';

class LibraryCoursePoster extends StatelessWidget {
  const LibraryCoursePoster({
    required this.title,
    required this.path,
    required this.borderRadius,
    this.fit = BoxFit.cover,
    super.key,
  });

  final String title;
  final String path;
  final BorderRadius borderRadius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (path.trim().isEmpty) {
      return _PosterPlaceholder(
        title: title,
        borderRadius: borderRadius,
      );
    }

    return CoverImage(
      path: path,
      fit: fit,
      errorBuilder: (_, _, __) {
        return _PosterPlaceholder(
          title: title,
          borderRadius: borderRadius,
        );
      },
    );
  }
}

class LibraryCoursePosterTitle extends StatelessWidget {
  const LibraryCoursePosterTitle({
    required this.title,
    super.key,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      maxLines: 3,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w900,
        height: 1.15,
        color: AppDesignTokens.appWhite,
      ),
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder({
    required this.title,
    required this.borderRadius,
  });

  final String title;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppDesignTokens.primaryBlueDark,
        borderRadius: borderRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: LibraryCoursePosterTitle(title: title),
        ),
      ),
    );
  }
}
