import 'dart:io';

import 'package:path_provider/path_provider.dart';

class AsrSubtitleCache {
  const AsrSubtitleCache({
    this.appSupportDirectory = getApplicationSupportDirectory,
    this.downloadsDirectory = getDownloadsDirectory,
  });

  final Future<Directory> Function() appSupportDirectory;
  final Future<Directory?> Function() downloadsDirectory;

  Future<File> cacheFileFor({
    required String episodeId,
    required String videoPath,
  }) async {
    final Directory root = await appSupportDirectory();
    return File(
      '${root.path}${Platform.pathSeparator}asr_subtitles'
      '${Platform.pathSeparator}${_safeSegment(episodeId)}'
      '${Platform.pathSeparator}${_wordsFileName(videoPath)}',
    );
  }

  Future<bool> exists({
    required String episodeId,
    required String videoPath,
  }) async {
    return (await cacheFileFor(
      episodeId: episodeId,
      videoPath: videoPath,
    )).existsSync();
  }

  Future<String?> read({
    required String episodeId,
    required String videoPath,
  }) async {
    final File file = await cacheFileFor(
      episodeId: episodeId,
      videoPath: videoPath,
    );
    if (!file.existsSync()) {
      return null;
    }
    return file.readAsString();
  }

  Future<File> write({
    required String episodeId,
    required String videoPath,
    required String content,
  }) async {
    final File file = await cacheFileFor(
      episodeId: episodeId,
      videoPath: videoPath,
    );
    await file.parent.create(recursive: true);
    return file.writeAsString(content);
  }

  Future<void> delete({
    required String episodeId,
    required String videoPath,
  }) async {
    final File file = await cacheFileFor(
      episodeId: episodeId,
      videoPath: videoPath,
    );
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<File> exportOne({
    required String episodeId,
    required String videoPath,
  }) async {
    final File source = await cacheFileFor(
      episodeId: episodeId,
      videoPath: videoPath,
    );
    if (!source.existsSync()) {
      throw StateError('missing-asr-subtitle-cache');
    }
    final Directory targetDir = await _exportDirectory();
    return source.copy(
      '${targetDir.path}${Platform.pathSeparator}${_wordsFileName(videoPath)}',
    );
  }

  Future<int> exportAll() async {
    final Directory root = await appSupportDirectory();
    final Directory sourceRoot = Directory(
      '${root.path}${Platform.pathSeparator}asr_subtitles',
    );
    if (!sourceRoot.existsSync()) {
      return 0;
    }
    final Directory targetDir = await _exportDirectory();
    int count = 0;
    for (final FileSystemEntity entity in sourceRoot.listSync(
      recursive: true,
    )) {
      if (entity is! File || !entity.path.endsWith('.words.json')) {
        continue;
      }
      await entity.copy(
        '${targetDir.path}${Platform.pathSeparator}${_fileName(entity.path)}',
      );
      count += 1;
    }
    return count;
  }

  Future<Directory> _exportDirectory() async {
    final Directory? downloads = await downloadsDirectory();
    final Directory targetDir = Directory(
      '${(downloads ?? await appSupportDirectory()).path}'
      '${Platform.pathSeparator}Shadowing English'
      '${Platform.pathSeparator}AI Subtitles',
    );
    await targetDir.create(recursive: true);
    return targetDir;
  }

  String _wordsFileName(String videoPath) {
    final String fileName = _fileName(videoPath);
    final int dot = fileName.lastIndexOf('.');
    final String baseName = dot <= 0 ? fileName : fileName.substring(0, dot);
    return '$baseName.words.json';
  }

  String _fileName(String path) {
    return path
        .replaceAll(String.fromCharCode(92), Platform.pathSeparator)
        .split(Platform.pathSeparator)
        .last;
  }

  String _safeSegment(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp('_+'), '_');
  }
}
