import 'video_cover_extractor.dart';

VideoCoverExtractor createVideoCoverExtractor() {
  return const _UnsupportedVideoCoverExtractor();
}

Future<void> initializeVideoCoverExtractorImpl() async {}

class _UnsupportedVideoCoverExtractor implements VideoCoverExtractor {
  const _UnsupportedVideoCoverExtractor();

  @override
  Future<String?> extractCourseCover({
    required String courseId,
    required String videoPath,
    String? fallbackEpisodeCoverPath,
  }) async {
    return fallbackEpisodeCoverPath;
  }

  @override
  Future<String?> extractEpisodeCover({
    required String courseId,
    required String episodeId,
    required String videoPath,
  }) async {
    return null;
  }
}
