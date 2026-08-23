import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'desktop_nllb.dart';

typedef NllbTranslateBatchOverride = Future<List<String?>> Function({
  required List<String> sentences,
  required String targetLanguage,
});

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

  Future<String?> translate(String sentence, {String? targetLanguage}) async {
    final List<String?> results = await translateBatch(
      <String>[sentence],
      targetLanguage: targetLanguage,
    );
    return results.isEmpty ? null : results.first;
  }

  Future<List<String?>> translateBatch(
    List<String> sentences, {
    String? targetLanguage,
  }) async {
    final List<String> cleaned = sentences
        .map((String sentence) => sentence.trim())
        .where((String sentence) => sentence.isNotEmpty)
        .toList(growable: false);
    if (cleaned.isEmpty) return const <String?>[];
    final String target = targetLanguage ?? defaultTargetLanguage;

    if (translateBatchOverride != null) {
      return translateBatchOverride!(
        sentences: cleaned,
        targetLanguage: target,
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
          sourceLanguage,
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
