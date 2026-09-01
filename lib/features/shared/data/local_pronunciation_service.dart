import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'desktop_pronunciation.dart';

/// A per-syllable pronunciation score returned by the local server.
class PronunciationSyllableScore {
  const PronunciationSyllableScore({
    required this.syllable,
    required this.score,
  });

  factory PronunciationSyllableScore.fromJson(Map<String, dynamic> json) {
    return PronunciationSyllableScore(
      syllable: (json['syllable'] as String? ?? '').trim(),
      score: (json['score'] as num? ?? 0).toDouble(),
    );
  }

  final String syllable;
  final double score;
}

/// A per-word pronunciation score returned by the local server, including the
/// finer-grained per-syllable scores when the server provides them.
class PronunciationWordScore {
  const PronunciationWordScore({
    required this.word,
    required this.score,
    this.syllables = const <PronunciationSyllableScore>[],
  });

  factory PronunciationWordScore.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawSyllables =
        json['syllables'] as List<dynamic>? ?? const <dynamic>[];
    return PronunciationWordScore(
      word: (json['word'] as String? ?? '').trim(),
      score: (json['score'] as num? ?? 0).toDouble(),
      syllables: rawSyllables
          .whereType<Map<String, dynamic>>()
          .map(PronunciationSyllableScore.fromJson)
          .toList(growable: false),
    );
  }

  final String word;
  final double score;
  final List<PronunciationSyllableScore> syllables;
}

/// The overall + per-word pronunciation evaluation of one spoken sentence.
class PronunciationResult {
  const PronunciationResult({required this.score, required this.words});

  factory PronunciationResult.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawWords =
        json['words'] as List<dynamic>? ?? const <dynamic>[];
    return PronunciationResult(
      score: (json['score'] as num? ?? 0).toDouble(),
      words: rawWords
          .whereType<Map<String, dynamic>>()
          .map(PronunciationWordScore.fromJson)
          .toList(growable: false),
    );
  }

  final double score;
  final List<PronunciationWordScore> words;
}

typedef PronunciationEvaluateOverride =
    Future<PronunciationResult> Function({
      required Uint8List audioBytes,
      required String text,
      required int sampleRate,
    });

/// Manages a long-lived local `pronunciation-server` process so the bundled
/// wav2vec2 model is loaded only once, mirroring the whisper-server integration.
class LocalPronunciationService {
  LocalPronunciationService({
    this.binaryPathResolver,
    this.modelDirResolver,
    this.evaluateOverride,
    this.port = 8082,
  });

  final Future<String?> Function()? binaryPathResolver;
  final Future<String?> Function()? modelDirResolver;
  final PronunciationEvaluateOverride? evaluateOverride;
  final int port;

  Process? _serverProcess;
  Future<void>? _starting;

  bool get isRunning => _serverProcess != null;

  Future<void> ensureStarted() async {
    if (_serverProcess != null) return;
    final Future<void>? inFlight = _starting;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final Future<void> start = _start();
    _starting = start;
    try {
      await start;
    } finally {
      _starting = null;
    }
  }

  Future<void> _start() async {
    final String? binary = binaryPathResolver != null
        ? await binaryPathResolver!()
        : await findDesktopPronunciationBinary();
    final String? modelDir = modelDirResolver != null
        ? await modelDirResolver!()
        : await findDesktopPronunciationModelDir();
    if (binary == null || modelDir == null) {
      throw StateError('本地发音评测组件缺失，请重新安装最新版本。');
    }
    final Process process = await Process.start(binary, <String>[
      '--model-dir',
      modelDir,
      '--port',
      '$port',
    ]);
    _serverProcess = process;
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());

    final Dio dio = _healthDio();
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      if (await _healthy(dio)) return;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    await shutdown();
    throw StateError('本地发音评测服务启动超时，请重试。');
  }

  Dio _healthDio() => Dio(
    BaseOptions(
      baseUrl: 'http://127.0.0.1:$port',
      connectTimeout: const Duration(seconds: 2),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );

  Future<bool> _healthy(Dio dio) async {
    try {
      final Response<dynamic> response = await dio.get<dynamic>('/health');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<PronunciationResult> evaluate({
    required Uint8List audioBytes,
    required String text,
    int sampleRate = 16000,
  }) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty || audioBytes.isEmpty) {
      return const PronunciationResult(score: 0, words: <PronunciationWordScore>[]);
    }

    if (evaluateOverride != null) {
      return evaluateOverride!(
        audioBytes: audioBytes,
        text: trimmed,
        sampleRate: sampleRate,
      );
    }

    await ensureStarted();
    try {
      return await _evaluateOnce(
        audioBytes: audioBytes,
        text: trimmed,
        sampleRate: sampleRate,
      );
    } on DioException {
      await shutdown();
      await ensureStarted();
      return _evaluateOnce(
        audioBytes: audioBytes,
        text: trimmed,
        sampleRate: sampleRate,
      );
    }
  }

  Future<PronunciationResult> _evaluateOnce({
    required Uint8List audioBytes,
    required String text,
    required int sampleRate,
  }) async {
    final Dio dio = Dio(
      BaseOptions(
        baseUrl: 'http://127.0.0.1:$port',
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(minutes: 3),
      ),
    );
    final Response<dynamic> response = await dio.post<dynamic>(
      '/evaluate',
      data: jsonEncode(<String, dynamic>{
        'audio': base64Encode(audioBytes),
        'text': text,
        'sample_rate': sampleRate,
      }),
    );
    final Map<String, dynamic> data = response.data as Map<String, dynamic>;
    return PronunciationResult.fromJson(data);
  }

  Future<void> shutdown() async {
    final Process? process = _serverProcess;
    _serverProcess = null;
    if (process == null) return;
    process.kill();
    try {
      await process.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return process.exitCode;
        },
      );
    } catch (_) {}
  }
}

/// Shared singleton used by the pronunciation evaluation flow.
final LocalPronunciationService localPronunciationService =
    LocalPronunciationService();
