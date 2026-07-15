import 'dart:convert';

import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/subtitle_reference_review.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const PlayerSubtitleLine reference = PlayerSubtitleLine(
    startTime: '00:01',
    english: 'Hello, world!',
    chinese: '你好',
    startMs: 1000,
    endMs: 2000,
  );
  test('reports text differences against a time-aligned reference', () {
    final SubtitleReferenceReview review = reviewGeneratedSubtitles(
      generated: <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Hello word',
          chinese: '',
          startMs: 1050,
          endMs: 2000,
        ),
      ],
      reference: <PlayerSubtitleLine>[reference],
    );
    expect(review.comparedLines, 1);
    expect(review.differentLines, 1);
  });
  test('adopting a reference keeps generated Chinese when needed', () {
    expect(
      adoptReferenceSubtitles(
        generated: <PlayerSubtitleLine>[
          const PlayerSubtitleLine(
            startTime: '00:01',
            english: 'wrong',
            chinese: '你好',
            startMs: 1000,
            endMs: 2000,
          ),
        ],
        reference: <PlayerSubtitleLine>[reference],
      ).single.english,
      'Hello, world!',
    );
  });

  test('adopting matching reference words preserves ASR timestamps', () {
    final List<PlayerSubtitleLine> adopted = adoptReferenceSubtitles(
      generated: <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Hello word!',
          chinese: '你好',
          startMs: 1000,
          endMs: 2000,
          words: <PlayerSubtitleWord>[
            PlayerSubtitleWord(text: 'Hello', startMs: 1000, endMs: 1400),
            PlayerSubtitleWord(text: 'word', startMs: 1400, endMs: 2000),
          ],
        ),
      ],
      reference: <PlayerSubtitleLine>[reference],
    );

    expect(
      adopted.single.words.map((PlayerSubtitleWord word) => word.text),
      <String>['Hello', 'world'],
    );
    expect(adopted.single.words.first.startMs, 1000);
    expect(adopted.single.words.last.endMs, 2000);
  });

  test('serialized adopted subtitles keep words and glossary', () {
    final String raw = subtitleLinesToJson(
      <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Hello',
          chinese: '你好',
          startMs: 1000,
          endMs: 2000,
          words: <PlayerSubtitleWord>[
            PlayerSubtitleWord(text: 'Hello', startMs: 1000, endMs: 2000),
          ],
        ),
      ],
      wordDefinitions: const <String, String>{'hello': '你好'},
    );
    final Map<String, dynamic> decoded =
        jsonDecode(raw) as Map<String, dynamic>;
    final Map<String, dynamic> line =
        (decoded['lines'] as List<dynamic>).single as Map<String, dynamic>;

    expect(line['words'], isNotEmpty);
    expect(decoded['glossary'], isNotEmpty);
  });
}
