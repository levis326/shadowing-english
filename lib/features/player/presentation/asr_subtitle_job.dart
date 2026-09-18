import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../../utils/app_paths.dart';
import '../../models/data/local_model_resolver.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/data/desktop_nllb.dart';
import '../../shared/data/local_nllb_translation.dart';
import '../../shared/data/word_lookup_service.dart';
import 'asr_subtitle_cache.dart';
import 'asr_subtitle_service.dart';
import 'desktop_whisper.dart';
import 'player_mock_state.dart';
import 'player_subtitle_loader.dart';
import 'subtitle_text_alignment.dart';
import 'subtitle_text_source.dart';
import 'subtitle_word_alignment.dart';

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
typedef AsrBatchTranslator =
    Future<List<String?>> Function({
      required List<String> sentences,
      required LearningSettingsState settings,
      required String sourceLanguage,
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

class AsrRegeneratedLineResult {
  const AsrRegeneratedLineResult({required this.line, required this.raw});

  final PlayerSubtitleLine line;
  final String raw;
}

String subtitleReferenceSignature(List<PlayerSubtitleLine> lines) {
  final List<PlayerSubtitleLine> usableLines = usableReferenceSubtitles(lines);
  if (usableLines.isEmpty) return '';
  final String value = usableLines
      .map(
        (PlayerSubtitleLine line) =>
            '${line.startMs}|${line.endMs}|${line.english}|${line.chinese}',
      )
      .join('\n');
  return sha1.convert(utf8.encode(value)).toString();
}

String? subtitleGenerationWarning(String raw) {
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final List<String> warnings = <String>[
      for (final String key in <String>['timingWarning', 'translationWarning'])
        if ((decoded[key] as String? ?? '').trim().isNotEmpty)
          (decoded[key] as String).trim(),
    ];
    return warnings.isEmpty ? null : warnings.join('；');
  } catch (_) {
    return null;
  }
}

/// 缓存里记录的生成来源；目前只有 [subtitleTextSourceLabel]
/// （用「字幕文本文件」生成：本地 Whisper 只对齐时间轴，文字来自文件）。
String? subtitleGenerationSource(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded['source'] as String?;
    }
  } catch (_) {
    // 损坏的缓存按“没有来源标记”处理。
  }
  return null;
}

/// 取出缓存里保存的参考字幕快照（生成时用的原字幕或字幕文本）。
List<PlayerSubtitleLine> subtitleReferenceLinesFromCache(String? raw) {
  if (raw == null || raw.isEmpty) {
    return const <PlayerSubtitleLine>[];
  }
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return const <PlayerSubtitleLine>[];
    }
    final Object? referenceLines = decoded['referenceLines'];
    if (referenceLines is! List) {
      return const <PlayerSubtitleLine>[];
    }
    return parseSubtitleLines(
      jsonEncode(<String, Object?>{'version': 1, 'lines': referenceLines}),
    );
  } catch (_) {
    return const <PlayerSubtitleLine>[];
  }
}

/// 只按文字内容计算的签名：字幕文本文件换了内容时，缓存即视为过期。
String subtitleTextSignature(List<PlayerSubtitleLine> lines) {
  final String value = lines
      .map((PlayerSubtitleLine line) => line.english.trim())
      .where((String text) => text.isNotEmpty)
      .join('\n');
  if (value.isEmpty) {
    return '';
  }
  return sha1.convert(utf8.encode(value)).toString();
}

