import 'dart:convert';
import 'dart:io';

import '../../../utils/app_paths.dart';
import '../../settings/presentation/settings_provider.dart';

class AiSubtitleCacheEntry {
  const AiSubtitleCacheEntry({
    required this.episodeId,
    required this.videoPath,
    required this.cacheFile,
    required this.lineCount,
    required this.provider,
    required this.model,
    required this.generatedAt,
    required this.sizeBytes,
    this.chineseLineCount = 0,
    this.translationWarning,
    this.generationSource,
    this.referenceSignature,
  });

  final String episodeId;
  final String videoPath;
  final File cacheFile;
  final int lineCount;
  final String provider;
  final String model;
  final DateTime generatedAt;
  final int sizeBytes;

  /// 已带中文翻译的行数（0 表示这次生成没有翻译成功）。
  final int chineseLineCount;

  /// 生成时记录下来的翻译/时间轴警告，例如
  /// “英文词级字幕已生成，但中文翻译失败：…”。
  final String? translationWarning;

  /// 生成来源：`subtitle-text` 表示用「字幕文本文件」生成
  /// （本地 Whisper 只对齐时间轴，文字来自文件）。
  final String? generationSource;
  final String? referenceSignature;
}

class AsrSubtitleCache {
  /// Cache files live under `<数据目录>/asr_subtitles` (portable desktop:
  /// `<exe目录>/data/asr_subtitles`); exports go under the downloads root
  /// (portable desktop: the same `<exe目录>/data` folder).
  const AsrSubtitleCache({
    this.appSupportDirectory = AppPaths.dataDirectory,
    this.downloadsDirectory = AppPaths.downloadsRootDirectory,
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

  /// Reads a cached AI subtitle.
  ///
  /// [referenceSignature] 传 null（或空串）表示“当前拿不到参考字幕”，
  /// 此时不做参考比对；只有拿到了参考且与生成时记录的原参考、生成结果签名
  /// 都不一致时，才判定这份缓存不再适用。
  ///
  /// 只有在缓存文件本身损坏（无法解析 / 版本过期）时才会删除它：
  /// 设置变化、参考字幕变化、视频暂时不可访问都只让本次读取返回 null
  /// （播放页会重新生成），缓存文件会保留下来，这样「设置 → 管理 AI 字幕」
  /// 里始终能看到、导出、编辑已生成的字幕，不会出现“生成完却找不到”的空列表。
  Future<String?> read({
    required String episodeId,
    required String videoPath,
    LearningSettingsState? settings,
    String? referenceSignature,
  }) async {
    final File file = await cacheFileFor(
      episodeId: episodeId,
      videoPath: videoPath,
    );
    if (!file.existsSync()) {
      return null;
    }
    final String content;
    try {
      content = await file.readAsString();
    } catch (_) {
      // 读不到（文件被占用等）时按“没有缓存”处理，绝不删除用户的字幕。
      return null;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      _deleteFiles(file);
      return null;
    }
    if (decoded is! Map<String, dynamic> || decoded['lines'] is! List) {
      _deleteFiles(file);
      return null;
    }
    if (settings != null && decoded['version'] != 1) {
      _deleteFiles(file);
      return null;
    }
    if (settings != null) {
      bool matches;
      try {
        matches = _metadataMatches(
          file: file,
          videoPath: videoPath,
          settings: settings,
          referenceSignature: referenceSignature,
        );
      } catch (_) {
        matches = false;
      }
      if (!matches) {
        return null;
      }
    }
    return content;
  }

  Future<File> write({
    required String episodeId,
    required String videoPath,
    required String content,
    LearningSettingsState? settings,
    String? referenceSignature,
    String? generatedSignature,
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
    _writeAtomically(file, content);
    if (settings != null) {
      _writeAtomically(
        _metadataFile(file),
        jsonEncode(<String, Object?>{
          ..._metadata(
            videoPath: videoPath,
            settings: settings,
            referenceSignature: referenceSignature,
            generatedSignature: generatedSignature,
          ),
          'episodeId': episodeId,
          'generatedAtMs': DateTime.now().millisecondsSinceEpoch,
        }),
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
    _deleteFiles(file);
  }

  Future<List<AiSubtitleCacheEntry>> listEntries() async {
    final Directory root = await _cacheRoot();
    if (!root.existsSync()) return const <AiSubtitleCacheEntry>[];
    final List<AiSubtitleCacheEntry> entries = <AiSubtitleCacheEntry>[];
    for (final FileSystemEntity entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.words.json')) continue;
      try {
        final Object? raw = jsonDecode(entity.readAsStringSync());
        if (raw is! Map<String, dynamic> || raw['lines'] is! List) continue;
        final File metadataFile = _metadataFile(entity);
        Map<String, dynamic> metadata = <String, dynamic>{};
        if (metadataFile.existsSync()) {
          final Object? decoded = jsonDecode(metadataFile.readAsStringSync());
          if (decoded is Map<String, dynamic>) metadata = decoded;
        }
        final FileStat stat = entity.statSync();
        final int? generatedAtMs = metadata['generatedAtMs'] as int?;
        final List<dynamic> lines = raw['lines'] as List<dynamic>;
        entries.add(
          AiSubtitleCacheEntry(
            episodeId:
                metadata['episodeId'] as String? ??
                entity.parent.path.split(Platform.pathSeparator).last,
            videoPath: metadata['videoPath'] as String? ?? entity.path,
            cacheFile: entity,
            lineCount: lines.length,
            chineseLineCount: lines
                .whereType<Map<String, dynamic>>()
                .where(
                  (Map<String, dynamic> line) =>
                      (line['chinese'] as String? ?? '').trim().isNotEmpty,
                )
                .length,
            translationWarning: _entryWarning(raw),
            generationSource: raw['source'] as String?,
            provider: metadata['asrProvider'] as String? ?? '未知服务',
            model: metadata['asrModel'] as String? ?? '未知模型',
            generatedAt: generatedAtMs == null
                ? stat.modified
                : DateTime.fromMillisecondsSinceEpoch(generatedAtMs),
            sizeBytes: stat.size,
            referenceSignature: metadata['referenceSignature'] as String?,
          ),
        );
      } catch (_) {
        // A damaged cache is ignored here and cleaned when the player reads it.
      }
    }
    entries.sort(
      (AiSubtitleCacheEntry a, AiSubtitleCacheEntry b) =>
          b.generatedAt.compareTo(a.generatedAt),
    );
    return entries;
  }

  Future<Map<String, dynamic>> readEntry(AiSubtitleCacheEntry entry) async {
    final Object? decoded = jsonDecode(entry.cacheFile.readAsStringSync());
    if (decoded is! Map<String, dynamic> || decoded['lines'] is! List) {
      throw const FormatException('invalid-asr-subtitle-cache');
    }
    return decoded;
  }

  Future<void> updateEntry(
    AiSubtitleCacheEntry entry,
    Map<String, dynamic> content,
  ) async {
    if (content['lines'] is! List) {
      throw const FormatException('invalid-asr-subtitle-cache');
    }
    _writeAtomically(entry.cacheFile, jsonEncode(content));
  }

  Future<File> exportEntry(AiSubtitleCacheEntry entry) async {
    if (!entry.cacheFile.existsSync()) {
      throw StateError('missing-asr-subtitle-cache');
    }
    final Directory targetDir = await _exportDirectory();
    return entry.cacheFile.copySync(
      _availableExportPath(targetDir, _fileName(entry.cacheFile.path)),
    );
  }

  Future<void> deleteEntry(AiSubtitleCacheEntry entry) async {
    _deleteFiles(entry.cacheFile);
    final Directory jobs = Directory(
      '${entry.cacheFile.parent.path}${Platform.pathSeparator}jobs',
    );
    if (jobs.existsSync()) jobs.deleteSync(recursive: true);
  }

  Future<void> deleteAll() async {
    final Directory root = await _cacheRoot();
    if (root.existsSync()) root.deleteSync(recursive: true);
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
    final Directory sourceRoot = await _cacheRoot();
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
    )..createSync(recursive: true);
    return targetDir;
  }

  /// 判断一份缓存是否仍然符合当前设置与视频（管理页用来提示“设置已变更”）。
  /// 同步实现（只做文件读取与比较），便于界面在测试/启动时立即拿到结果。
  bool isUpToDate({
    required AiSubtitleCacheEntry entry,
    required LearningSettingsState settings,
    String? referenceSignature,
  }) {
    try {
      return _metadataMatches(
        file: entry.cacheFile,
        videoPath: entry.videoPath,
        settings: settings,
        referenceSignature: referenceSignature,
      );
    } catch (_) {
      return false;
    }
  }

  bool _metadataMatches({
    required File file,
    required String videoPath,
    required LearningSettingsState settings,
    String? referenceSignature,
  }) {
    final File metadataFile = _metadataFile(file);
    if (!metadataFile.existsSync()) return false;
    final Object? decoded = jsonDecode(metadataFile.readAsStringSync());
    if (decoded is! Map<String, dynamic>) return false;
    // 参考字幕签名只是“软”信号：
    // 生成完成后程序会把结果保存成 `.en.srt` / `.zh.srt` 并挂到剧集上，
    // 重新打开时参考字幕就变成了生成结果本身（签名必然与原参考不同）；
    // 若据此判定缓存失效，双语 AI 字幕（以及管理页里的条目）会在重启后消失。
    // 因此这里接受“原参考”或“生成结果”任一签名。
    final String storedSignature =
        decoded['referenceSignature'] as String? ?? '';
    final String current = (referenceSignature ?? '').trim();
    if (storedSignature.isNotEmpty && current.isNotEmpty) {
      final String storedGenerated =
          decoded['generatedSignature'] as String? ?? '';
      final bool matchesOriginal = current == storedSignature;
      final bool matchesGenerated =
          storedGenerated.isNotEmpty && current == storedGenerated;
      if (!matchesOriginal && !matchesGenerated) {
        return false;
      }
    }
    // The recorded `videoPath` is informational: the app folder may move
    // (portable USB drive), so identity is checked via size/modified-time
    // below instead of the absolute path. `referenceSignature` is compared
    // explicitly above (only when the cache stored one).
    return _expectedMetadataEntries(
      videoPath: videoPath,
      settings: settings,
    ).every(
      (MapEntry<String, Object?> entry) => decoded[entry.key] == entry.value,
    );
  }

  /// 需要与缓存元数据逐项比对的字段（忽略仅作参考的路径与签名）。
  static List<MapEntry<String, Object?>> _expectedMetadataEntries({
    required String videoPath,
    required LearningSettingsState settings,
  }) {
    return _metadata(videoPath: videoPath, settings: settings).entries
        .where(
          (MapEntry<String, Object?> entry) =>
              entry.key != 'videoPath' &&
              entry.key != 'referenceSignature' &&
              entry.key != 'generatedSignature',
        )
        .toList(growable: false);
  }

  Future<Directory> _cacheRoot() async {
    final Directory root = await appSupportDirectory();
    return Directory('${root.path}${Platform.pathSeparator}asr_subtitles');
  }

  static Map<String, Object?> _metadata({
    required String videoPath,
    required LearningSettingsState settings,
    String? referenceSignature,
    String? generatedSignature,
  }) {
    final File video = File(videoPath);
    int? size;
    int? modifiedMs;
    try {
      final FileStat stat = video.statSync();
      size = stat.size;
      modifiedMs = stat.modified.millisecondsSinceEpoch;
    } catch (_) {
      // 视频暂时不可访问（U 盘未就绪、文件被移动）时不要抛异常：
      // 调用方据此判定为“不匹配”，但缓存文件会保留下来。
    }
    return <String, Object?>{
      'version': 1,
      'videoPath': video.absolute.path,
      'videoSize': size,
      'videoModifiedMs': modifiedMs,
      'asrProvider': settings.asrProvider,
      'asrBaseUrl': settings.asrBaseUrl,
      'asrModel': settings.asrModel,
      'bilingual': settings.generateBilingualAsrSubtitles,
      if (referenceSignature?.isNotEmpty ?? false)
        'referenceSignature': referenceSignature,
      if (generatedSignature?.isNotEmpty ?? false)
        'generatedSignature': generatedSignature,
      if (settings.generateBilingualAsrSubtitles) ...<String, Object?>{
        'translationProvider': settings.translationProvider,
        'translationBaseUrl': settings.translationBaseUrl,
        'translationModel': settings.translationModel,
      },
    };
  }

  /// 从缓存 JSON 中取出生成时记录的警告（翻译未完成 / 时间轴估算）。
  static String? _entryWarning(Map<String, dynamic> raw) {
    final List<String> warnings = <String>[
      for (final String key in <String>['translationWarning', 'timingWarning'])
        if ((raw[key] as String? ?? '').trim().isNotEmpty)
          (raw[key] as String).trim(),
    ];
    return warnings.isEmpty ? null : warnings.join('；');
  }

  File _metadataFile(File file) => File('${file.path}.meta.json');

  void _deleteFiles(File file) {
    for (final File target in <File>[file, _metadataFile(file)]) {
      if (target.existsSync()) target.deleteSync();
    }
  }

  void _writeAtomically(File file, String content) {
    final File part = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.part',
    );
    try {
      part
        ..writeAsStringSync(content, flush: true)
        ..renameSync(file.path);
    } finally {
      if (part.existsSync()) part.deleteSync();
    }
  }

  String _wordsFileName(String videoPath) {
    final String fileName = _fileName(videoPath);
    final int dot = fileName.lastIndexOf('.');
    final String baseName = dot <= 0 ? fileName : fileName.substring(0, dot);
    return '$baseName.words.json';
  }

  String _availableExportPath(Directory directory, String fileName) {
    final String direct = '${directory.path}${Platform.pathSeparator}$fileName';
    if (!File(direct).existsSync()) return direct;
    final bool isWordsJson = fileName.endsWith('.words.json');
    final int dot = fileName.lastIndexOf('.');
    final String extension = isWordsJson
        ? '.words.json'
        : dot <= 0
        ? ''
        : fileName.substring(dot);
    final String baseName = fileName.substring(
      0,
      fileName.length - extension.length,
    );
    int suffix = 2;
    while (true) {
      final String candidate =
          '${directory.path}${Platform.pathSeparator}$baseName ($suffix)$extension';
      if (!File(candidate).existsSync()) return candidate;
      suffix += 1;
    }
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
