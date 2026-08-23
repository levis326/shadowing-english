import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

/// Translates sentences with the bundled CTranslate2 NLLB model.
///
/// Each call spawns the bundled `nllb-translate` binary with a temp input file
/// and reads the translated lines back. The batch API keeps a single process
/// for many sentences (used during subtitle post-processing); single-sentence
/// lookups reuse the same path.
class LocalNllbTranslationService {
  LocalNllbTranslationService({
    this.binaryPathResolver,
    this.modelDirResolver,
    this.tokenizerPathResolver,
    this.translateBatchOverride,
    this.sourceLanguage = desktopNllbSourceLanguage,
    this.defaultTargetLanguage = desktopNllbTargetLanguage,
    this.timeout = const Duration(minutes: 5),
  });

  final Future<String?> Function()? binaryPathResolver;
  final Future<String?> Function()? modelDirResolver;
  final Future<String?> Function()? tokenizerPathResolver;
  final NllbTranslateBatchOverride? translateBatchOverride;
  final String sourceLanguage;
  final String defaultTargetLanguage;
  final Duration timeout;

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

    final Directory tempDir = await Directory.systemTemp.createTemp('nllb_');
    final File inputFile = File(
      '${tempDir.path}${Platform.pathSeparator}input.txt',
    );
    final File outputFile = File(
      '${tempDir.path}${Platform.pathSeparator}output.txt',
    );
    await inputFile.writeAsString('${cleaned.join('\n')}\n');
    try {
      final Process process = await Process.start(
        binary,
        <String>[
          '--model',
          modelDir,
          '--tokenizer',
          tokenizer,
          '--src-lang',
          source,
          '--tgt-lang',
          target,
          '--input',
          inputFile.path,
          '--output',
          outputFile.path,
        ],
      );
      final StringBuffer stderrBuffer = StringBuffer();
      process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
      unawaited(process.stdout.drain<void>());

      int exitCode;
      try {
        exitCode = await process.exitCode.timeout(timeout);
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        throw StateError('本地翻译超时，请重试。');
      }

      if (exitCode != 0) {
        final String error = stderrBuffer.toString().trim();
        throw StateError(error.isEmpty ? '本地翻译失败。' : '本地翻译失败：$error');
      }
      if (!outputFile.existsSync()) {
        throw StateError('本地翻译未生成结果。');
      }
      final List<String> lines = outputFile.readAsLinesSync();
      final List<String?> results = List<String?>.filled(cleaned.length, null);
      for (int i = 0; i < cleaned.length && i < lines.length; i++) {
        final String translated = lines[i].trim();
        results[i] = translated.isEmpty ? null : translated;
      }
      return results;
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }
}

/// Shared singleton used by the local translation provider.
final LocalNllbTranslationService localNllbTranslationService =
    LocalNllbTranslationService();
