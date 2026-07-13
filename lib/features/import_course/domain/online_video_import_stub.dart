import 'import_match.dart';

typedef OnlineVideoDownloadProgress =
    void Function(OnlineVideoImportProgress progress);

class OnlineVideoImportProgress {
  const OnlineVideoImportProgress({required this.label, this.value});

  final String label;
  final double? value;
}

class OnlineVideoImportResult {
  const OnlineVideoImportResult({
    required this.title,
    required this.videoPath,
    this.subtitleTracks = const <ImportSubtitleTrack>[],
  });

  final String title;
  final String videoPath;
  final List<ImportSubtitleTrack> subtitleTracks;
}

class OnlineVideoImporter {
  const OnlineVideoImporter();

  Future<OnlineVideoImportResult> downloadDirect(
    String url, {
    OnlineVideoDownloadProgress? onProgress,
  }) {
    throw UnsupportedError('网页端暂不支持下载视频，请在桌面端或 Android 设备上完成导入。');
  }
}
