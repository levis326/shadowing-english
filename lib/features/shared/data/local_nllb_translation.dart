import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'desktop_nllb.dart';

typedef NllbTranslateBatchOverride = Future<List<String?>> Function({
  required List<String> sentences,
  required String targetLanguage,
  required String sourceLanguage,
});

/// Maps a Whisper language code (ISO 639-1, as returned by whisper.cpp) to the
/// NLLB-200 language code used as the translation source prefix. Falls back to
/// English for unknown or empty languages.
String nllbSourceLanguageForWhisper(String whisperLanguage) {
  final String code = whisperLanguage.trim().toLowerCase();
  return _whisperToNllbLanguage[code] ?? 'eng_Latn';
}

const Map<String, String> _whisperToNllbLanguage = <String, String>{
  'en': 'eng_Latn',
  'zh': 'zho_Hans',
  'yue': 'yue_Hant',
  'ja': 'jpn_Jpan',
  'ko': 'kor_Hang',
  'fr': 'fra_Latn',
  'de': 'deu_Latn',
  'es': 'spa_Latn',
  'ru': 'rus_Cyrl',
  'pt': 'por_Latn',
  'it': 'ita_Latn',
  'ar': 'arb_Arab',
  'hi': 'hin_Deva',
  'tr': 'tur_Latn',
  'nl': 'nld_Latn',
  'pl': 'pol_Latn',
  'vi': 'vie_Latn',
  'th': 'tha_Thai',
  'id': 'ind_Latn',
  'ms': 'zsm_Latn',
  'cs': 'ces_Latn',
  'sv': 'swe_Latn',
  'da': 'dan_Latn',
  'fi': 'fin_Latn',
  'no': 'nob_Latn',
  'he': 'heb_Hebr',
  'uk': 'ukr_Cyrl',
  'el': 'ell_Grek',
  'ro': 'ron_Latn',
  'hu': 'hun_Latn',
  'bg': 'bul_Cyrl',
  'hr': 'hrv_Latn',
  'sk': 'slk_Latn',
  'sl': 'slv_Latn',
  'et': 'est_Latn',
  'lv': 'lvs_Latn',
  'lt': 'lit_Latn',
  'fa': 'pes_Arab',
  'bn': 'ben_Beng',
  'ta': 'tam_Taml',
  'te': 'tel_Telu',
  'ur': 'urd_Arab',
  'sw': 'swh_Latn',
  'af': 'afr_Latn',
  'sq': 'als_Latn',
  'am': 'amh_Ethi',
  'az': 'azj_Latn',
  'be': 'bel_Cyrl',
  'bs': 'bos_Latn',
  'ca': 'cat_Latn',
  'cy': 'cym_Latn',
  'eu': 'eus_Latn',
  'gl': 'glg_Latn',
  'gu': 'guj_Gujr',
  'is': 'isl_Latn',
  'ka': 'kat_Geor',
  'kk': 'kaz_Cyrl',
  'km': 'khm_Khmr',
  'kn': 'kan_Knda',
  'lo': 'lao_Laoo',
  'mk': 'mkd_Cyrl',
  'ml': 'mal_Mlym',
  'mn': 'khk_Cyrl',
  'mr': 'mar_Deva',
  'my': 'mya_Mymr',
  'ne': 'npi_Deva',
  'pa': 'pan_Guru',
  'si': 'sin_Sinh',
  'sr': 'srp_Cyrl',
  'tg': 'tgk_Cyrl',
  'tk': 'tuk_Latn',
  'tl': 'tgl_Latn',
  'ug': 'uig_Arab',
  'uz': 'uzn_Latn',
  'yi': 'ydd_Hebr',
  'yo': 'yor_Latn',
};

/// Manages a long-lived local `nllb-server` process so the bundled NLLB model
/// is loaded only once, mirroring the whisper-server integration.
class LocalNllbTranslationService {
  LocalNllbTranslationService({
    this.binaryPathResolver,
    this.modelDirResolver,
    this.tokenizerPathResolver,
    this.translateBatchOverride,
    this.sourceLanguage = desktopNllbSourceLanguage,
    this.defaultTargetLanguage = desktopNllbTargetLanguage,
    this.port = 8081,
  });

