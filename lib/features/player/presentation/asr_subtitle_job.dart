import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../settings/presentation/settings_provider.dart';
import '../../shared/data/word_lookup_service.dart';
import 'asr_subtitle_cache.dart';
import 'asr_subtitle_service.dart';
import 'player_mock_state.dart';
import 'player_subtitle_loader.dart';

typedef AsrChunkTranscriber =
    Future<Map<String, Object?>> Function({
      required AsrAudioChunk chunk,
      required LearningSettingsState settings,
    });
typedef AsrSentenceTranslator =
    Future<String?> Function({
      required String sentence,
      required LearningSettingsState settings,
    });

class AsrSubtitleGenerationException implements Exception {
  const AsrSubtitleGenerationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AsrSubtitleCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) {
      throw const AsrSubtitleGenerationException('AI 字幕生成已取消。');
    }
  }
}

class AsrSubtitleRepairSummary {
  const AsrSubtitleRepairSummary(this.itemCount);

  final int itemCount;

  String appendTo(String message) =>
      itemCount > 0 ? '$message，已自动修复 $itemCount 项时间轴数据' : message;
}

class _SubtitleQualityReport {
  _SubtitleQualityReport(this.provider);

  final String provider;
  final List<Map<String, Object?>> anomalies = <Map<String, Object?>>[];
  final List<Map<String, Object?>> chunks = <Map<String, Object?>>[];
  int wordOverlap = 0;
  int sentenceOverlap = 0;
  int chunkBoundaryOverlap = 0;
  int wordFix = 0;
  int wordDeleted = 0;
  int chunkBoundaryFix = 0;
  int repairCount = 0;

  void addOverlap({
    required String kind,
    required String previousText,
    required int previousStart,
    required int previousEnd,
    required String currentText,
    required int currentStart,
    required int currentEnd,
    required int overlapMs,
    required int sourceChunk,
    required int previousSourceChunk,
  }) {
    if (kind == 'word') {
      wordOverlap += 1;
    } else if (kind == 'sentence') {
      sentenceOverlap += 1;
      if (sourceChunk != previousSourceChunk) {
        chunkBoundaryOverlap += 1;
      }
    } else if (kind == 'chunkBoundary') {
      chunkBoundaryOverlap += 1;
    }
    anomalies.add(<String, Object?>{
      'kind': kind,
      'previousText': previousText,
      'previousStart': previousStart,
      'previousEnd': previousEnd,
      'currentText': currentText,
      'currentStart': currentStart,
      'currentEnd': currentEnd,
      'overlapMs': overlapMs,
      'sourceChunk': sourceChunk,
      'previousSourceChunk': previousSourceChunk,
      'provider': provider,
    });
  }

  void addChunk({
    required int sourceChunk,
    required int startOffsetMs,
    required int endOffsetMs,
    required List<Map<String, Object?>> lines,
  }) {
    final List<Map<String, Object?>> words = lines
        .expand(
          (Map<String, Object?> line) =>
              (line['words'] as List<dynamic>? ?? const <dynamic>[])
                  .whereType<Map<String, dynamic>>()
                  .map(Map<String, Object?>.from),
        )
        .toList(growable: false);
    chunks.add(<String, Object?>{
      'sourceChunk': sourceChunk,
      'startOffsetMs': startOffsetMs,
      'endOffsetMs': endOffsetMs,
      'firstWord': words.isEmpty ? '' : words.first['text'],
      'actualStart': words.isEmpty ? null : words.first['startMs'],
      'lastWord': words.isEmpty ? '' : words.last['text'],
      'actualEnd': words.isEmpty ? null : words.last['endMs'],
    });
  }

  Future<void> write(Directory jobDir, String finalStatus) {
    return File(
      '${jobDir.path}${Platform.pathSeparator}subtitle_quality_report.json',
    ).writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'provider': provider,
        'wordOverlap': wordOverlap,
        'sentenceOverlap': sentenceOverlap,
        'chunkBoundaryOverlap': chunkBoundaryOverlap,
        'wordFix': wordFix,
        'wordDeleted': wordDeleted,
        'chunkBoundaryFix': chunkBoundaryFix,
        'repairCount': repairCount,
        'chunks': chunks,
        'anomalies': anomalies,
        'finalStatus': finalStatus,
      }),
    );
  }
}

class AsrSubtitleJobRunner {
  const AsrSubtitleJobRunner({
    this.supportDirectory,
    this.cache = const AsrSubtitleCache(),
    this.service = const AsrSubtitleService(),
    this.cloudTranscribeChunk,
    this.translateSentence,
  });

  final Future<Directory> Function()? supportDirectory;
  final AsrSubtitleCache cache;
  final AsrSubtitleService service;
  final AsrChunkTranscriber? cloudTranscribeChunk;
  final AsrSentenceTranslator? translateSentence;

  static const int _repairableOverlapMs = 500;
  static final Set<String> _activeJobs = <String>{};

