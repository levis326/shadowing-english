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
}
