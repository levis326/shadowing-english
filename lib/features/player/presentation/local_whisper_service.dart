import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'desktop_whisper.dart';

typedef LocalWhisperInferenceOverride =
    Future<Object?> Function({
      required String baseUrl,
      required File file,
      required String language,
    });

/// Manages a long-lived local `whisper-server` process so the bundled Whisper
/// model is loaded into memory only once, instead of being reloaded for every
/// 58-second audio chunk.
class LocalWhisperService {
  LocalWhisperService({
    this.serverPathResolver,
    this.modelPathResolver,
    this.port = 8071,
    this.wordThreshold = 0.01,
    this.inferenceOverride,
  });

  final Future<String?> Function()? serverPathResolver;
  final Future<String?> Function()? modelPathResolver;
  final int port;
  final double wordThreshold;

  /// Test seam: replace the HTTP POST to `/inference`.
  final LocalWhisperInferenceOverride? inferenceOverride;

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
    final String? serverPath = serverPathResolver != null
        ? await serverPathResolver!()
        : await findDesktopWhisperServer();
    final String? modelPath = modelPathResolver != null
        ? await modelPathResolver!()
        : await findDesktopWhisperModel();
    if (serverPath == null || modelPath == null) {
      throw StateError('本地语音识别组件缺失，请重新安装最新版本。');
    }
    final Process process = await Process.start(serverPath, <String>[
      '-m',
      modelPath,
      '--host',
      '127.0.0.1',
      '--port',
      '$port',
      '--word-thold',
      '$wordThreshold',
    ]);
    _serverProcess = process;
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());

    final Dio dio = _healthDio();
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      if (await _healthy(dio)) return;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    await shutdown();
    throw StateError('本地语音识别服务启动超时，请重试。');
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

  Future<Map<String, Object?>> transcribe({
    required File file,
    required String language,
  }) async {
    await ensureStarted();
    final String baseUrl = 'http://127.0.0.1:$port';
    final Object? data = inferenceOverride != null
        ? await inferenceOverride!(
            baseUrl: baseUrl,
            file: file,
            language: language,
          )
        : await _postInference(
            baseUrl: baseUrl,
            file: file,
            language: language,
          );
    if (data is! Map<String, dynamic>) {
      throw StateError('invalid-asr-response');
    }
    return Map<String, Object?>.from(data);
  }

  Future<Object?> _postInference({
    required String baseUrl,
    required File file,
    required String language,
  }) async {
    final FormData formData = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(file.path),
      'language': language,
      'response_format': 'verbose_json',
    });
    final Dio dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(minutes: 10),
      ),
    );
    final Response<dynamic> response = await dio.post<dynamic>(
      '/inference',
      data: formData,
    );
    return response.data;
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

/// Shared singleton used by the offline subtitle provider.
final LocalWhisperService localWhisperService = LocalWhisperService();
