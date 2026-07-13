import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'video_cover_extractor_impl.dart';

abstract class VideoCoverExtractor {
  Future<String?> extractEpisodeCover({
    required String courseId,
    required String episodeId,
    required String videoPath,
  });

  Future<String?> extractCourseCover({
    required String courseId,
    required String videoPath,
    String? fallbackEpisodeCoverPath,
  });
}

final Provider<VideoCoverExtractor> videoCoverExtractorProvider =
    Provider<VideoCoverExtractor>((Ref ref) {
      return createVideoCoverExtractor();
    });

Future<void> initializeVideoCoverExtractor({
  Future<void> Function()? initializeImpl,
}) {
  return (initializeImpl ?? initializeVideoCoverExtractorImpl)();
}
