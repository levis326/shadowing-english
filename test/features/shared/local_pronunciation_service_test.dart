import 'dart:typed_data';

import 'package:common_learn_english/features/shared/data/local_pronunciation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PronunciationResult parses the server JSON', () {
    final PronunciationResult result = PronunciationResult.fromJson(
      <String, dynamic>{
        'score': 0.8,
        'words': <Map<String, dynamic>>[
          <String, dynamic>{'word': 'THE', 'score': 0.9},
          <String, dynamic>{'word': 'WEATHER', 'score': 0.7},
        ],
      },
    );

    expect(result.score, 0.8);
    expect(result.words, hasLength(2));
    expect(result.words.first.word, 'THE');
    expect(result.words.first.score, 0.9);
    expect(result.words.last.word, 'WEATHER');
  });

  test('evaluate returns an empty result for empty input', () async {
    final LocalPronunciationService service = LocalPronunciationService();
    final PronunciationResult result = await service.evaluate(
      audioBytes: Uint8List(0),
      text: '',
    );
    expect(result.score, 0);
    expect(result.words, isEmpty);
  });

  test('evaluate uses the injected override seam', () async {
    final LocalPronunciationService service = LocalPronunciationService(
      evaluateOverride:
          ({
            required Uint8List audioBytes,
            required String text,
            required int sampleRate,
          }) async {
            expect(text, 'hello');
            expect(sampleRate, 16000);
            return const PronunciationResult(
              score: 0.5,
              words: <PronunciationWordScore>[
                PronunciationWordScore(word: 'HELLO', score: 0.5),
              ],
            );
          },
    );

    final PronunciationResult result = await service.evaluate(
      audioBytes: Uint8List.fromList(<int>[1, 2, 3]),
      text: 'hello',
    );
    expect(result.score, 0.5);
    expect(result.words.single.word, 'HELLO');
  });
}