  Future<String> run({
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
    bool forceRegenerate = false,
    AsrProgressCallback? onProgress,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    final File video = File(videoPath);
    if (!video.existsSync()) {
      throw StateError('missing-video-file');
    }
    final String? bilingualConfigurationError = _bilingualConfigurationError(
      settings,
    );
    if (bilingualConfigurationError != null) {
      throw AsrSubtitleGenerationException(bilingualConfigurationError);
    }

    final String jobKey = _jobKey(
      episodeId: episodeId,
      videoPath: videoPath,
      settings: settings,
    );
    if (!_activeJobs.add(jobKey)) {
      throw const AsrSubtitleGenerationException('这个视频的 AI 字幕正在生成，请等待当前任务完成。');
    }
    List<AsrAudioChunk> chunks = const <AsrAudioChunk>[];
    try {
      cancellationToken?.throwIfCancelled();
      if (forceRegenerate) {
        final Directory previousJob = await jobDirectory(
          episodeId: episodeId,
          videoPath: videoPath,
          settings: settings,
        );
        if (previousJob.existsSync()) {
          await previousJob.delete(recursive: true);
        }
      }
      chunks = await service.prepareAudioChunks(video);
      cancellationToken?.throwIfCancelled();
      return await _runPrepared(
        episodeId: episodeId,
        videoPath: videoPath,
        settings: settings,
        chunks: chunks,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
    } finally {
      service.deleteTemporaryAudioChunks(chunks);
      _activeJobs.remove(jobKey);
    }
  }

  Future<String> _runPrepared({
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
    required List<AsrAudioChunk> chunks,
    AsrProgressCallback? onProgress,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    final Directory jobDir = await jobDirectory(
      episodeId: episodeId,
      videoPath: videoPath,
      settings: settings,
    );
    final Directory chunksDir = Directory(
      '${jobDir.path}${Platform.pathSeparator}chunks',
    );
    await chunksDir.create(recursive: true);
    final _SubtitleQualityReport report = _SubtitleQualityReport(
      settings.asrProvider,
    );

    final int totalMs = _estimatedTotalMs(chunks);
    await _writeJob(
      jobDir: jobDir,
      episodeId: episodeId,
      videoPath: videoPath,
      settings: settings,
      totalChunks: chunks.length,
      status: 'running',
      error: '',
    );
    int completed = 0;
    onProgress?.call(
      AsrSubtitleProgress(
        completedChunks: completed,
        totalChunks: chunks.length,
        currentMs: 0,
        totalMs: totalMs,
      ),
    );

    try {
      for (int index = 0; index < chunks.length; index += 1) {
        cancellationToken?.throwIfCancelled();
        final File chunkFile = File(
          '${chunksDir.path}${Platform.pathSeparator}${index.toString().padLeft(5, '0')}.json',
        );
        await _loadOrTranscribeValidChunk(
          chunkFile: chunkFile,
          chunk: chunks[index],
          chunkEndMs: index + 1 < chunks.length
              ? chunks[index + 1].offsetMs
              : chunks[index].offsetMs + 58000,
          settings: settings,
          sourceChunk: index,
          report: report,
          cancellationToken: cancellationToken,
        );
        final Object? decoded = jsonDecode(await chunkFile.readAsString());
        final List<Map<String, Object?>> chunkLines =
            decoded is Map<String, dynamic>
            ? (decoded['lines'] as List<dynamic>? ?? const <dynamic>[])
                  .whereType<Map<String, dynamic>>()
                  .map(Map<String, Object?>.from)
                  .toList(growable: false)
            : const <Map<String, Object?>>[];
        report.addChunk(
          sourceChunk: index,
          startOffsetMs: chunks[index].offsetMs,
          endOffsetMs: index + 1 < chunks.length
              ? chunks[index + 1].offsetMs
              : chunks[index].offsetMs + 58000,
          lines: chunkLines,
        );
        completed += 1;
        onProgress?.call(
          AsrSubtitleProgress(
            completedChunks: completed,
            totalChunks: chunks.length,
            currentMs: await _currentMs(chunkFile, chunks[index].offsetMs),
            totalMs: totalMs,
            previewText: await _previewText(chunkFile),
          ),
        );
      }
    } catch (error) {
      await report.write(jobDir, 'FAILED');
      await _writeJob(
        jobDir: jobDir,
        episodeId: episodeId,
        videoPath: videoPath,
        settings: settings,
        totalChunks: chunks.length,
        status: 'failed',
        error: error.toString(),
      );
      rethrow;
    }

    final String raw = await _mergeChunks(
      chunksDir,
      chunks.length,
      report: report,
    );
    late final String completedRaw;
    try {
      completedRaw = await _addChineseTranslations(
        raw: raw,
        settings: settings,
        jobDir: jobDir,
        cancellationToken: cancellationToken,
      );
    } catch (error) {
      await report.write(jobDir, 'FAILED');
      await _writeJob(
        jobDir: jobDir,
        episodeId: episodeId,
        videoPath: videoPath,
        settings: settings,
        totalChunks: chunks.length,
        status: 'failed',
        error: error.toString(),
      );
      rethrow;
    }
    final File part = File(
      '${jobDir.path}${Platform.pathSeparator}final.words.json.part',
    );
    await part.writeAsString(completedRaw);
    try {
      _validateFinalResult(completedRaw);
    } catch (error) {
      await report.write(jobDir, 'FAILED');
      await chunksDir.delete(recursive: true);
      await _writeJob(
        jobDir: jobDir,
        episodeId: episodeId,
        videoPath: videoPath,
        settings: settings,
        totalChunks: chunks.length,
        status: 'failed',
        error: error.toString(),
      );
      rethrow;
    }
    await cache.write(
      episodeId: episodeId,
      videoPath: videoPath,
      content: completedRaw,
      settings: settings,
    );
    await _writeJob(
      jobDir: jobDir,
      episodeId: episodeId,
      videoPath: videoPath,
      settings: settings,
      totalChunks: chunks.length,
      status: 'completed',
      error: '',
    );
    await report.write(jobDir, 'PASS');
    return completedRaw;
  }

  Future<String> _addChineseTranslations({
    required String raw,
    required LearningSettingsState settings,
    required Directory jobDir,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    if (!settings.generateBilingualAsrSubtitles) {
      return raw;
    }

    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    final List<dynamic> lines =
        decoded['lines'] as List<dynamic>? ?? const <dynamic>[];
    final File checkpoint = File(
      '${jobDir.path}${Platform.pathSeparator}translations.json',
    );
    final String signature = _translationSignature(settings);
    final Map<String, String> translations = await _loadTranslations(
      checkpoint,
      signature,
    );
    for (final dynamic line in lines) {
      if (line is! Map<String, dynamic>) {
        continue;
      }
      if ((line['chinese'] as String? ?? '').trim().isNotEmpty) {
        continue;
      }
      final String english = (line['english'] as String? ?? '').trim();
      if (english.isEmpty) {
        continue;
      }
      cancellationToken?.throwIfCancelled();
      final String key = _translationLineKey(line, english);
      final String? cached = translations[key];
      final String? chinese =
          cached ??
          await (translateSentence ??
                  const WordLookupService().translateSentence)(
                sentence: english,
                settings: settings,
              )
              .timeout(
                const Duration(seconds: 45),
                onTimeout: () =>
                    throw TimeoutException('双语字幕翻译超时，请检查网络后重试；已完成的翻译会保留。'),
              );
      if (chinese == null || chinese.trim().isEmpty) {
        throw const AsrSubtitleGenerationException(
          '双语字幕生成失败：翻译请求未返回结果。请检查“翻译”中的 API Key、服务地址和模型配置。',
        );
      }
      line['chinese'] = chinese.trim();
      if (cached == null) {
        translations[key] = chinese.trim();
        await _writeJsonAtomically(checkpoint, <String, Object?>{
          'version': 1,
          'signature': signature,
          'translations': translations,
        });
      }
      cancellationToken?.throwIfCancelled();
    }
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  String? _bilingualConfigurationError(LearningSettingsState settings) {
    if (!settings.generateBilingualAsrSubtitles || translateSentence != null) {
      return null;
    }
    if (settings.translationApiKey.trim().isEmpty) {
      return '无法生成双语字幕：请先在“翻译”中填写 API Key。';
    }
    if ((settings.translationProvider == '百度翻译' ||
            settings.translationProvider == '阿里云翻译') &&
        settings.translationApiSecret.trim().isEmpty) {
      return '无法生成双语字幕：${settings.translationProvider} 还需要填写 Secret。';
    }
    if (settings.translationBaseUrl.trim().isEmpty) {
      return '无法生成双语字幕：请在“翻译”中填写服务地址。';
    }
    if (_isAiTranslationProvider(settings.translationProvider) &&
        settings.translationModel.trim().isEmpty) {
      return '无法生成双语字幕：请在“翻译”中填写模型名称。';
    }
    return null;
  }

  bool _isAiTranslationProvider(String provider) {
    return provider == 'OpenAI' ||
        provider == 'OpenRouter' ||
        provider == 'SiliconFlow' ||
        provider == 'DeepSeek';
  }

  Future<Directory> jobDirectory({
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
  }) async {
    final Directory support = supportDirectory == null
        ? await getApplicationSupportDirectory()
        : await supportDirectory!();
    final String key = _jobKey(
      episodeId: episodeId,
      videoPath: videoPath,
      settings: settings,
    );
    return Directory(
      '${support.path}${Platform.pathSeparator}asr_subtitles'
      '${Platform.pathSeparator}${_safe(episodeId)}'
      '${Platform.pathSeparator}jobs'
      '${Platform.pathSeparator}$key',
    );
  }

  Future<AsrSubtitleRepairSummary> readRepairSummary({
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
  }) async {
    final Directory jobDir = await jobDirectory(
      episodeId: episodeId,
      videoPath: videoPath,
      settings: settings,
    );
    final File reportFile = File(
      '${jobDir.path}${Platform.pathSeparator}subtitle_quality_report.json',
    );
    if (!reportFile.existsSync()) {
      return const AsrSubtitleRepairSummary(0);
    }
    try {
      final Object? decoded = jsonDecode(await reportFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return const AsrSubtitleRepairSummary(0);
      }
      final int count =
          decoded['repairCount'] as int? ??
          (decoded['wordFix'] as int? ?? 0) +
              (decoded['wordDeleted'] as int? ?? 0) +
              (decoded['chunkBoundaryFix'] as int? ?? 0);
      return AsrSubtitleRepairSummary(count);
    } catch (_) {
      return const AsrSubtitleRepairSummary(0);
    }
  }

  Future<Map<String, Object?>> _transcribe({
    required AsrAudioChunk chunk,
    required LearningSettingsState settings,
  }) async {
    if (cloudTranscribeChunk != null) {
      return cloudTranscribeChunk!(chunk: chunk, settings: settings);
    }
    return service.generateCloudChunk(chunk: chunk, settings: settings);
  }

  Future<void> _loadOrTranscribeValidChunk({
    required File chunkFile,
    required AsrAudioChunk chunk,
    required int chunkEndMs,
    required LearningSettingsState settings,
    required int sourceChunk,
    required _SubtitleQualityReport report,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    for (int attempt = 0; attempt < 2; attempt += 1) {
      cancellationToken?.throwIfCancelled();
      late final Map<String, Object?> chunkJson;
      if (attempt == 0 && chunkFile.existsSync()) {
        try {
          final Object? decoded = jsonDecode(await chunkFile.readAsString());
          if (decoded is! Map<String, dynamic>) {
            throw StateError('invalid-asr-chunk');
          }
          chunkJson = Map<String, Object?>.from(decoded);
        } catch (_) {
          await chunkFile.delete();
          continue;
        }
      } else {
        chunkJson = await _transcribe(chunk: chunk, settings: settings).timeout(
          const Duration(minutes: 20),
          onTimeout: () => throw TimeoutException('AI 字幕生成超时，请重试或换更小模型。'),
        );
      }
      try {
        final Map<String, Object?> normalized = _normalizeChunkTimeline(
          chunkJson,
          chunkStartMs: chunk.offsetMs,
          chunkEndMs: chunkEndMs,
          sourceChunk: sourceChunk,
          report: report,
        );
        final Object? lines = normalized['lines'];
        if (lines is! List<dynamic> || lines.isNotEmpty) {
          _validateFinalResult(jsonEncode(normalized));
        }
        await chunkFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert(normalized),
        );
        return;
      } catch (error) {
        if (chunkFile.existsSync()) {
          await chunkFile.delete();
        }
        if (attempt == 1) {
          throw StateError(
            '第 ${sourceChunk + 1} 段处理失败：${_errorMessage(error)}',
          );
        }
      }
    }
  }

  void _validateFinalResult(String raw) {
    final List<PlayerSubtitleLine> lines = parseSubtitleLines(raw);
    if (lines.isEmpty) {
      throw StateError('字幕检查失败：没有识别到有效字幕。');
    }

    int previousEndMs = -1;
    for (int index = 0; index < lines.length; index += 1) {
      final PlayerSubtitleLine line = lines[index];
      final String location = '第 ${index + 1} 句';
      if (line.english.trim().isEmpty) {
        throw StateError('字幕检查失败：$location 存在空字幕。');
      }
      if (line.endMs <= line.startMs) {
        throw StateError('字幕检查失败：$location 存在无效时间轴。');
      }
      if (line.words.isEmpty) {
        throw StateError('字幕检查失败：$location 未返回词级时间戳，无法精准跟读单词。');
      }
      final int expectedWordCount = _wordCount(line.english);
      final int timedWordCount = line.words.fold<int>(
        0,
        (int count, PlayerSubtitleWord word) => count + _wordCount(word.text),
      );
      if (expectedWordCount > 0 && timedWordCount < expectedWordCount) {
        throw StateError('字幕检查失败：$location 不是每个英文单词都有词级时间戳。');
      }
      if (_comparableText(line.english) !=
          _comparableText(
            line.words.map((PlayerSubtitleWord word) => word.text).join(' '),
          )) {
        throw StateError('字幕检查失败：$location 的正文与词级时间戳文本不一致。');
      }
      int previousWordEndMs = -1;
      for (final PlayerSubtitleWord word in line.words) {
        if (previousWordEndMs >= 0 && word.startMs < previousWordEndMs) {
          throw StateError('字幕检查失败：$location 的单词时间轴乱序或重叠。');
        }
        previousWordEndMs = word.endMs;
      }
      if (previousEndMs >= 0 && line.startMs < previousEndMs - 250) {
        throw StateError('字幕检查失败：$location 时间轴乱序或重叠过多。');
      }
      previousEndMs = line.endMs;
    }
  }

  int _wordCount(String text) {
    return RegExp("[A-Za-z0-9]+(?:[’'-][A-Za-z0-9]+)?").allMatches(text).length;
  }

  String _comparableText(String text) => RegExp(
    '[A-Za-z0-9]+',
  ).allMatches(text).map((Match match) => match.group(0)!.toLowerCase()).join();

  Future<String> _mergeChunks(
    Directory chunksDir,
    int totalChunks, {
    required _SubtitleQualityReport report,
  }) async {
    final List<Map<String, Object?>> lines = <Map<String, Object?>>[];
    final Map<String, String> glossary = <String, String>{};
    for (int index = 0; index < totalChunks; index += 1) {
      final File chunkFile = File(
        '${chunksDir.path}${Platform.pathSeparator}${index.toString().padLeft(5, '0')}.json',
      );
      final Object? decoded = jsonDecode(await chunkFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw StateError('invalid-asr-chunk');
      }
      lines.addAll(
        (decoded['lines'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(
              (Map<String, dynamic> line) => <String, Object?>{
                ...line,
                '_sourceChunk': index,
              },
            ),
      );
      for (final Object? item
          in decoded['glossary'] as List<dynamic>? ?? const <dynamic>[]) {
        if (item is! Map<String, dynamic>) continue;
        final String word = (item['word'] as String? ?? '')
            .trim()
            .toLowerCase();
        final String definition = (item['definitionCn'] as String? ?? '')
            .trim();
        if (RegExp(r'^[a-z]{2,}$').hasMatch(word) && definition.isNotEmpty) {
          glossary.putIfAbsent(word, () => definition);
        }
      }
    }
    final List<Map<String, Object?>> boundaryNormalized =
        _normalizeChunkBoundaries(lines, report: report);
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'version': 1,
      'language': '',
      'lines': _normalizeTimeline(
        boundaryNormalized,
        report: report,
      ).map(_withoutSourceChunk).toList(growable: false),
      'glossary': glossary.entries
          .map(
            (MapEntry<String, String> entry) => <String, String>{
              'word': entry.key,
              'definitionCn': entry.value,
            },
          )
          .toList(growable: false),
    });
  }

  List<Map<String, Object?>> _normalizeTimeline(
    List<Map<String, Object?>> lines, {
    _SubtitleQualityReport? report,
  }) {
    final List<Map<String, Object?>> sorted =
        lines.map(Map<String, Object?>.from).toList(growable: false)..sort(
          (Map<String, Object?> a, Map<String, Object?> b) =>
              _timelineMs(a['startMs']).compareTo(_timelineMs(b['startMs'])),
        );
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    for (Map<String, Object?> line in sorted) {
      if (result.isEmpty) {
        result.add(line);
        continue;
      }
      final Map<String, Object?> previous = result.last;
      if (_sameOverlappingLine(previous, line)) {
        continue;
      }
      final int overlapMs =
          _timelineMs(previous['endMs']) - _timelineMs(line['startMs']);
      if (overlapMs > 0) {
        final int previousSourceChunk = _sourceChunk(previous);
        final int currentSourceChunk = _sourceChunk(line);
        report?.addOverlap(
          kind: 'sentence',
          previousText: previous['english'] as String? ?? '',
          previousStart: _timelineMs(previous['startMs']),
          previousEnd: _timelineMs(previous['endMs']),
          currentText: line['english'] as String? ?? '',
          currentStart: _timelineMs(line['startMs']),
          currentEnd: _timelineMs(line['endMs']),
          overlapMs: overlapMs,
          sourceChunk: currentSourceChunk,
          previousSourceChunk: previousSourceChunk,
        );
      }
      if (overlapMs > 0) {
        report?.repairCount += 1;
        if (overlapMs <= _repairableOverlapMs) {
          line = _shiftLine(line, overlapMs);
        } else if (_trimLineAtBoundary(
          previous,
          _timelineMs(line['startMs']),
        )) {
          report?.wordFix += 1;
        } else {
          line = _shiftLine(line, overlapMs);
        }
        if (_sourceChunk(previous) != _sourceChunk(line)) {
          report?.chunkBoundaryFix += 1;
        }
      }
      result.add(line);
    }
    return result;
  }

  List<Map<String, Object?>> _normalizeChunkBoundaries(
    List<Map<String, Object?>> lines, {
    required _SubtitleQualityReport report,
  }) {
    final Map<int, List<Map<String, Object?>>> byChunk =
        <int, List<Map<String, Object?>>>{};
    for (final Map<String, Object?> line in lines) {
      byChunk
          .putIfAbsent(_sourceChunk(line), () => <Map<String, Object?>>[])
          .add(Map<String, Object?>.from(line));
    }
    Map<String, Object?>? previousLastWord;
    int previousChunk = -1;
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    for (final int sourceChunk in byChunk.keys.toList()..sort()) {
      List<Map<String, Object?>> chunkLines = byChunk[sourceChunk]!
        ..sort(
          (Map<String, Object?> a, Map<String, Object?> b) =>
              _timelineMs(a['startMs']).compareTo(_timelineMs(b['startMs'])),
        );
      final Map<String, Object?>? firstWord = _firstWord(chunkLines);
      if (previousLastWord != null && firstWord != null) {
        final int overlapMs =
            _timelineMs(previousLastWord['endMs']) -
            _timelineMs(firstWord['startMs']);
        if (overlapMs > 0) {
          report.addOverlap(
            kind: 'chunkBoundary',
            previousText: previousLastWord['text'] as String? ?? '',
            previousStart: _timelineMs(previousLastWord['startMs']),
            previousEnd: _timelineMs(previousLastWord['endMs']),
            currentText: firstWord['text'] as String? ?? '',
            currentStart: _timelineMs(firstWord['startMs']),
            currentEnd: _timelineMs(firstWord['endMs']),
            overlapMs: overlapMs,
            sourceChunk: sourceChunk,
            previousSourceChunk: previousChunk,
          );
          if (overlapMs <= _repairableOverlapMs) {
            chunkLines = chunkLines
                .map((Map<String, Object?> line) => _shiftLine(line, overlapMs))
                .toList(growable: false);
            report
              ..chunkBoundaryFix += 1
              ..repairCount += 1;
          } else if (_trimPreviousLineAtBoundary(
            result,
            _timelineMs(firstWord['startMs']),
          )) {
            report
              ..chunkBoundaryFix += 1
              ..repairCount += 1;
          }
        }
      }
      final Map<String, Object?>? lastWord = _lastWord(chunkLines);
      if (lastWord != null) {
        previousLastWord = lastWord;
        previousChunk = sourceChunk;
      }
      result.addAll(chunkLines);
    }
    return result;
  }

  bool _trimPreviousLineAtBoundary(
    List<Map<String, Object?>> lines,
    int boundaryMs,
  ) {
    for (int index = lines.length - 1; index >= 0; index -= 1) {
      final Map<String, Object?> line = lines[index];
      if (_lineWords(line).isEmpty) continue;
      return _trimLineAtBoundary(line, boundaryMs);
    }
    return false;
  }

  bool _trimLineAtBoundary(Map<String, Object?> line, int boundaryMs) {
    final List<Map<String, Object?>> words = _lineWords(line);
    if (words.isEmpty) return false;
    final Map<String, Object?> lastWord = words.last;
    if (_timelineMs(lastWord['startMs']) >= boundaryMs ||
        _timelineMs(lastWord['endMs']) <= boundaryMs) {
      return false;
    }
    lastWord['endMs'] = boundaryMs;
    line['words'] = words;
    line['endMs'] = boundaryMs;
    return true;
  }

  Map<String, Object?>? _firstWord(List<Map<String, Object?>> lines) {
    for (final Map<String, Object?> line in lines) {
      final List<Map<String, Object?>> words = _lineWords(line);
      if (words.isNotEmpty) return words.first;
    }
    return null;
  }

  Map<String, Object?>? _lastWord(List<Map<String, Object?>> lines) {
    for (final Map<String, Object?> line in lines.reversed) {
      final List<Map<String, Object?>> words = _lineWords(line);
      if (words.isNotEmpty) return words.last;
    }
    return null;
  }

  List<Map<String, Object?>> _lineWords(Map<String, Object?> line) =>
      (line['words'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(Map<String, Object?>.from)
          .toList(growable: false);

  Map<String, Object?> _normalizeChunkTimeline(
    Map<String, Object?> chunk, {
    required int chunkStartMs,
    required int chunkEndMs,
    required int sourceChunk,
    required _SubtitleQualityReport report,
  }) {
    final List<Map<String, Object?>> lines =
        (chunk['lines'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(
              (Map<String, dynamic> line) => <String, Object?>{
                ...line,
                '_sourceChunk': sourceChunk,
              },
            )
            .toList(growable: false);
    final List<Map<String, Object?>> constrained = _constrainChunkTimeline(
      lines,
      chunkStartMs: chunkStartMs,
      chunkEndMs: chunkEndMs,
      report: report,
    );
    final List<Map<String, Object?>> normalized = _normalizeWords(
      constrained,
      report: report,
    );
    return <String, Object?>{
      ...chunk,
      'lines': _normalizeTimeline(
        normalized,
        report: report,
      ).map(_withoutSourceChunk).toList(growable: false),
    };
  }

  List<Map<String, Object?>> _constrainChunkTimeline(
    List<Map<String, Object?>> lines, {
    required int chunkStartMs,
    required int chunkEndMs,
    required _SubtitleQualityReport report,
  }) {
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    for (final Map<String, Object?> original in lines) {
      bool repaired = false;
      final Map<String, Object?> line = Map<String, Object?>.from(original);
      final List<Map<String, Object?>> originalWords = _lineWords(line);
      final List<Map<String, Object?>> words = <Map<String, Object?>>[];
      for (final Map<String, Object?> originalWord in originalWords) {
        final int startMs = _timelineMs(originalWord['startMs']);
        final int endMs = _timelineMs(originalWord['endMs']);
        if (endMs <= chunkStartMs || startMs >= chunkEndMs) {
          report.wordDeleted += 1;
          repaired = true;
          continue;
        }
        final Map<String, Object?> word = Map<String, Object?>.from(
          originalWord,
        );
        word['startMs'] = startMs < chunkStartMs ? chunkStartMs : startMs;
        word['endMs'] = endMs > chunkEndMs ? chunkEndMs : endMs;
        repaired =
            repaired || word['startMs'] != startMs || word['endMs'] != endMs;
        if (_timelineMs(word['endMs']) > _timelineMs(word['startMs'])) {
          words.add(word);
        } else {
          report.wordDeleted += 1;
          repaired = true;
        }
      }
      if (words.length != originalWords.length) {
        words.clear();
      }
      if (words.isNotEmpty) {
        line['words'] = words;
        line['startMs'] = _timelineMs(words.first['startMs']);
        line['endMs'] = _timelineMs(words.last['endMs']);
      } else {
        line['words'] = const <Map<String, Object?>>[];
        int startMs = _timelineMs(line['startMs']);
        int endMs = _timelineMs(line['endMs']);
        if (startMs < chunkStartMs || startMs >= chunkEndMs) {
          startMs = chunkStartMs;
          repaired = true;
        }
        if (endMs <= startMs || endMs > chunkEndMs) {
          final int tokenCount = _wordCount(line['english'] as String? ?? '');
          final int fallbackEndMs =
              startMs + (tokenCount > 0 ? tokenCount * 400 : 1000);
          endMs = fallbackEndMs < chunkEndMs ? fallbackEndMs : chunkEndMs;
          repaired = true;
        }
        if (endMs <= startMs) continue;
        line['startMs'] = startMs;
        line['endMs'] = endMs;
      }
      if (repaired) report.repairCount += 1;
      result.add(line);
    }
    return result;
  }

  List<Map<String, Object?>> _normalizeWords(
    List<Map<String, Object?>> lines, {
    required _SubtitleQualityReport report,
  }) {
    final List<Map<String, Object?>> sorted =
        lines.map(Map<String, Object?>.from).toList(growable: false)..sort(
          (Map<String, Object?> a, Map<String, Object?> b) =>
              _timelineMs(a['startMs']).compareTo(_timelineMs(b['startMs'])),
        );
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    for (final Map<String, Object?> line in sorted) {
      if (result.isNotEmpty && _sameOverlappingLine(result.last, line)) {
        continue;
      }
      List<Map<String, Object?>> words =
          (line['words'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(Map<String, Object?>.from)
              .where(
                (Map<String, Object?> word) =>
                    _timelineMs(word['endMs']) > _timelineMs(word['startMs']),
              )
              .toList(growable: false)
            ..sort(
              (Map<String, Object?> a, Map<String, Object?> b) => _timelineMs(
                a['startMs'],
              ).compareTo(_timelineMs(b['startMs'])),
            );
      final int originalCount =
          (line['words'] as List<dynamic>? ?? const <dynamic>[]).length;
      report.wordDeleted += originalCount - words.length;
      final String english = line['english'] as String? ?? '';
      bool repaired = false;
      if (words.isEmpty ||
          _comparableText(english) !=
              _comparableText(
                words
                    .map((Map<String, Object?> word) => word['text'] ?? '')
                    .join(' '),
              )) {
        words = _synthesizeWords(
          english,
          _timelineMs(line['startMs']),
          _timelineMs(line['endMs']),
        );
        report.wordFix += words.length;
        repaired = true;
      }
      Map<String, Object?>? previousWord;
      for (final Map<String, Object?> word in words) {
        if (previousWord != null &&
            _timelineMs(word['startMs']) < _timelineMs(previousWord['endMs'])) {
          final int overlapMs =
              _timelineMs(previousWord['endMs']) - _timelineMs(word['startMs']);
          report.addOverlap(
            kind: 'word',
            previousText: previousWord['text'] as String? ?? '',
            previousStart: _timelineMs(previousWord['startMs']),
            previousEnd: _timelineMs(previousWord['endMs']),
            currentText: word['text'] as String? ?? '',
            currentStart: _timelineMs(word['startMs']),
            currentEnd: _timelineMs(word['endMs']),
            overlapMs: overlapMs,
            sourceChunk: _sourceChunk(line),
            previousSourceChunk: _sourceChunk(line),
          );
          final int currentStartMs = _timelineMs(word['startMs']);
          if (currentStartMs > _timelineMs(previousWord['startMs'])) {
            previousWord['endMs'] = currentStartMs;
          } else {
            final int latestEndMs =
                _timelineMs(previousWord['endMs']) > _timelineMs(word['endMs'])
                ? _timelineMs(previousWord['endMs'])
                : _timelineMs(word['endMs']);
            final int boundaryMs =
                _timelineMs(previousWord['startMs']) +
                ((latestEndMs - _timelineMs(previousWord['startMs'])) ~/ 2);
            previousWord['endMs'] = boundaryMs;
            word['startMs'] = boundaryMs;
          }
          report.wordFix += 1;
          repaired = true;
        }
        previousWord = word;
      }
      if (!_hasValidWordTimeline(words)) {
        words = _synthesizeWords(
          english,
          _timelineMs(line['startMs']),
          _timelineMs(line['endMs']),
        );
        report.wordFix += words.length;
        repaired = true;
      }
      if (words.isNotEmpty) {
        line['words'] = words;
        line['startMs'] = _timelineMs(words.first['startMs']);
        line['endMs'] = _timelineMs(words.last['endMs']);
      }
      if (repaired) report.repairCount += 1;
      result.add(line);
    }
    return result;
  }

  List<Map<String, Object?>> _synthesizeWords(
    String english,
    int startMs,
    int endMs,
  ) {
    final List<String> tokens = RegExp("[A-Za-z0-9]+(?:[’'-][A-Za-z0-9]+)?")
        .allMatches(english)
        .map((Match match) => match.group(0)!)
        .toList(growable: false);
    if (tokens.isEmpty || endMs <= startMs) {
      return const <Map<String, Object?>>[];
    }
    final int durationMs = endMs - startMs < tokens.length
        ? tokens.length
        : endMs - startMs;
    return <Map<String, Object?>>[
      for (int index = 0; index < tokens.length; index += 1)
        <String, Object?>{
          'text': tokens[index],
          'startMs': startMs + (durationMs * index ~/ tokens.length),
          'endMs': startMs + (durationMs * (index + 1) ~/ tokens.length),
        },
    ];
  }

  bool _hasValidWordTimeline(List<Map<String, Object?>> words) {
    int previousEndMs = -1;
    for (final Map<String, Object?> word in words) {
      final int startMs = _timelineMs(word['startMs']);
      final int endMs = _timelineMs(word['endMs']);
      if (endMs <= startMs || (previousEndMs >= 0 && startMs < previousEndMs)) {
        return false;
      }
      previousEndMs = endMs;
    }
    return true;
  }

  int _sourceChunk(Map<String, Object?> line) {
    final Object? value = line['_sourceChunk'];
    return value is int ? value : -1;
  }

  Map<String, Object?> _withoutSourceChunk(Map<String, Object?> line) =>
      <String, Object?>{
        for (final MapEntry<String, Object?> entry in line.entries)
          if (entry.key != '_sourceChunk') entry.key: entry.value,
      };

  bool _sameOverlappingLine(
    Map<String, Object?> previous,
    Map<String, Object?> current,
  ) {
    final String previousText = (previous['english'] as String? ?? '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    final String currentText = (current['english'] as String? ?? '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    return previousText.isNotEmpty &&
        previousText == currentText &&
        _timelineMs(current['startMs']) <= _timelineMs(previous['endMs']) &&
        _timelineMs(current['endMs']) >= _timelineMs(previous['startMs']);
  }

  Map<String, Object?> _shiftLine(Map<String, Object?> line, int offsetMs) {
    return <String, Object?>{
      ...line,
      'startMs': _timelineMs(line['startMs']) + offsetMs,
      'endMs': _timelineMs(line['endMs']) + offsetMs,
      'words': (line['words'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(
            (Map<String, dynamic> word) => <String, Object?>{
              ...word,
              'startMs': _timelineMs(word['startMs']) + offsetMs,
              'endMs': _timelineMs(word['endMs']) + offsetMs,
            },
          )
          .toList(growable: false),
    };
  }

  int _timelineMs(Object? value) => value is num ? value.round() : -1;

  Future<String?> _previewText(File chunkFile) async {
    final Object? decoded = jsonDecode(await chunkFile.readAsString());
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final List<dynamic> lines =
        decoded['lines'] as List<dynamic>? ?? const <dynamic>[];
    for (final Object? line in lines.reversed) {
      if (line is Map<String, dynamic>) {
        final String text = (line['english'] as String? ?? '').trim();
        if (text.isNotEmpty) {
          return text;
        }
      }
    }
    return null;
  }

  Future<int> _currentMs(File chunkFile, int fallbackMs) async {
    final Object? decoded = jsonDecode(await chunkFile.readAsString());
    if (decoded is! Map<String, dynamic>) {
      return fallbackMs;
    }
    int currentMs = fallbackMs;
    final List<dynamic> lines =
        decoded['lines'] as List<dynamic>? ?? const <dynamic>[];
    for (final Object? line in lines) {
      if (line is Map<String, dynamic>) {
        final int? endMs = line['endMs'] as int?;
        if (endMs != null && endMs > currentMs) {
          currentMs = endMs;
        }
      }
    }
    return currentMs;
  }

  int _estimatedTotalMs(List<AsrAudioChunk> chunks) {
    if (chunks.isEmpty) {
      return 0;
    }
    if (chunks.length == 1) {
      return chunks.first.offsetMs + 60000;
    }
    final int stepMs =
        chunks.last.offsetMs - chunks[chunks.length - 2].offsetMs;
    return chunks.last.offsetMs + stepMs;
  }

  Future<void> _writeJob({
    required Directory jobDir,
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
    required int totalChunks,
    required String status,
    required String error,
  }) async {
    await jobDir.create(recursive: true);
    await File('${jobDir.path}${Platform.pathSeparator}job.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'version': 1,
        'episodeId': episodeId,
        'videoPath': videoPath,
        'provider': settings.asrProvider,
        'model': settings.asrModel,
        'chunkMs': 58000,
        'totalChunks': totalChunks,
        'status': status,
        'error': error,
      }),
    );
  }

  String _jobKey({
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
  }) {
    final FileStat stat = File(videoPath).statSync();
    final String value =
        '$episodeId|${File(videoPath).absolute.path}|${stat.size}|'
        '${stat.modified.millisecondsSinceEpoch}|${settings.asrProvider}|'
        '${settings.asrBaseUrl}|${settings.asrModel}';
    return sha1.convert(utf8.encode(value)).toString();
  }

  String _translationSignature(LearningSettingsState settings) {
    final String value =
        '${settings.translationProvider}|${settings.translationBaseUrl}|'
        '${settings.translationModel}';
    return sha1.convert(utf8.encode(value)).toString();
  }

  String _translationLineKey(Map<String, dynamic> line, String english) {
    final String value = '${line['startMs']}|${line['endMs']}|$english';
    return sha1.convert(utf8.encode(value)).toString();
  }

  Future<Map<String, String>> _loadTranslations(
    File file,
    String signature,
  ) async {
    if (!file.existsSync()) return <String, String>{};
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['signature'] != signature ||
          decoded['translations'] is! Map<String, dynamic>) {
        return <String, String>{};
      }
      return (decoded['translations'] as Map<String, dynamic>).map(
        (String key, dynamic value) =>
            MapEntry<String, String>(key, value is String ? value : ''),
      )..removeWhere((String _, String value) => value.isEmpty);
    } catch (_) {
      await file.delete();
      return <String, String>{};
    }
  }

  Future<void> _writeJsonAtomically(
    File file,
    Map<String, Object?> value,
  ) async {
    final File part = File('${file.path}.part');
    try {
      await part.writeAsString(jsonEncode(value), flush: true);
      await part.rename(file.path);
    } finally {
      if (part.existsSync()) await part.delete();
    }
  }

  String _errorMessage(Object error) {
    if (error is StateError) return error.message;
    if (error is AsrSubtitleGenerationException) return error.message;
    return error.toString();
  }

  String _safe(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp('_+'), '_');
  }
}
