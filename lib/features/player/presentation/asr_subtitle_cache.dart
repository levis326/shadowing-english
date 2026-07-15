import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../settings/presentation/settings_provider.dart';

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
  }) async => await read(episodeId: episodeId, videoPath: videoPath) != null;

  Future<String?> read({
    required String episodeId,
    required String videoPath,
    LearningSettingsState? settings,
  }) async {
    final File file = await cacheFileFor(
      episodeId: episodeId,
      videoPath: videoPath,
    );
    if (!file.existsSync()) {
      return null;
    }
    try {
      final String content = await file.readAsString();
      final Object? decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic> || decoded['lines'] is! List) {
        throw const FormatException('invalid-asr-subtitle-cache');
      }
      if (settings != null &&
          !await _metadataMatches(
            file: file,
            videoPath: videoPath,
            settings: settings,
          )) {
        await _deleteFiles(file);
        return null;
      }
      return content;
    } catch (_) {
      await _deleteFiles(file);
      return null;
    }
  }

  Future<File> write({
    required String episodeId,
    required String videoPath,
    required String content,
    LearningSettingsState? settings,
  }) async {
    final File file = await cacheFileFor(
      episodeId: episodeId,
      videoPath: videoPath,
    );
    await file.parent.create(recursive: true);
    final Object? decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic> || decoded['lines'] is! List) {
      throw const FormatException('invalid-asr-subtitle-cache');
    }
    await _writeAtomically(file, content);
    if (settings != null) {
      await _writeAtomically(
        _metadataFile(file),
        jsonEncode(_metadata(videoPath: videoPath, settings: settings)),
      );
    }
    return file;
  }

  Future<void> delete({
    required String episodeId,
    required String videoPath,
  }) async {
    final File file = await cacheFileFor(
      episodeId: episodeId,
      videoPath: videoPath,
    );
    await _deleteFiles(file);
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

  Future<bool> _metadataMatches({
    required File file,
    required String videoPath,
    required LearningSettingsState settings,
  }) async {
    final File metadataFile = _metadataFile(file);
    if (!metadataFile.existsSync()) return false;
    final Object? decoded = jsonDecode(await metadataFile.readAsString());
    if (decoded is! Map<String, dynamic>) return false;
    return jsonEncode(decoded) ==
        jsonEncode(_metadata(videoPath: videoPath, settings: settings));
  }

  Map<String, Object?> _metadata({
    required String videoPath,
    required LearningSettingsState settings,
  }) {
    final File video = File(videoPath);
    final FileStat stat = video.statSync();
    return <String, Object?>{
      'version': 1,
      'videoPath': video.absolute.path,
      'videoSize': stat.size,
      'videoModifiedMs': stat.modified.millisecondsSinceEpoch,
      'asrProvider': settings.asrProvider,
      'asrBaseUrl': settings.asrBaseUrl,
      'asrModel': settings.asrModel,
      'bilingual': settings.generateBilingualAsrSubtitles,
      if (settings.generateBilingualAsrSubtitles) ...<String, Object?>{
        'translationProvider': settings.translationProvider,
        'translationBaseUrl': settings.translationBaseUrl,
        'translationModel': settings.translationModel,
      },
    };
  }

  File _metadataFile(File file) => File('${file.path}.meta.json');

  Future<void> _deleteFiles(File file) async {
    for (final File target in <File>[file, _metadataFile(file)]) {
      if (target.existsSync()) await target.delete();
    }
  }

  Future<void> _writeAtomically(File file, String content) async {
    final File part = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.part',
    );
    try {
      await part.writeAsString(content, flush: true);
      await part.rename(file.path);
    } finally {
      if (part.existsSync()) await part.delete();
    }
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
