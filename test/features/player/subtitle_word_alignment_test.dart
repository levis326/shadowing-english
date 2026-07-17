import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/subtitle_word_alignment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps SRT text and fills words missed by ASR with ordered timings', () {
    const PlayerSubtitleLine reference = PlayerSubtitleLine(
      startTime: '00:01',
      english: 'I would like to go home.',
      chinese: '我想回家。',
      startMs: 1000,
      endMs: 4000,
    );
    const PlayerSubtitleLine recognition = PlayerSubtitleLine(
      startTime: '00:01',
      english: 'I like go home',
      chinese: '',
      startMs: 1000,
      endMs: 4000,
      words: <PlayerSubtitleWord>[
        PlayerSubtitleWord(text: 'I', startMs: 1100, endMs: 1250),
        PlayerSubtitleWord(text: 'like', startMs: 1800, endMs: 2100),
        PlayerSubtitleWord(text: 'go', startMs: 2600, endMs: 2750),
        PlayerSubtitleWord(text: 'home', startMs: 3200, endMs: 3500),
      ],
    );

    final SubtitleWordAlignmentResult result = alignReferenceSubtitles(
      reference: const <PlayerSubtitleLine>[reference],
      recognition: const <PlayerSubtitleLine>[recognition],
    );

    expect(result.lines.single.english, reference.english);
    expect(
      result.lines.single.words.map((PlayerSubtitleWord word) => word.text),
      <String>['I', 'would', 'like', 'to', 'go', 'home'],
    );
    expect(result.directWordCount, 4);
    expect(result.estimatedWordCount, 2);
    for (int index = 1; index < result.lines.single.words.length; index += 1) {
      expect(
        result.lines.single.words[index].startMs,
        greaterThanOrEqualTo(result.lines.single.words[index - 1].endMs),
      );
    }
  });

  test('uses safe interpolation when ASR has no matching words', () {
    const PlayerSubtitleLine reference = PlayerSubtitleLine(
      startTime: '00:01',
      english: 'This sentence stays correct.',
      chinese: '',
      startMs: 1000,
      endMs: 3000,
    );
    final SubtitleWordAlignmentResult result = alignReferenceSubtitles(
      reference: const <PlayerSubtitleLine>[reference],
      recognition: const <PlayerSubtitleLine>[],
    );

    expect(result.directWordCount, 0);
    expect(result.estimatedWordCount, 4);
    expect(result.lines.single.words, hasLength(4));
    expect(
      result.lines.single.words.every(
        (PlayerSubtitleWord word) =>
            word.startMs >= reference.startMs && word.endMs <= reference.endMs,
      ),
      isTrue,
    );
  });

  test('drops decorative cues and sorts usable reference subtitles', () {
    final SubtitleWordAlignmentResult result = alignReferenceSubtitles(
      reference: const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:03',
          english: 'Second sentence.',
          chinese: '',
          startMs: 3000,
          endMs: 5000,
        ),
        PlayerSubtitleLine(
          startTime: '00:02',
          english: '♪ ♪',
          chinese: '',
          startMs: 2000,
          endMs: 2500,
        ),
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'First sentence.',
          chinese: '',
          startMs: 1000,
          endMs: 2000,
        ),
      ],
      recognition: const <PlayerSubtitleLine>[],
    );

    expect(
      result.lines.map((PlayerSubtitleLine line) => line.english),
      <String>['First sentence.', 'Second sentence.'],
    );
  });

  test('expands an extremely short cue enough for valid word timings', () {
    final SubtitleWordAlignmentResult result = alignReferenceSubtitles(
      reference: const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'One two three',
          chinese: '',
          startMs: 1000,
          endMs: 1001,
        ),
      ],
      recognition: const <PlayerSubtitleLine>[],
    );

    final PlayerSubtitleLine line = result.lines.single;
    expect(line.endMs, 1003);
    expect(line.words, hasLength(3));
    expect(line.words.last.endMs, line.endMs);
  });

  test('keeps matched tail words inside the reference cue', () {
    final SubtitleWordAlignmentResult result = alignReferenceSubtitles(
      reference: const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:02',
          english: "I'm Peppa Pig. This is my little brother, George.",
          chinese: '',
          startMs: 2535,
          endMs: 6232,
        ),
      ],
      recognition: const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:02',
          english: "I'm Peppa Pig This is my little brother George",
          chinese: '',
          startMs: 2535,
          endMs: 7000,
          words: <PlayerSubtitleWord>[
            PlayerSubtitleWord(text: "I'm", startMs: 2535, endMs: 2700),
            PlayerSubtitleWord(text: 'Peppa', startMs: 2700, endMs: 3100),
            PlayerSubtitleWord(text: 'Pig', startMs: 3100, endMs: 3500),
            PlayerSubtitleWord(text: 'This', startMs: 3500, endMs: 4000),
            PlayerSubtitleWord(text: 'is', startMs: 4000, endMs: 4300),
            PlayerSubtitleWord(text: 'my', startMs: 4300, endMs: 4700),
            PlayerSubtitleWord(text: 'little', startMs: 4700, endMs: 5964),
            PlayerSubtitleWord(text: 'brother', startMs: 6232, endMs: 6500),
            PlayerSubtitleWord(text: 'George', startMs: 6500, endMs: 6900),
          ],
        ),
      ],
    );

    final PlayerSubtitleLine line = result.lines.single;
    expect(line.words, hasLength(9));
    expect(
      line.words.every(
        (PlayerSubtitleWord word) =>
            word.startMs >= line.startMs && word.endMs <= line.endMs,
      ),
      isTrue,
    );
    expect(line.words.map((PlayerSubtitleWord word) => word.text), <String>[
      "I'm",
      'Peppa',
      'Pig',
      'This',
      'is',
      'my',
      'little',
      'brother',
      'George',
    ]);
  });
}