/// 「用字幕文本生成」需要本地 Whisper 只提供时间轴；返回 null 表示可用。
Future<String?> localWhisperTimingUnavailableReason() async {
  final String? model =
      LocalModelResolver.whisperModelPath() ??
      await findDesktopWhisperModel();
  if (model == null) {
    return '需要先下载本地语音识别模型（只用来对齐时间轴，不会上传音频、不产生费用）：请到“设置 → 本地模型（在线下载）”下载 Whisper 模型后重试。';
  }
  final String? server = await findDesktopWhisperServer();
  if (server == null) {
    return '没有找到本地 whisper-server，无法对齐时间轴；请使用官方发布包，或在“设置 → 本地模型”确认模型完整后重试。';
  }
  return null;
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
  bool usedReferenceFallback = false;

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
        'usedReferenceFallback': usedReferenceFallback,
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
    this.translateBatch,
    this.whisperAvailabilityChecker,
  });

  final Future<Directory> Function()? supportDirectory;
  final AsrSubtitleCache cache;
  final AsrSubtitleService service;
  final AsrChunkTranscriber? cloudTranscribeChunk;
  final AsrSentenceTranslator? translateSentence;
  final AsrBatchTranslator? translateBatch;

  /// 测试用：检查「本地 Whisper 是否可用于对齐时间轴」（返回 null 表示可用）。
  final Future<String?> Function()? whisperAvailabilityChecker;

  static const int _repairableOverlapMs = 500;
  static final Set<String> _activeJobs = <String>{};

  Future<AsrRegeneratedLineResult> regenerateLine({
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
    required List<PlayerSubtitleLine> currentLines,
    required int lineIndex,
    String? referenceSignature,
  }) async {
    if (lineIndex < 0 || lineIndex >= currentLines.length) {
      throw const AsrSubtitleGenerationException('当前句不存在，无法重新生成。');
    }
    final File video = File(videoPath);
    if (!video.existsSync()) {
      throw const AsrSubtitleGenerationException('当前视频不可用，无法重新生成这句话。');
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
      chunks = await service.prepareAudioChunks(
        video,
        wavOutput: settings.asrProvider == localWhisperProviderName,
      );
      if (chunks.isEmpty) {
        throw const AsrSubtitleGenerationException('没有提取到可识别的音频，原句已保留。');
      }
      final PlayerSubtitleLine currentLine = currentLines[lineIndex];
      final List<Map<String, Object?>> recognizedLines =
          <Map<String, Object?>>[];
      final _SubtitleQualityReport report = _SubtitleQualityReport(
        settings.asrProvider,
      );

      for (int index = 0; index < chunks.length; index += 1) {
        final int chunkEndMs = index + 1 < chunks.length
            ? chunks[index + 1].offsetMs
            : chunks[index].offsetMs + 58000;
        if (chunks[index].offsetMs >= currentLine.endMs ||
            chunkEndMs <= currentLine.startMs) {
          continue;
        }
        Map<String, Object?>? normalized;
        Object? lastError;
        for (int attempt = 0; attempt < 2; attempt += 1) {
          try {
            final Map<String, Object?> response =
                await _transcribe(
                  chunk: chunks[index],
                  settings: settings,
                ).timeout(
                  const Duration(minutes: 20),
                  onTimeout: () =>
                      throw TimeoutException('AI 重新识别当前句超时，请稍后重试。'),
                );
            normalized = _normalizeChunkTimeline(
              response,
              chunkStartMs: chunks[index].offsetMs,
              chunkEndMs: chunkEndMs,
              sourceChunk: index,
              report: report,
            );
            break;
          } catch (error) {
            lastError = error;
          }
        }
        if (normalized == null) {
          throw AsrSubtitleGenerationException(
            '当前句重新识别失败，原句已保留：${_errorMessage(lastError ?? 'unknown-error')}',
          );
        }
        recognizedLines.addAll(
          (normalized['lines'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(Map<String, Object?>.from),
        );
      }

      final List<PlayerSubtitleWord> words = _wordsForCurrentLine(
        recognizedLines,
        currentLine,
      );
      if (words.isEmpty) {
        throw const AsrSubtitleGenerationException(
          'AI 没有在当前句时间范围内识别到有效英文，原句已保留。',
        );
      }
      final String english = words
          .map((PlayerSubtitleWord word) => word.text)
          .join(' ')
          .trim();
      if (english.isEmpty) {
        throw const AsrSubtitleGenerationException('AI 返回了空字幕，原句已保留。');
      }
      final String chinese = await _translateRegeneratedLine(
        english: english,
        settings: settings,
      );
      final PlayerSubtitleLine regenerated = PlayerSubtitleLine(
        startTime: currentLine.startTime,
        english: english,
        chinese: chinese,
        startMs: currentLine.startMs,
        endMs: currentLine.endMs,
        words: words,
      );
      _validateFinalResult(
        jsonEncode(<String, Object?>{
          'version': 1,
          'lines': <Object?>[_lineToJson(regenerated)],
        }),
      );

      final String? cached = await cache.read(
        episodeId: episodeId,
        videoPath: videoPath,
      );
      final Map<String, dynamic> decoded = cached == null
          ? <String, dynamic>{'version': 1, 'language': 'en'}
          : Map<String, dynamic>.from(
              jsonDecode(cached) as Map<String, dynamic>,
            );
      final List<PlayerSubtitleLine> updatedLines = List<PlayerSubtitleLine>.of(
        currentLines,
      )..[lineIndex] = regenerated;
      decoded['lines'] = updatedLines.map(_lineToJson).toList(growable: false);
      final String raw = const JsonEncoder.withIndent('  ').convert(decoded);
      await cache.write(
        episodeId: episodeId,
        videoPath: videoPath,
        content: raw,
        settings: settings,
        referenceSignature: referenceSignature,
      );
      return AsrRegeneratedLineResult(line: regenerated, raw: raw);
    } finally {
      service.deleteTemporaryAudioChunks(chunks);
      _activeJobs.remove(jobKey);
    }
  }

  Future<String> run({
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
    List<PlayerSubtitleLine> referenceSubtitleLines =
        const <PlayerSubtitleLine>[],
    String? referenceSignatureOverride,
    bool forceRegenerate = false,
    AsrProgressCallback? onProgress,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    final File video = File(videoPath);
    if (!video.existsSync()) {
      throw StateError('missing-video-file');
    }
    final List<PlayerSubtitleLine> usableReferenceLines =
        usableReferenceSubtitles(referenceSubtitleLines);

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
      try {
        chunks = await service.prepareAudioChunks(
          video,
          wavOutput: settings.asrProvider == localWhisperProviderName,
        );
      } catch (_) {
        cancellationToken?.throwIfCancelled();
        if (usableReferenceLines.isEmpty) rethrow;
      }
      cancellationToken?.throwIfCancelled();
      return await _runPrepared(
        episodeId: episodeId,
        videoPath: videoPath,
        settings: settings,
        chunks: chunks,
        referenceSubtitleLines: usableReferenceLines,
        referenceSignature: referenceSignatureOverride?.isNotEmpty ?? false
            ? referenceSignatureOverride!
            : subtitleReferenceSignature(usableReferenceLines),
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
    } finally {
      service.deleteTemporaryAudioChunks(chunks);
      _activeJobs.remove(jobKey);
    }
  }

  /// 用「字幕文本文件」生成 AI 字幕（不需要 AI 语音转文字）。
  ///
  /// 文字以 [textSource] 为准（用户的正确字幕文本），时间轴这样来：
  ///  - [timingRecognition] 不为空时直接用它对齐（“重新生成”复用上次结果）；
  ///  - 文件自带时间轴（`.srt` / `.vtt`）时用文件的时间，完全不碰音频；
  ///  - 纯文本时用本地 Whisper 只做时间轴，识别出来的文字随后被文件文字替换。
  /// 之后按“翻译”设置补齐中文，生成结果与 AI 字幕完全一致（可逐词跟读、
  /// 在“设置 → 管理 AI 字幕”中查看/编辑/导出/重新生成）。
  Future<String> runFromSubtitleText({
    required String episodeId,
    required String videoPath,
    required LearningSettingsState settings,
    required SubtitleTextSource textSource,
    List<PlayerSubtitleLine> timingRecognition = const <PlayerSubtitleLine>[],
    bool forceRegenerate = false,
    AsrProgressCallback? onProgress,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    final File video = File(videoPath);
    if (!video.existsSync()) {
      throw StateError('missing-video-file');
    }
    if (textSource.lines.isEmpty) {
      throw const AsrSubtitleGenerationException('字幕文本文件里没有可用文本。');
    }
    // 只用本地 Whisper 对齐时间轴：不依赖“设置 → ASR 来源”，
    // 因此不会把音频发给云端、也不会产生费用。
    final TranslationProviderPreset whisperPreset =
        asrProviderPresets[localWhisperProviderName]!;
    final LearningSettingsState timingSettings = settings.copyWith(
      asrProvider: localWhisperProviderName,
      asrApiKey: '',
      asrBaseUrl: whisperPreset.baseUrl,
      asrModel: whisperPreset.model,
    );
    final String jobKey = _jobKey(
      episodeId: episodeId,
      videoPath: videoPath,
      settings: timingSettings,
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
          settings: timingSettings,
        );
        if (previousJob.existsSync()) {
          await previousJob.delete(recursive: true);
        }
      }
      List<PlayerSubtitleLine> reference = textSource.lines;
      List<PlayerSubtitleLine>? untimedTextLines;
      if (timingRecognition.isNotEmpty) {
        // 调用方已经有一份带时间轴（最好还带逐词时间）的识别结果，
        // 例如“重新生成”时复用上次结果：不用再跑一次 Whisper。
        reference = assignTimingsFromRecognition(
          reference: textSource.lines,
          recognition: timingRecognition,
        );
        if (reference.isEmpty) {
          throw const AsrSubtitleGenerationException('这份字幕缺少可用于对齐的时间轴。');
        }
      } else if (textSource.hasTimings) {
        // 文件自带时间轴：不需要音频，也不需要 Whisper。
      } else {
        final String? unavailable = await (whisperAvailabilityChecker ??
            localWhisperTimingUnavailableReason)();
        if (unavailable != null) {
          throw AsrSubtitleGenerationException(unavailable);
        }
        chunks = await service.prepareAudioChunks(video, wavOutput: true);
        if (chunks.isEmpty) {
          throw const AsrSubtitleGenerationException(
            '没有从视频里提取到音频，无法用本地 Whisper 对齐字幕时间轴。',
          );
        }
        untimedTextLines = textSource.lines;
      }
      cancellationToken?.throwIfCancelled();
      final String textSignature = subtitleTextSignature(textSource.lines);
      return await _runPrepared(
        episodeId: episodeId,
        videoPath: videoPath,
        settings: timingSettings,
        chunks: chunks,
        referenceSubtitleLines: untimedTextLines == null
            ? reference
            : const <PlayerSubtitleLine>[],
        referenceSignature: textSignature,
        untimedTextLines: untimedTextLines,
        generationSource: subtitleTextSourceLabel,
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
    required List<PlayerSubtitleLine> referenceSubtitleLines,
    required String referenceSignature,
    List<PlayerSubtitleLine>? untimedTextLines,
    String? generationSource,
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
          allowReferenceFallback: referenceSubtitleLines.isNotEmpty,
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

    String raw = await _mergeChunks(chunksDir, chunks.length, report: report);
    _reportProgressPhase(onProgress, chunks.length, '正在整理字幕...');
    // 「字幕文本文件」只有文字、没有时间轴：用本地 Whisper 的识别结果
    // 给每一句套上时间（文字仍以文件为准）。
    List<PlayerSubtitleLine> effectiveReference = referenceSubtitleLines;
    if (untimedTextLines != null && untimedTextLines.isNotEmpty) {
      effectiveReference = assignTimingsFromRecognition(
        reference: untimedTextLines,
        recognition: parseSubtitleLines(raw),
        fallbackEndMs: totalMs,
      );
      if (effectiveReference.isEmpty) {
        throw const AsrSubtitleGenerationException(
          '本地 Whisper 没有识别到可用语音，无法为字幕文本对齐时间轴；请确认视频有声音，或改用 AI 语音识别。',
        );
      }
    }
    if (effectiveReference.isNotEmpty) {
      final bool hasRecognizedWords = parseSubtitleLines(
        raw,
      ).any((PlayerSubtitleLine line) => line.words.isNotEmpty);
      raw = _calibrateWithReference(raw, effectiveReference);
      if (report.usedReferenceFallback || !hasRecognizedWords) {
        raw = _addTimingWarning(raw);
      }
      if (generationSource != null) {
        raw = _withGenerationSource(raw, generationSource);
      }
    }
    // 按句号、问号、分号等句子标点拆分成独立字幕行，避免一句字幕过长；
    // 拆分在翻译之前进行，每个句子单独翻译、单独成行。
    raw = _splitLinesAtSentencePunctuation(raw);
    late final String completedRaw;
    try {
      final String translatedRaw = await _addChineseTranslations(
        raw: raw,
        settings: settings,
        jobDir: jobDir,
        cancellationToken: cancellationToken,
        onProgress: (int done, int total) {
          _reportProgressPhase(
            onProgress,
            chunks.length,
            '正在翻译中文字幕 $done/$total',
          );
        },
      );
      _reportProgressPhase(onProgress, chunks.length, '正在校准词级时间轴...');
      completedRaw = _normalizeFinalLines(
        _repairFinalWordTimelines(translatedRaw, report: report),
        allowLineOverlap:
            referenceSubtitleLines.isNotEmpty ||
            (untimedTextLines?.isNotEmpty ?? false),
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
      _validateFinalResult(
        completedRaw,
        allowLineOverlap:
            referenceSubtitleLines.isNotEmpty ||
            (untimedTextLines?.isNotEmpty ?? false),
      );
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
      referenceSignature: referenceSignature.isEmpty
          ? null
          : referenceSignature,
      // 生成完成后程序会把结果保存成 `.en.srt` / `.zh.srt` 并挂到剧集上，
      // 重新打开时参考字幕就变成了这份生成结果；记下它的签名，
      // 这样重启后缓存不会被当成“参考已变更”而失效（否则双语字幕会消失）。
      generatedSignature: subtitleReferenceSignature(
        parseSubtitleLines(completedRaw),
      ),
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

  String _withGenerationSource(String raw, String source) {
    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    decoded['source'] = source;
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  String _calibrateWithReference(
    String raw,
    List<PlayerSubtitleLine> referenceSubtitleLines,
  ) {
    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    final SubtitleWordAlignmentResult aligned = alignReferenceSubtitles(
      reference: referenceSubtitleLines,
      recognition: parseSubtitleLines(raw),
    );
    decoded['referenceLines'] = usableReferenceSubtitles(
      referenceSubtitleLines,
    ).map(_lineToJson).toList(growable: false);
    decoded['lines'] = aligned.lines
        .map(
          (PlayerSubtitleLine line) => <String, Object?>{
            'startMs': line.startMs,
            'endMs': line.endMs,
            'english': line.english,
            'chinese': line.chinese,
            'words': line.words
                .map(
                  (PlayerSubtitleWord word) => <String, Object?>{
                    'text': word.text,
                    'startMs': word.startMs,
                    'endMs': word.endMs,
                    if (word.confidence != null) 'confidence': word.confidence,
                  },
                )
                .toList(growable: false),
          },
        )
        .toList(growable: false);
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  String _addTimingWarning(String raw) {
    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    decoded['timingWarning'] = '已使用原字幕保证正文完整；部分单词时间为本地估算，联网后重新生成可提高逐词同步精度。';
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  Future<String> _addChineseTranslations({
    required String raw,
    required LearningSettingsState settings,
    required Directory jobDir,
    AsrSubtitleCancellationToken? cancellationToken,
    void Function(int done, int total)? onProgress,
  }) async {
    if (!settings.generateBilingualAsrSubtitles) {
      return raw;
    }

    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    final List<dynamic> lines =
        decoded['lines'] as List<dynamic>? ?? const <dynamic>[];
    // “需要翻译”= 中文为空，或中文与英文完全相同（部分多模态 ASR 会把英文
    // 原样填进 chinese 字段，那种情况下必须真正翻译一次）。
    final List<Map<String, dynamic>> pendingLines = lines
        .whereType<Map<String, dynamic>>()
        .where(_lineNeedsTranslation)
        .toList(growable: false);
    final bool needsTranslation = pendingLines.isNotEmpty;
    if (!needsTranslation) return raw;
    final String? configurationError = await _bilingualConfigurationError(
      settings,
    );
    if (configurationError != null) {
      decoded['translationWarning'] = configurationError;
      return const JsonEncoder.withIndent('  ').convert(decoded);
    }
    if (settings.translationProvider == localNllbTranslationProviderName) {
      return _addChineseTranslationsWithNllb(
        decoded: decoded,
        pendingLines: pendingLines,
        settings: settings,
        jobDir: jobDir,
        cancellationToken: cancellationToken,
        onProgress: onProgress,
      );
    }
    final File checkpoint = File(
      '${jobDir.path}${Platform.pathSeparator}translations.json',
    );
    final String signature = _translationSignature(settings);
    final Map<String, String> translations = await _loadTranslations(
      checkpoint,
      signature,
    );
    int done = 0;
    for (final dynamic line in lines) {
      if (line is! Map<String, dynamic>) {
        continue;
      }
      if (!_lineNeedsTranslation(line)) {
        continue;
      }
      final String english = (line['english'] as String? ?? '').trim();
      cancellationToken?.throwIfCancelled();
      final String key = _translationLineKey(line, english);
      final String? cached = translations[key];
      String? chinese = cached;
      if (chinese == null) {
        try {
          chinese =
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
        } catch (error) {
          cancellationToken?.throwIfCancelled();
          decoded['translationWarning'] =
              '外文字幕已生成，但中文翻译失败：${_translationErrorReason(error)}'
              '；可在“设置 → 翻译”中检查后重新生成。';
          break;
        }
      }
      if (chinese == null || chinese.trim().isEmpty) {
        decoded['translationWarning'] =
            '外文字幕已生成，但中文翻译返回了空结果；请在“设置 → 翻译”中检查服务后重新生成。';
        break;
      }
      final String sanitized = _sanitizeTranslation(chinese);
      if (sanitized.isEmpty) {
        // 翻译结果只剩乱码占位符时，该行保留英文（双语模式下不显示中文行）。
        done += 1;
        onProgress?.call(done, pendingLines.length);
        continue;
      }
      line['chinese'] = sanitized;
      if (cached == null) {
        translations[key] = sanitized;
        await _writeJsonAtomically(checkpoint, <String, Object?>{
          'version': 1,
          'signature': signature,
          'translations': translations,
        });
      }
      done += 1;
      onProgress?.call(done, pendingLines.length);
      cancellationToken?.throwIfCancelled();
    }
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  Future<String> _addChineseTranslationsWithNllb({
    required Map<String, dynamic> decoded,
    required List<Map<String, dynamic>> pendingLines,
    required LearningSettingsState settings,
    required Directory jobDir,
    AsrSubtitleCancellationToken? cancellationToken,
    void Function(int done, int total)? onProgress,
  }) async {
    final File checkpoint = File(
      '${jobDir.path}${Platform.pathSeparator}translations.json',
    );
    final String whisperLanguage = (decoded['language'] as String? ?? '')
        .trim();
    final String sourceLanguage = nllbSourceLanguageForWhisper(whisperLanguage);
    final String signature =
        '${_translationSignature(settings)}|$sourceLanguage';
    final Map<String, String> translations = await _loadTranslations(
      checkpoint,
      signature,
    );

    final List<Map<String, dynamic>> toTranslate = <Map<String, dynamic>>[];
    final List<String> englishBatch = <String>[];
    for (final Map<String, dynamic> line in pendingLines) {
      final String english = (line['english'] as String? ?? '').trim();
      final String key = _translationLineKey(line, english);
      final String? cached = translations[key];
      if (cached != null && cached.trim().isNotEmpty) {
        line['chinese'] = cached.trim();
        continue;
      }
      toTranslate.add(line);
      englishBatch.add(english);
    }

    int done = pendingLines.length - toTranslate.length;
    onProgress?.call(done, pendingLines.length);

    if (toTranslate.isNotEmpty) {
      cancellationToken?.throwIfCancelled();
      final List<String?> results;
      try {
        results =
            await (translateBatch != null
                    ? translateBatch!(
                        sentences: englishBatch,
                        settings: settings,
                        sourceLanguage: sourceLanguage,
                      )
                    : localNllbTranslationService.translateBatch(
                        englishBatch,
                        sourceLanguage: sourceLanguage,
                      ))
                .timeout(
                  const Duration(minutes: 6),
                  onTimeout: () => throw TimeoutException('本地 NLLB 翻译超时，请重试。'),
                );
      } catch (error) {
        cancellationToken?.throwIfCancelled();
        decoded['translationWarning'] =
            '外文字幕已生成，但本地中文翻译失败：'
            '${_translationErrorReason(error)}';
        return const JsonEncoder.withIndent('  ').convert(decoded);
      }

      bool incomplete = false;
      for (int i = 0; i < toTranslate.length; i += 1) {
        cancellationToken?.throwIfCancelled();
        final Map<String, dynamic> line = toTranslate[i];
        final String english = englishBatch[i];
        final String key = _translationLineKey(line, english);
        final String? chinese = results.length > i ? results[i] : null;
        final String sanitized = _sanitizeTranslation(chinese ?? '');
        if (sanitized.isEmpty) {
          incomplete = true;
          continue;
        }
        line['chinese'] = sanitized;
        translations[key] = sanitized;
        done += 1;
        onProgress?.call(done, pendingLines.length);
      }
      await _writeJsonAtomically(checkpoint, <String, Object?>{
        'version': 1,
        'signature': signature,
        'translations': translations,
      });
      if (incomplete) {
        decoded['translationWarning'] =
            '外文字幕已生成，但部分句子的中文翻译为空；请检查“设置 → 翻译”后重新生成。';
      }
    }
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  /// 把翻译异常转换成能直接展示给用户的原因说明。
  String _translationErrorReason(Object error) {
    String message = error.toString();
    for (final String prefix in <String>[
      'Bad state: ',
      'Exception: ',
      'DioException [unknown]: ',
    ]) {
      if (message.startsWith(prefix)) {
        message = message.substring(prefix.length);
      }
    }
    message = message.trim();
    if (message.isEmpty) {
      return '未知原因';
    }
    return message;
  }

  /// 清理翻译结果中的乱码占位符：本地模型对无法翻译的词会输出
  /// `⁇`（U+2047，NLLB 词表的未知词符号）或 `�`（U+FFFD），
  /// 移除它们并收紧标点前的多余空格。
  String _sanitizeTranslation(String text) {
    String cleaned = text.replaceAll('\u2047', '').replaceAll('\uFFFD', '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\s+([,.;:!?，。；：！？、])'),
      (Match match) => match.group(1)!,
    );
    return cleaned;
  }

  bool _lineNeedsTranslation(Map<String, dynamic> line) {
    final String english = (line['english'] as String? ?? '').trim();
    if (english.isEmpty) {
      return false;
    }
    final String chinese = (line['chinese'] as String? ?? '').trim();
    return chinese.isEmpty || chinese == english;
  }

  Future<String?> _bilingualConfigurationError(
    LearningSettingsState settings,
  ) async {
    if (!settings.generateBilingualAsrSubtitles ||
        translateSentence != null ||
        translateBatch != null) {
      return null;
    }
    if (settings.translationProvider == localNllbTranslationProviderName) {
      // 本地 NLLB 需要用户先在“设置 → 本地模型”里下载翻译模型，
      // 提前给出可操作的提示，避免生成完外文字幕才发现没有中文。
      final String? modelDir =
          LocalModelResolver.translationModelDir() ??
          await findDesktopNllbModelDir();
      final String? tokenizer =
          LocalModelResolver.translationTokenizerPath() ??
          await findDesktopNllbTokenizer();
      if (modelDir == null || tokenizer == null) {
        return '中文翻译未生成：没有找到本地翻译模型。请到“设置 → 本地模型（在线下载）”下载 NLLB 翻译模型；如果已经下载过，请在同一个页面确认模型是否完整，然后重新生成 AI 字幕。';
      }
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
        ? await AppPaths.dataDirectory()
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

  List<PlayerSubtitleWord> _wordsForCurrentLine(
    List<Map<String, Object?>> recognizedLines,
    PlayerSubtitleLine currentLine,
  ) {
    final String raw = jsonEncode(<String, Object?>{
      'version': 1,
      'lines': recognizedLines,
    });
    final List<PlayerSubtitleWord> candidates =
        parseSubtitleLines(raw)
            .expand((PlayerSubtitleLine line) => line.words)
            .where((PlayerSubtitleWord word) {
              final int midpoint =
                  word.startMs + ((word.endMs - word.startMs) ~/ 2);
              return midpoint >= currentLine.startMs &&
                  midpoint <= currentLine.endMs;
            })
            .toList(growable: false)
          ..sort(
            (PlayerSubtitleWord a, PlayerSubtitleWord b) =>
                a.startMs.compareTo(b.startMs),
          );
    final List<PlayerSubtitleWord> result = <PlayerSubtitleWord>[];
    for (final PlayerSubtitleWord word in candidates) {
      final int startMs = word.startMs.clamp(
        currentLine.startMs,
        currentLine.endMs,
      );
      final int endMs = word.endMs.clamp(
        currentLine.startMs,
        currentLine.endMs,
      );
      final int safeStartMs = result.isEmpty
          ? startMs
          : startMs < result.last.endMs
          ? result.last.endMs
          : startMs;
      if (endMs <= safeStartMs) continue;
      result.add(
        PlayerSubtitleWord(
          text: word.text,
          startMs: safeStartMs,
          endMs: endMs,
          confidence: word.confidence,
        ),
      );
    }
    return result;
  }

  Future<String> _translateRegeneratedLine({
    required String english,
    required LearningSettingsState settings,
  }) async {
    if (!settings.generateBilingualAsrSubtitles) return '';
    final String? configurationError = await _bilingualConfigurationError(
      settings,
    );
    if (configurationError != null) {
      throw AsrSubtitleGenerationException('$configurationError 原句已保留。');
    }
    Object? lastError;
    for (int attempt = 0; attempt < 2; attempt += 1) {
      try {
        final String? translated =
            await (translateSentence ??
                    const WordLookupService().translateSentence)(
                  sentence: english,
                  settings: settings,
                )
                .timeout(const Duration(seconds: 45));
        if (translated != null && translated.trim().isNotEmpty) {
          return translated.trim();
        }
        lastError = StateError('empty-translation');
      } catch (error) {
        lastError = error;
      }
    }
    throw AsrSubtitleGenerationException(
      '当前句英文已识别，但中文翻译失败，原句已保留：${_errorMessage(lastError ?? 'unknown-error')}',
    );
  }

  Map<String, Object?> _lineToJson(PlayerSubtitleLine line) {
    return <String, Object?>{
      'startMs': line.startMs,
      'endMs': line.endMs,
      'english': line.english,
      'chinese': line.chinese,
      'words': line.words
          .map(
            (PlayerSubtitleWord word) => <String, Object?>{
              'text': word.text,
              'startMs': word.startMs,
              'endMs': word.endMs,
              if (word.confidence != null) 'confidence': word.confidence,
            },
          )
          .toList(growable: false),
    };
  }

  Future<void> _loadOrTranscribeValidChunk({
    required File chunkFile,
    required AsrAudioChunk chunk,
    required int chunkEndMs,
    required LearningSettingsState settings,
    required int sourceChunk,
    required _SubtitleQualityReport report,
    required bool allowReferenceFallback,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    for (int attempt = 0; attempt < 2; attempt += 1) {
      try {
        cancellationToken?.throwIfCancelled();
        late final Map<String, Object?> chunkJson;
        if (attempt == 0 && chunkFile.existsSync()) {
          final Object? decoded = jsonDecode(await chunkFile.readAsString());
          if (decoded is! Map<String, dynamic>) {
            throw StateError('invalid-asr-chunk');
          }
          chunkJson = Map<String, Object?>.from(decoded);
        } else {
          chunkJson = await _transcribe(chunk: chunk, settings: settings)
              .timeout(
                const Duration(minutes: 20),
                onTimeout: () => throw TimeoutException('AI 字幕生成超时，请重试或换更小模型。'),
              );
        }
        final Map<String, Object?> normalized = _normalizeChunkTimeline(
          chunkJson,
          chunkStartMs: chunk.offsetMs,
          chunkEndMs: chunkEndMs,
          sourceChunk: sourceChunk,
          report: report,
        );
        // 逐段也要清理一遍：只剩标点的行、字数与正文不一致的词级数据
        // 都不该让整段（进而整段视频）失败。但如果这一段的返回整体不可用
        // （有行却一行都留不下），仍然算无效响应，交给上面的重试逻辑处理。
        final Map<String, Object?> cleaned = Map<String, Object?>.from(
          jsonDecode(
                _normalizeFinalLines(
                  jsonEncode(normalized),
                  allowLineOverlap: false,
                  requireNonEmpty: false,
                ),
              )
              as Map<String, dynamic>,
        );
        final Object? rawLines = normalized['lines'];
        final int rawLineCount = rawLines is List<dynamic> ? rawLines.length : 0;
        final Object? cleanedLines = cleaned['lines'];
        final int cleanedLineCount = cleanedLines is List<dynamic>
            ? cleanedLines.length
            : 0;
        if (rawLineCount > 0 && cleanedLineCount == 0) {
          throw StateError('字幕检查失败：没有识别到有效字幕。');
        }
        await chunkFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert(cleaned),
        );
        return;
      } catch (error) {
        cancellationToken?.throwIfCancelled();
        if (chunkFile.existsSync()) {
          await chunkFile.delete();
        }
        if (attempt == 1) {
          final bool skipChunk =
              allowReferenceFallback ||
              settings.asrProvider == localWhisperProviderName;
          if (skipChunk) {
            report
              ..repairCount += 1
              ..anomalies.add(<String, Object?>{
                'kind': allowReferenceFallback
                    ? 'referenceFallback'
                    : 'localSkip',
                'sourceChunk': sourceChunk,
                'errorType': error.runtimeType.toString(),
              });
            if (allowReferenceFallback) {
              report.usedReferenceFallback = true;
            }
            await chunkFile.writeAsString(
              const JsonEncoder.withIndent(' ').convert(<String, Object?>{
                'version': 1,
                'language': 'en',
                'lines': const <Object?>[],
              }),
            );
            return;
          }
          throw StateError(
            '第 ${sourceChunk + 1} 段处理失败：${_errorMessage(error)}',
          );
        }
      }
    }
  }

  void _validateFinalResult(String raw, {bool allowLineOverlap = false}) {
    final List<PlayerSubtitleLine> lines = parseSubtitleLines(raw);
    if (lines.isEmpty) {
      throw StateError('字幕检查失败：没有识别到有效字幕。');
    }

    int previousEndMs = -1;
    for (int index = 0; index < lines.length; index += 1) {
      final PlayerSubtitleLine line = lines[index];
      final String location = '第 ${index + 1} 句';
      final String snippet = _lineSnippet(line.english);
      if (line.english.trim().isEmpty) {
        throw StateError('字幕检查失败：$location 存在空字幕。');
      }
      if (line.endMs <= line.startMs) {
        throw StateError('字幕检查失败：$location$snippet 存在无效时间轴。');
      }
      if (line.words.isEmpty) {
        throw StateError(
          '字幕检查失败：$location$snippet 未返回词级时间戳，无法精准跟读单词。',
        );
      }
      final int expectedWordCount = _wordCount(line.english);
      final int timedWordCount = line.words.fold<int>(
        0,
        (int count, PlayerSubtitleWord word) => count + _wordCount(word.text),
      );
      if (expectedWordCount > 0 && timedWordCount < expectedWordCount) {
        throw StateError(
          '字幕检查失败：$location$snippet 不是每个英文单词都有词级时间戳。',
        );
      }
      if (_comparableText(line.english) !=
          _comparableText(
            line.words.map((PlayerSubtitleWord word) => word.text).join(' '),
          )) {
        throw StateError(
          '字幕检查失败：$location$snippet 的正文与词级时间戳文本不一致。',
        );
      }
      int previousWordEndMs = -1;
      for (final PlayerSubtitleWord word in line.words) {
        if (previousWordEndMs >= 0 && word.startMs < previousWordEndMs) {
          throw StateError('字幕检查失败：$location 的单词时间轴乱序或重叠。');
        }
        previousWordEndMs = word.endMs;
      }
      if (!allowLineOverlap &&
          previousEndMs >= 0 &&
          line.startMs < previousEndMs - 250) {
        throw StateError('字幕检查失败：$location 时间轴乱序或重叠过多。');
      }
      previousEndMs = line.endMs;
    }
  }

  /// 最后一道保险：让每一行都满足 [ _validateFinalResult ] 的要求。
  ///
  /// 真实数据里总会有“只剩标点”的行、时间戳类型不对的词条、字数与正文不一致
  /// 的词级数据（服务商差异、字幕文件写法各异）。这些细节不该让整段视频的
  /// 字幕生成失败：能修的修（按正文重新合成逐词时间），修不好的行直接丢掉。
  String _normalizeFinalLines(
    String raw, {
    required bool allowLineOverlap,
    bool requireNonEmpty = true,
  }) {
    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    final List<dynamic> lines =
        decoded['lines'] as List<dynamic>? ?? const <dynamic>[];
    final List<Map<String, Object?>> normalized = <Map<String, Object?>>[];
    int previousEndMs = -1;
    for (final Object? item in lines) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final String english = (item['english'] as String? ?? '').trim();
      int startMs = _timelineMs(item['startMs']);
      int endMs = _timelineMs(item['endMs']);
      // 没有可跟读文字的（纯标点）和无效时间轴的行直接丢掉。
      if (english.isEmpty || _wordCount(english) == 0) {
        continue;
      }
      if (endMs <= startMs) {
        continue;
      }
      if (!allowLineOverlap &&
          previousEndMs >= 0 &&
          startMs < previousEndMs - 250) {
        startMs = previousEndMs;
        if (endMs <= startMs) {
          endMs = startMs + 1;
        }
      }
      List<Map<String, Object?>> words = _sanitizedWords(
        item: item,
        startMs: startMs,
        endMs: endMs,
      );
      if (!_wordsCoverText(english: english, words: words)) {
        words = _synthesizeWords(english, startMs, endMs);
      }
      if (words.isEmpty) {
        continue;
      }
      normalized.add(<String, Object?>{
        ...item,
        'english': english,
        'startMs': startMs,
        'endMs': endMs,
        'words': words,
      });
      previousEndMs = endMs;
    }
    if (normalized.isEmpty && requireNonEmpty) {
      throw StateError('字幕检查失败：没有识别到有效字幕。');
    }
    decoded['lines'] = normalized;
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  /// 只保留解析时会保留的词条（文本非空、时间戳为有效数字且在行内、不乱序）。
  List<Map<String, Object?>> _sanitizedWords({
    required Map<String, dynamic> item,
    required int startMs,
    required int endMs,
  }) {
    final List<Map<String, Object?>> words = <Map<String, Object?>>[];
    int previousWordEndMs = -1;
    for (final Object? entry
        in item['words'] as List<dynamic>? ?? const <dynamic>[]) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      final String text = (entry['text'] as String? ?? '').trim();
      final Object? rawStart = entry['startMs'];
      final Object? rawEnd = entry['endMs'];
      if (text.isEmpty || rawStart is! num || rawEnd is! num) {
        continue;
      }
      final int wordStartMs = rawStart.round();
      final int wordEndMs = rawEnd.round();
      if (wordEndMs <= wordStartMs ||
          wordStartMs < startMs ||
          wordEndMs > endMs ||
          (previousWordEndMs >= 0 && wordStartMs < previousWordEndMs)) {
        continue;
      }
      words.add(<String, Object?>{
        ...entry,
        'text': text,
        'startMs': wordStartMs,
        'endMs': wordEndMs,
      });
      previousWordEndMs = wordEndMs;
    }
    return words;
  }

  /// 逐词时间戳是否覆盖了整行正文。
  bool _wordsCoverText({
    required String english,
    required List<Map<String, Object?>> words,
  }) {
    if (words.isEmpty) {
      return false;
    }
    final int expectedWordCount = _wordCount(english);
    final int timedWordCount = words.fold<int>(
      0,
      (int count, Map<String, Object?> word) =>
          count + _wordCount(word['text'] as String? ?? ''),
    );
    if (timedWordCount < expectedWordCount) {
      return false;
    }
    return _comparableText(english) ==
        _comparableText(
          words.map((Map<String, Object?> word) => word['text'] ?? '').join(' '),
        );
  }

  String _repairFinalWordTimelines(
    String raw, {
    required _SubtitleQualityReport report,
  }) {
    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    final List<dynamic> lines =
        decoded['lines'] as List<dynamic>? ?? const <dynamic>[];
    for (final Object? item in lines) {
      if (item is! Map<String, dynamic>) continue;
      final String english = (item['english'] as String? ?? '').trim();
      final int startMs = _timelineMs(item['startMs']);
      final int endMs = _timelineMs(item['endMs']);
      if (english.isEmpty || endMs <= startMs) continue;
      final List<Map<String, Object?>> words =
          (item['words'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(Map<String, Object?>.from)
              .toList(growable: false);
      final int expectedWordCount = _wordCount(english);
      final int timedWordCount = words.fold<int>(
        0,
        (int count, Map<String, Object?> word) =>
            count + _wordCount(word['text'] as String? ?? ''),
      );
      final bool hasValidCoverage =
          words.isNotEmpty &&
          timedWordCount >= expectedWordCount &&
          _comparableText(english) ==
              _comparableText(
                words
                    .map((Map<String, Object?> word) => word['text'] ?? '')
                    .join(' '),
              ) &&
          _hasValidWordTimeline(words) &&
          words.every(
            (Map<String, Object?> word) =>
                _timelineMs(word['startMs']) >= startMs &&
                _timelineMs(word['endMs']) <= endMs,
          );
      if (hasValidCoverage) continue;
      final List<Map<String, Object?>> repaired = _synthesizeWords(
        english,
        startMs,
        endMs,
      );
      if (repaired.isEmpty) continue;
      item['words'] = repaired;
      report
        ..wordFix += repaired.length
        ..repairCount += 1;
    }
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  /// 报错时带上这一句的开头，方便定位是哪个视频/哪一句的数据有问题。
  String _lineSnippet(String english) {
    final String trimmed = english.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final String short = trimmed.length > 24
        ? '${trimmed.substring(0, 24)}…'
        : trimmed;
    return '「$short」';
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
    String detectedLanguage = '';
    for (int index = 0; index < totalChunks; index += 1) {
      final File chunkFile = File(
        '${chunksDir.path}${Platform.pathSeparator}${index.toString().padLeft(5, '0')}.json',
      );
      final Object? decoded = jsonDecode(await chunkFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw StateError('invalid-asr-chunk');
      }
      final String chunkLanguage = (decoded['language'] as String? ?? '')
          .trim();
      if (chunkLanguage.isNotEmpty && detectedLanguage.isEmpty) {
        detectedLanguage = chunkLanguage;
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
    final List<Map<String, Object?>> timelineNormalized = _normalizeTimeline(
      boundaryNormalized,
      report: report,
    );
    final List<Map<String, Object?>> sentenceLines = _mergeIntoEnglishSentences(
      timelineNormalized,
    );
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'version': 1,
      'language': detectedLanguage,
      'lines': sentenceLines.map(_withoutSourceChunk).toList(growable: false),
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

  /// Merges adjacent whisper fragments into whole English sentences, so each
  /// subtitle cue corresponds to one sentence. Fragments that do not end with
  /// sentence punctuation (`.!?;；。！？`) are joined with the following
  /// fragment; fragments ending with any of those punctuation marks start a
  /// new subtitle line.
  List<Map<String, Object?>> _mergeIntoEnglishSentences(
    List<Map<String, Object?>> lines,
  ) {
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    final List<Map<String, Object?>> buffer = <Map<String, Object?>>[];
    for (final Map<String, Object?> line in lines) {
      buffer.add(line);
      if (_endsSentence((line['english'] as String? ?? '').trim())) {
        result.add(_mergeLineBuffer(buffer));
        buffer.clear();
      }
    }
    if (buffer.isNotEmpty) {
      result.add(_mergeLineBuffer(buffer));
    }
    return result;
  }

  bool _endsSentence(String english) {
    if (english.isEmpty) {
      return false;
    }
    final String last = english.substring(english.length - 1);
    return last == '.' ||
        last == '!' ||
        last == '?' ||
        last == ';' ||
        last == '。' ||
        last == '！' ||
        last == '？' ||
        last == '；';
  }

  /// 分句标点集合：见到这些符号就拆成新的字幕行（含逗号、分号、冒号）。
  bool _endsClause(String text) {
    if (text.isEmpty) {
      return false;
    }
    final String last = text.substring(text.length - 1);
    return _endsSentence(text) ||
        last == ',' ||
        last == '，' ||
        last == ':' ||
        last == '：';
  }

  /// 在 [words] 中从 [fromIndex] 起查找与 [token] 对应的词条下标，
  /// 用于词条数量与 token 数量不一致时的对齐（按可比较文本匹配，
  /// 允许“词条是 token 的前缀/子串”这类拆分差异）。
  int _wordIndexForToken(
    String token,
    List<Map<String, dynamic>> words,
    int fromIndex,
  ) {
    final int safeFrom = fromIndex.clamp(0, words.length - 1);
    final String target = _comparableText(token);
    if (target.isEmpty) {
      // 纯标点 token 不参与匹配，也不能占用某个词条（否则后面的单词会
      // 因为“下标已被用过”而丢掉时间戳）。
      return -1;
    }
    for (int index = safeFrom; index < words.length; index += 1) {
      final String candidate = _comparableText(
        words[index]['text'] as String? ?? '',
      );
      if (candidate.isEmpty) {
        // 标点等不含字母数字的词条不参与匹配（否则空前缀会匹配任何 token）。
        continue;
      }
      if (candidate == target ||
          candidate.startsWith(target) ||
          target.startsWith(candidate)) {
        return index;
      }
    }
    return safeFrom;
  }

  /// Splits every subtitle line at clause punctuation (`, . ! ? ; :` and the
  /// full-width equivalents) so one cue never contains several sentences.
  /// Boundaries are derived from the line's own English text — not from the
  /// word entries — because reference-aligned words carry no punctuation.
  String _splitLinesAtSentencePunctuation(String raw) {
    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    final List<dynamic> lines =
        decoded['lines'] as List<dynamic>? ?? const <dynamic>[];
    final List<Map<String, Object?>> splitLines = <Map<String, Object?>>[];
    for (final dynamic line in lines) {
      if (line is! Map<String, dynamic>) {
        continue;
      }
      splitLines.addAll(_splitLineAtSentencePunctuation(line));
    }
    decoded['lines'] = splitLines;
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  List<Map<String, Object?>> _splitLineAtSentencePunctuation(
    Map<String, dynamic> line,
  ) {
    final String english = (line['english'] as String? ?? '').trim();
    final List<String> tokens = english
        .split(RegExp(r'\s+'))
        .where((String token) => token.isNotEmpty)
        .toList(growable: false);
    if (tokens.length < 2) {
      return <Map<String, Object?>>[Map<String, Object?>.from(line)];
    }

    // 找出所有“断句点”：该 token 以分句标点结尾，其后另起一行。
    final List<int> boundaries = <int>[];
    for (int index = 0; index < tokens.length - 1; index += 1) {
      if (_endsClause(tokens[index])) {
        boundaries.add(index);
      }
    }
    if (boundaries.isEmpty) {
      return <Map<String, Object?>>[Map<String, Object?>.from(line)];
    }

    final List<List<int>> ranges = <List<int>>[];
    int start = 0;
    for (final int boundary in boundaries) {
      ranges.add(
        List<int>.generate(boundary - start + 1, (int i) => start + i),
      );
      start = boundary + 1;
    }
    ranges.add(List<int>.generate(tokens.length - start, (int i) => start + i));

    final List<Map<String, dynamic>> words =
        (line['words'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
    // token 序号 -> 词条下标。数量一致时按位置一一对应（常见情况，
    // 参考字幕对齐的词不含标点也能正确分组）；数量不一致时（例如服务商
    // 把标点单独算一个词）按文本匹配推进游标，避免时间戳整体错位。
    final List<int> tokenToWord = <int>[];
    if (words.length == tokens.length) {
      for (int index = 0; index < tokens.length; index += 1) {
        tokenToWord.add(index);
      }
    } else if (words.isNotEmpty) {
      int cursor = 0;
      for (final String token in tokens) {
        final int match = _wordIndexForToken(token, words, cursor);
        tokenToWord.add(match);
        if (match >= 0 && match + 1 < words.length) {
          cursor = match + 1;
        }
      }
    }
    final int lineStartMs = (line['startMs'] as num?)?.round() ?? 0;
    final int lineEndMs = (line['endMs'] as num?)?.round() ?? lineStartMs;

    final List<Map<String, Object?>> subLines = <Map<String, Object?>>[];
    int previousEndMs = -1;
    for (final List<int> range in ranges) {
      final String subEnglish = range
          .map((int index) => tokens[index])
          .join(' ');
      // 只剩标点的片段（例如单独的 ","）没法跟读，丢掉它，
      // 这段时间会被相邻子行覆盖（下面会把首尾接起来）。
      if (_wordCount(subEnglish) == 0) {
        continue;
      }
      final List<Map<String, dynamic>> groupWords = <Map<String, dynamic>>[];
      if (tokenToWord.isNotEmpty) {
        final Set<int> usedWordIndexes = <int>{};
        for (final int tokenIndex in range) {
          final int wordIndex = tokenToWord[tokenIndex];
          if (wordIndex < 0 || wordIndex >= words.length) {
            continue;
          }
          if (usedWordIndexes.add(wordIndex)) {
            groupWords.add(words[wordIndex]);
          }
        }
      }
      int startMs;
      int endMs;
      if (groupWords.isNotEmpty) {
        startMs = (groupWords.first['startMs'] as num?)?.round() ?? lineStartMs;
        endMs = (groupWords.last['endMs'] as num?)?.round() ?? lineEndMs;
      } else {
        // 没有词级时间戳时按 token 占比切分整行时间。
        final double span = (lineEndMs - lineStartMs).toDouble();
        startMs = lineStartMs + (range.first / tokens.length * span).round();
        endMs = lineStartMs + ((range.last + 1) / tokens.length * span).round();
      }
      // 相邻子行不允许时间轴重叠（否则校验失败）。
      if (previousEndMs > 0 && startMs < previousEndMs) {
        startMs = previousEndMs;
      }
      if (endMs <= startMs) {
        endMs = startMs + 1;
      }
      previousEndMs = endMs;
      subLines.add(<String, Object?>{
        'startMs': startMs,
        'endMs': endMs,
        'english': subEnglish,
        'chinese': '', // 拆分后每句单独翻译
        'words': groupWords,
      });
    }

    // 让拆出来的子行时间轴首尾相接：每一行都延伸到下一行的起点，
    // 第一行从原行起点开始、最后一行覆盖到原行终点。这样点击某行时
    // 该行的完整发音（包括词尾被低估的音节）不会被切到下一行去播放。
    if (subLines.isNotEmpty) {
      subLines.first['startMs'] = lineStartMs;
      for (int index = 0; index < subLines.length - 1; index += 1) {
        final int nextStartMs = _timelineMs(subLines[index + 1]['startMs']);
        final int currentStartMs = _timelineMs(subLines[index]['startMs']);
        if (nextStartMs > currentStartMs) {
          subLines[index]['endMs'] = nextStartMs;
        }
      }
      final int lastEndMs = _timelineMs(subLines.last['endMs']);
      if (lineEndMs > lastEndMs) {
        subLines.last['endMs'] = lineEndMs;
      }
    }
    return subLines;
  }

  Map<String, Object?> _mergeLineBuffer(List<Map<String, Object?>> buffer) {
    if (buffer.length == 1) {
      return buffer.first;
    }
    final Map<String, Object?> first = buffer.first;
    final Map<String, Object?> last = buffer.last;
    final List<Map<String, Object?>> words = <Map<String, Object?>>[];
    final List<String> englishParts = <String>[];
    final List<String> chineseParts = <String>[];
    for (final Map<String, Object?> line in buffer) {
      words.addAll(
        (line['words'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(Map<String, Object?>.from),
      );
      final String english = (line['english'] as String? ?? '').trim();
      if (english.isNotEmpty) {
        englishParts.add(english);
      }
      final String chinese = (line['chinese'] as String? ?? '').trim();
      if (chinese.isNotEmpty) {
        chineseParts.add(chinese);
      }
    }
    return <String, Object?>{
      ...last,
      'startMs': first['startMs'],
      'endMs': last['endMs'],
      'english': englishParts.join(' '),
      'chinese': chineseParts.join(' '),
      'words': words,
    };
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
    final int fallbackMs = chunks.length >= 2
        ? chunks.last.offsetMs - chunks[chunks.length - 2].offsetMs
        : 58000;
    // Use the last chunk's actual duration (derived from its file size for
    // WAV) so a shorter final chunk is not overstated in the progress total.
    return chunks.last.offsetMs + _chunkDurationMs(chunks.last, fallbackMs);
  }

  int _chunkDurationMs(AsrAudioChunk chunk, int fallbackMs) {
    try {
      if (chunk.file.path.toLowerCase().endsWith('.wav')) {
        // 16 kHz mono 16-bit PCM = 32000 bytes/second, plus a 44-byte header.
        final int dataBytes = chunk.file.lengthSync() - 44;
        if (dataBytes > 0) {
          return (dataBytes * 1000 / 32000).round();
        }
      }
    } catch (_) {}
    return fallbackMs;
  }

  void _reportProgressPhase(
    AsrProgressCallback? onProgress,
    int totalChunks,
    String label,
  ) {
    onProgress?.call(
      AsrSubtitleProgress(
        completedChunks: totalChunks,
        totalChunks: totalChunks,
        labelOverride: label,
      ),
    );
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
