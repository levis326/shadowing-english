import 'dart:io';

import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/player_subtitle_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses bilingual subtitles from srt/vtt', () {
    const String rawSrt = '''
1
00:00:01,000 --> 00:00:03,000
Hello there
你好

2
00:00:03,500 --> 00:00:06,000
Welcome to study
''';

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(rawSrt);
    expect(lines, hasLength(2));
    expect(lines[0].english, 'Hello there');
    expect(lines[0].chinese, '你好');
    expect(lines[0].startMs, 1000);
    expect(lines[0].endMs, 3000);

    const String rawVtt = '''
WEBVTT

00:00:00.000 --> 00:00:01.500
How are you?
''';
    final List<PlayerSubtitleLine> linesVtt = parseSubtitleLines(rawVtt);
    expect(linesVtt, hasLength(1));
    expect(linesVtt[0].endMs, 1500);
    expect(linesVtt[0].chinese, '');
  });

  test('exports generated lines to srt with en filename convention', () {
    final List<PlayerSubtitleLine> lines = <PlayerSubtitleLine>[
      const PlayerSubtitleLine(
        startTime: '00:01',
        english: 'Hello there',
        chinese: '你好',
        startMs: 1000,
        endMs: 3000,
      ),
      const PlayerSubtitleLine(
        startTime: '00:03',
        english: 'Welcome',
        chinese: '',
        startMs: 3500,
        endMs: 6000,
      ),
    ];

    final String srt = subtitleLinesToSrt(lines);
    expect(srt, contains('00:00:01,000 --> 00:00:03,000'));
    expect(srt, contains('Hello there'));
    expect(srt, contains('00:00:03,500 --> 00:00:06,000'));
    expect(srt, contains('Welcome'));
    expect(srt, isNot(contains('你好')));

    final String chineseSrt = subtitleLinesToSrt(lines, chinese: true);
    expect(chineseSrt, contains('00:00:01,000 --> 00:00:03,000'));
    expect(chineseSrt, contains('你好'));
    expect(chineseSrt, isNot(contains('Hello there')));

    expect(
      generatedSubtitleSrtFileName(r'C:\videos\Friends-S01E01.mp4'),
      'Friends-S01E01.en.srt',
    );
    expect(
      generatedSubtitleSrtFileName('/videos/Friends-S01E01.mp4'),
      'Friends-S01E01.en.srt',
    );
    expect(
      generatedSubtitleSrtFileName(
        '/videos/Friends-S01E01.mp4',
        languageCode: 'zh',
      ),
      'Friends-S01E01.zh.srt',
    );
  });

  test('merges english and chinese subtitle lines by index', () {
    const String english = '''
1
00:00:01,000 --> 00:00:03,000
Hello there

2
00:00:03,500 --> 00:00:06,000
Welcome to study
''';

    const String chinese = '''
1
00:00:01,000 --> 00:00:03,000
你好

2
00:00:03,500 --> 00:00:06,000
欢迎来学习
''';

    final List<PlayerSubtitleLine> lines = mergeSubtitleLines(
      englishLines: parseSubtitleLines(english),
      chineseLines: parseSubtitleLines(chinese),
    );

    expect(lines, hasLength(2));
    expect(lines[0].english, 'Hello there');
    expect(lines[0].chinese, '你好');
    expect(lines[1].english, 'Welcome to study');
    expect(lines[1].chinese, '欢迎来学习');
  });

  test('keeps english subtitles when chinese track is missing', () {
    const String english = '''
1
00:00:01,000 --> 00:00:03,000
Hello there
''';

    final List<PlayerSubtitleLine> lines = mergeSubtitleLines(
      englishLines: parseSubtitleLines(english),
      chineseLines: const <PlayerSubtitleLine>[],
    );

    expect(lines, hasLength(1));
    expect(lines[0].english, 'Hello there');
    expect(lines[0].chinese, '');
  });

  test('parses generated words json subtitles', () {
    const String rawJson = '''
{
  "version": 1,
  "language": "en",
  "lines": [
    {
      "startMs": 70000,
      "endMs": 73000,
      "english": "I want to learn English.",
      "chinese": "我想学英语。",
      "words": [
        { "text": "I", "startMs": 70000, "endMs": 70280, "confidence": 0.98 },
        { "text": "want", "startMs": 70280, "endMs": 70880, "confidence": 0.96 }
      ]
    }
  ]
}
''';

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(rawJson);

    expect(lines, hasLength(1));
    expect(lines.single.startTime, '01:10');
    expect(lines.single.english, 'I want to learn English.');
    expect(lines.single.chinese, '我想学英语。');
    expect(lines.single.words, hasLength(2));
    expect(lines.single.words.first.text, 'I');
    expect(lines.single.words.last.startMs, 70280);
  });

  test('parses generated subtitle glossary', () {
    const String rawJson = '''
{
  "lines": [],
  "glossary": [
    { "word": "Puddle", "definitionCn": "水坑" },
    { "word": "I'm", "definitionCn": "我是" },
    { "word": "puddle", "definitionCn": "重复释义" }
  ]
}
''';

    expect(parseSubtitleGlossary(rawJson), <String, String>{'puddle': '水坑'});
  });

  test('player state keeps empty lines instead of fallback subtitles', () {
    final PlayerMockState state = PlayerMockState();

    final bool hasRealLines = state.loadLines(const <PlayerSubtitleLine>[]);

    expect(hasRealLines, isFalse);
    expect(state.lines, isEmpty);
    expect(state.hasLines, isFalse);
    expect(state.positionMs, 0);
  });

  test('loads subtitle lines from local file path', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'player_subtitle_loader_test',
    );
    final File subtitleFile = File('${tempDir.path}/episode01.en.srt')
      ..writeAsStringSync('''
1
00:00:01,000 --> 00:00:03,000
Hello from file
''');

    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final List<PlayerSubtitleLine> lines = await loadSubtitleLines(
      subtitleFile.path,
    );

    expect(lines, hasLength(1));
    expect(lines[0].english, 'Hello from file');
  });

  test(
    'player state falls back to english-only mode when chinese is missing',
    () {
      final PlayerMockState state = PlayerMockState()
        ..loadLines(const <PlayerSubtitleLine>[
          PlayerSubtitleLine(
            startTime: '00:01',
            english: 'English only',
            chinese: '',
            startMs: 1000,
            endMs: 2000,
          ),
        ])
        ..setSubtitleMode('单中');

      expect(state.subtitleMode, '单英');
    },
  );

  test('single-line loop restarts before switching to the next subtitle', () {
    final PlayerMockState state = PlayerMockState()
      ..loadLines(const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'First line',
          chinese: '第一句',
          startMs: 1000,
          endMs: 2000,
        ),
        PlayerSubtitleLine(
          startTime: '00:03',
          english: 'Second line',
          chinese: '第二句',
          startMs: 3000,
          endMs: 4000,
        ),
      ])
      ..toggleLoop();

    expect(state.restartLoopAtTimestamp(2000), isTrue);
    expect(state.activeLineIndex, 0);
    expect(state.positionMs, 1000);
  });

  test('sentence loop button starts, switches, and stops line playback', () {
    final PlayerMockState state = PlayerMockState()
      ..loadLines(const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'First line',
          chinese: '第一句',
          startMs: 1000,
          endMs: 2000,
        ),
        PlayerSubtitleLine(
          startTime: '00:03',
          english: 'Second line',
          chinese: '第二句',
          startMs: 3000,
          endMs: 4000,
        ),
      ]);

    expect(state.toggleLineLoopAt(1), isTrue);
    expect(state.activeLineIndex, 1);
    expect(state.positionMs, 3000);
    expect(state.isPlaying, isTrue);
    expect(state.isLooping, isTrue);

    expect(state.toggleLineLoopAt(1), isFalse);
    expect(state.isPlaying, isTrue);
    expect(state.isLooping, isFalse);
  });

  test(
    'player state starts from zero when subtitles load without initial time',
    () {
      final PlayerMockState state = PlayerMockState()
        ..loadLines(const <PlayerSubtitleLine>[
          PlayerSubtitleLine(
            startTime: '00:01',
            english: 'Hello there',
            chinese: '你好',
            startMs: 1000,
            endMs: 3000,
          ),
          PlayerSubtitleLine(
            startTime: '00:03',
            english: 'Welcome to study',
            chinese: '欢迎来学习',
            startMs: 3500,
            endMs: 6000,
          ),
        ]);

      expect(state.positionMs, 0);
      expect(state.activeLineIndex, 0);
    },
  );

  test('player state retains initial time when subtitles are unavailable', () {
    final PlayerMockState state = PlayerMockState()
      ..loadLines(const <PlayerSubtitleLine>[], initialStartTime: '00:34');

    expect(state.positionMs, 34000);
  });

  test('player state tracks video progress when subtitles are unavailable', () {
    final PlayerMockState state = PlayerMockState()
      ..loadLines(const <PlayerSubtitleLine>[])
      ..syncWithTimestamp(34000);

    expect(state.positionMs, 34000);
  });

  test('player state respects explicit initial time when provided', () {
    final PlayerMockState state = PlayerMockState()
      ..loadLines(const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Hello there',
          chinese: '你好',
          startMs: 1000,
          endMs: 3000,
        ),
        PlayerSubtitleLine(
          startTime: '00:03',
          english: 'Welcome to study',
          chinese: '欢迎来学习',
          startMs: 3500,
          endMs: 6000,
        ),
      ], initialStartTime: '00:03');

    expect(state.positionMs, 3000);
    expect(state.activeLineIndex, 1);
  });

  test(
    'player state keeps real seek time and hides subtitles outside cues',
    () {
      final PlayerMockState state = PlayerMockState()
        ..loadLines(const <PlayerSubtitleLine>[
          PlayerSubtitleLine(
            startTime: '00:01',
            english: 'Hello there',
            chinese: '你好',
            startMs: 1000,
            endMs: 3000,
          ),
          PlayerSubtitleLine(
            startTime: '00:05',
            english: 'Welcome back',
            chinese: '欢迎回来',
            startMs: 5000,
            endMs: 6000,
          ),
        ]);

      expect(state.visibleLine, isNull);

      expect(state.seekToMilliseconds(2500), isTrue);
      expect(state.positionMs, 2500);
      expect(state.activeLineIndex, 0);
      expect(state.visibleLine?.english, 'Hello there');

      expect(state.seekToMilliseconds(4500), isTrue);
      expect(state.positionMs, 4500);
      expect(state.activeLineIndex, 0);
      expect(state.visibleLine, isNull);

      expect(state.seekToMilliseconds(5500), isTrue);
      expect(state.positionMs, 5500);
      expect(state.activeLineIndex, 1);
      expect(state.visibleLine?.english, 'Welcome back');
    },
  );

  test('player state keeps short subtitles readable until the next cue', () {
    final PlayerMockState state = PlayerMockState()
      ..loadLines(const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'This line is too short',
          chinese: '这句太短了',
          startMs: 1000,
          endMs: 1200,
        ),
        PlayerSubtitleLine(
          startTime: '00:03',
          english: 'Next line',
          chinese: '下一句',
          startMs: 3000,
          endMs: 4000,
        ),
      ]);

    void syncTo(int milliseconds) {
      state.syncWithTimestamp(milliseconds);
    }

    syncTo(2400);
    expect(state.visibleLine?.english, 'This line is too short');

    syncTo(3000);
    expect(state.visibleLine?.english, 'Next line');
  });

  test(
    'player state does not extend generated word subtitles past cue end',
    () {
      final PlayerMockState state = PlayerMockState()
        ..loadLines(const <PlayerSubtitleLine>[
          PlayerSubtitleLine(
            startTime: '00:01',
            english: 'Generated line',
            chinese: '',
            startMs: 1000,
            endMs: 1200,
            words: <PlayerSubtitleWord>[
              PlayerSubtitleWord(text: 'Generated', startMs: 1000, endMs: 1100),
              PlayerSubtitleWord(text: 'line', startMs: 1100, endMs: 1200),
            ],
          ),
          PlayerSubtitleLine(
            startTime: '00:05',
            english: 'Next line',
            chinese: '',
            startMs: 5000,
            endMs: 6000,
          ),
        ]);

      expect((state..syncWithTimestamp(1300)).visibleLine, isNull);
    },
  );

  test('player state highlights words by generated timestamps', () {
    final PlayerMockState state = PlayerMockState()
      ..loadLines(const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '01:10',
          english: 'I want to learn English.',
          chinese: '我想学英语。',
          startMs: 70000,
          endMs: 73000,
          words: <PlayerSubtitleWord>[
            PlayerSubtitleWord(
              text: 'I',
              startMs: 70000,
              endMs: 70280,
              confidence: 0.98,
            ),
            PlayerSubtitleWord(
              text: 'want',
              startMs: 70280,
              endMs: 70880,
              confidence: 0.96,
            ),
          ],
        ),
      ]);

    expect((state..syncWithTimestamp(70400)).currentWordIndex, 1);
  });

  test('player state keeps previous generated word between word timings', () {
    final PlayerMockState state = PlayerMockState()
      ..loadLines(const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '01:10',
          english: 'I want to learn English.',
          chinese: '我想学英语。',
          startMs: 70000,
          endMs: 73000,
          words: <PlayerSubtitleWord>[
            PlayerSubtitleWord(text: 'I', startMs: 70000, endMs: 70280),
            PlayerSubtitleWord(text: 'want', startMs: 70400, endMs: 70880),
          ],
        ),
      ]);

    expect((state..syncWithTimestamp(69990)).currentWordIndex, -1);
    expect((state..syncWithTimestamp(70300)).currentWordIndex, 0);
    expect((state..syncWithTimestamp(72900)).currentWordIndex, 1);
  });

  test('player state delays subtitle sync by configured offset', () {
    final PlayerMockState state = PlayerMockState()
      ..subtitleDelayMs = 500
      ..loadLines(const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'First',
          chinese: '',
          startMs: 1000,
          endMs: 1800,
        ),
        PlayerSubtitleLine(
          startTime: '00:02',
          english: 'Second',
          chinese: '',
          startMs: 2000,
          endMs: 2800,
        ),
      ]);

    expect((state..syncWithTimestamp(2200)).activeLine.english, 'First');

    expect((state..syncWithTimestamp(2600)).activeLine.english, 'Second');
    expect(state.videoStartMsForLine(1), 2500);
  });
}
