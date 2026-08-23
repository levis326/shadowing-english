import 'package:common_learn_english/features/shared/data/local_nllb_translation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('translateBatch filters empty sentences and aligns results', () async {
    final LocalNllbTranslationService service = LocalNllbTranslationService(
      translateBatchOverride:
          ({
            required List<String> sentences,
            required String targetLanguage,
            required String sourceLanguage,
          }) async {
            expect(targetLanguage, 'zho_Hans');
            expect(sourceLanguage, 'eng_Latn');
            return sentences.map((String s) => s == 'hi' ? '你好' : null).toList(
              growable: false,
            );
          },
    );

    final List<String?> results = await service.translateBatch(
      <String>['hi', '', '  '],
      targetLanguage: 'zho_Hans',
    );

    expect(results, <String?>['你好']);
  });

  test('translate returns the first result or null for empty input', () async {
    final LocalNllbTranslationService service = LocalNllbTranslationService(
      translateBatchOverride:
          ({
            required List<String> sentences,
            required String targetLanguage,
            required String sourceLanguage,
          }) async => sentences.map((String _) => '译').toList(growable: false),
    );

    expect(await service.translate('hello'), '译');
    expect(await service.translate(''), isNull);
  });

  test('maps whisper language codes to NLLB source languages', () {
    expect(nllbSourceLanguageForWhisper('en'), 'eng_Latn');
    expect(nllbSourceLanguageForWhisper('ja'), 'jpn_Jpan');
    expect(nllbSourceLanguageForWhisper('ko'), 'kor_Hang');
    expect(nllbSourceLanguageForWhisper('zh'), 'zho_Hans');
    expect(nllbSourceLanguageForWhisper('fr'), 'fra_Latn');
    expect(nllbSourceLanguageForWhisper(''), 'eng_Latn');
    expect(nllbSourceLanguageForWhisper('xx'), 'eng_Latn');
  });
}