  final Future<String?> Function()? binaryPathResolver;
  final Future<String?> Function()? modelDirResolver;
  final Future<String?> Function()? tokenizerPathResolver;
  final NllbTranslateBatchOverride? translateBatchOverride;
  final String sourceLanguage;
  final String defaultTargetLanguage;
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
        : await findDesktopNllbBinary();
    final String? modelDir = modelDirResolver != null
        ? await modelDirResolver!()
        : await findDesktopNllbModelDir();
    final String? tokenizer = tokenizerPathResolver != null
        ? await tokenizerPathResolver!()
        : await findDesktopNllbTokenizer();
    if (binary == null || modelDir == null || tokenizer == null) {
      throw StateError('本地翻译组件缺失，请重新安装最新版本。');
    }
    final Process process = await Process.start(binary, <String>[
      '--model',
      modelDir,
      '--tokenizer',
      tokenizer,
      '--src-lang',
      sourceLanguage,
      '--tgt-lang',
      defaultTargetLanguage,
      '--port',
      '$port',
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
    throw StateError('本地翻译服务启动超时，请重试。');
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

  Future<String?> translate(
    String sentence, {
    String? targetLanguage,
    String? sourceLanguage,
  }) async {
    final List<String?> results = await translateBatch(
      <String>[sentence],
      targetLanguage: targetLanguage,
      sourceLanguage: sourceLanguage,
    );
    return results.isEmpty ? null : results.first;
  }

  Future<List<String?>> translateBatch(
    List<String> sentences, {
    String? targetLanguage,
    String? sourceLanguage,
  }) async {
    final List<String> cleaned = sentences
        .map((String sentence) => sentence.trim())
        .where((String sentence) => sentence.isNotEmpty)
        .toList(growable: false);
    if (cleaned.isEmpty) return const <String?>[];
    final String target = targetLanguage ?? defaultTargetLanguage;
    final String source = sourceLanguage ?? this.sourceLanguage;

    if (translateBatchOverride != null) {
      return translateBatchOverride!(
        sentences: cleaned,
        targetLanguage: target,
        sourceLanguage: source,
      );
    }

    await ensureStarted();
    try {
      return await _translateBatchOnce(
        sentences: cleaned,
        targetLanguage: target,
        sourceLanguage: source,
      );
    } on DioException {
      // The server may have stalled; restart it once and retry.
      await shutdown();
      await ensureStarted();
      return _translateBatchOnce(
        sentences: cleaned,
        targetLanguage: target,
        sourceLanguage: source,
      );
    }
  }

  Future<List<String?>> _translateBatchOnce({
    required List<String> sentences,
    required String targetLanguage,
    required String sourceLanguage,
  }) async {
    final Dio dio = Dio(
      BaseOptions(
        baseUrl: 'http://127.0.0.1:$port',
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(minutes: 6),
      ),
    );
    final Response<dynamic> response = await dio.post<dynamic>(
      '/translate',
      data: jsonEncode(<String, dynamic>{
        'sentences': sentences,
        'src_lang': sourceLanguage,
        'tgt_lang': targetLanguage,
      }),
    );
    final Map<String, dynamic> data = response.data as Map<String, dynamic>;
    final List<dynamic> translations =
        data['translations'] as List<dynamic>? ?? const <dynamic>[];
    final List<String?> results = List<String?>.filled(sentences.length, null);
    for (int i = 0; i < sentences.length && i < translations.length; i++) {
      final String translated = (translations[i] as String? ?? '').trim();
      results[i] = translated.isEmpty ? null : translated;
    }
    return results;
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

/// Shared singleton used by the local translation provider.
final LocalNllbTranslationService localNllbTranslationService =
    LocalNllbTranslationService();
