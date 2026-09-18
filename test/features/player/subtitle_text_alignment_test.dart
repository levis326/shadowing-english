import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/subtitle_text_alignment.dart';
import 'package:flutter_test/flutter_test.dart';

PlayerSubtitleLine _line(String text, int startMs, int endMs) {
  return PlayerSubtitleLine(
    startTime: '00:00',
    english: text,
    chinese: '',
    startMs: startMs,
    endMs: endMs,
  );
}

List<String> _texts(List<PlayerSubtitleLine> lines) =>
    lines.map((PlayerSubtitleLine line) => line.english).toList();

void main() {
  group('assignTimingsFromRecognition', () {
    test('keeps the reference text and borrows recognition timings', () {
      final List<PlayerSubtitleLine> result = assignTimingsFromRecognition(
        reference: <PlayerSubtitleLine>[
          _line('Hello there my friend.', 0, 0),
          _line('How are you today?', 0, 0),
        ],
        recognition: <PlayerSubtitleLine>[
          _line('hello there my friend', 1000, 3000),
          _line('how are you today', 3500, 6000),
        ],
      );

      expect(_texts(result), <String>[
        'Hello there my friend.',
        'How are you today?',
      ]);
      expect(result[0].startMs, 1000);
      expect(result[0].endMs, 3000);
      expect(result[1].startMs, 3500);
      expect(result[1].endMs, 6000);
    });

    test('splits a whisper segment that merged several sentences', () {
      final List<PlayerSubtitleLine> result = assignTimingsFromRecognition(
        reference: <PlayerSubtitleLine>[
          _line('First sentence here.', 0, 0),
          _line('Second sentence here.', 0, 0),
          _line('Third sentence here.', 0, 0),
        ],
        recognition: <PlayerSubtitleLine>[
          // Whisper 把前两句合成了一句。
          _line('first sentence here second sentence here', 1000, 5000),
          _line('third sentence here', 5500, 8000),
        ],
      );

      // 识别把前两句合成了一段：两句话按字数平分 1000-5000，
      // 而不是只有第一句拿到整段、另外一句被推到后面。
      expect(result[0].startMs, 1000);
      expect(result[0].endMs, 3000);
      expect(result[1].startMs, 3000);
      expect(result[1].endMs, 5000);
      expect(result[2].startMs, 5500);
      // 时间严格递增，不会互相交叉。
      for (int i = 1; i < result.length; i += 1) {
        expect(result[i].startMs >= result[i - 1].endMs, isTrue);
      }
    });

    test('splits one merged whisper segment across its sentences', () {
      final List<PlayerSubtitleLine> result = assignTimingsFromRecognition(
        reference: <PlayerSubtitleLine>[
          _line('Alpha beta.', 0, 0),
          _line('Gamma delta.', 0, 0),
          _line('Epsilon zeta.', 0, 0),
        ],
        // whisper 把三句合成了一段：三句应当按顺序平分这一段的 0-9000ms。
        recognition: <PlayerSubtitleLine>[
          _line('alpha beta gamma delta epsilon zeta', 0, 9000),
        ],
      );

      expect(result, hasLength(3));
      expect(<int>[for (final PlayerSubtitleLine l in result) l.startMs], <int>[
        0,
        3000,
        6000,
      ]);
      expect(<int>[for (final PlayerSubtitleLine l in result) l.endMs], <int>[
        3000,
        6000,
        9000,
      ]);
    });

    test('interpolates a reference sentence whisper missed', () {
      final List<PlayerSubtitleLine> result = assignTimingsFromRecognition(
        reference: <PlayerSubtitleLine>[
          _line('Alpha beta gamma.', 0, 0),
          _line('Delta epsilon zeta.', 0, 0),
          _line('Eta theta iota.', 0, 0),
        ],
        recognition: <PlayerSubtitleLine>[
          _line('alpha beta gamma', 0, 3000),
          // 中间这句识别里没有。
          _line('eta theta iota', 6000, 9000),
        ],
      );

      expect(result[1].startMs, 3000);
      expect(result[1].endMs, 6000);
      expect(result[2].startMs, 6000);
    });

    test('distributes trailing sentences up to the fallback end', () {
      final List<PlayerSubtitleLine> result = assignTimingsFromRecognition(
        reference: <PlayerSubtitleLine>[
          _line('Alpha beta gamma.', 0, 0),
          _line('Delta epsilon.', 0, 0),
          _line('Zeta eta theta.', 0, 0),
        ],
        recognition: <PlayerSubtitleLine>[_line('alpha beta gamma', 0, 2000)],
        fallbackEndMs: 8000,
      );

      expect(result[0].startMs, 0);
      expect(result[0].endMs, 2000);
      expect(result[1].startMs, 2000);
      expect(result[2].endMs, 8000);
      for (final PlayerSubtitleLine line in result) {
        expect(line.endMs, greaterThan(line.startMs));
      }
    });

    test('returns nothing when recognition is empty', () {
      expect(
        assignTimingsFromRecognition(
          reference: <PlayerSubtitleLine>[_line('Hello.', 0, 0)],
          recognition: const <PlayerSubtitleLine>[],
        ),
        isEmpty,
      );
      expect(
        assignTimingsFromRecognition(
          reference: const <PlayerSubtitleLine>[],
          recognition: <PlayerSubtitleLine>[_line('Hello.', 0, 1000)],
        ),
        isEmpty,
      );
    });
  });
}
