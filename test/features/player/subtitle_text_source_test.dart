import 'dart:io';

import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/subtitle_text_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSubtitleTextFile', () {
    test('plain text is split into one sentence per line', () {
      final SubtitleTextSource source = parseSubtitleTextFile('''
Hello there. How are you?
I am fine; thanks for asking.
''');

      expect(source.hasTimings, isFalse);
      expect(
        source.lines.map((PlayerSubtitleLine line) => line.english),
        <String>[
          'Hello there.',
          'How are you?',
          'I am fine;',
          'thanks for asking.',
        ],
      );
    });

    test('a single paragraph is split at sentence punctuation only', () {
      final SubtitleTextSource source = parseSubtitleTextFile(
        'I like English, and I study every day. It is fun! 你呢？我也喜欢。',
      );

      // 逗号不在这里拆（交给后面和 AI 字幕一样的拆行规则）。
      expect(
        source.lines.map((PlayerSubtitleLine line) => line.english),
        <String>[
          'I like English, and I study every day.',
          'It is fun!',
          '你呢？',
          '我也喜欢。',
        ],
      );
    });

    test('decimals are not treated as sentence ends', () {
      final SubtitleTextSource source = parseSubtitleTextFile(
        'The price is 3.5 dollars. That is cheap.',
      );

      expect(
        source.lines.map((PlayerSubtitleLine line) => line.english),
        <String>['The price is 3.5 dollars.', 'That is cheap.'],
      );
    });

    test('quotes after the punctuation stay on the same sentence', () {
      final SubtitleTextSource source = parseSubtitleTextFile(
        'He said "hello." Then he left.',
      );

      expect(
        source.lines.map((PlayerSubtitleLine line) => line.english),
        <String>['He said "hello."', 'Then he left.'],
      );
    });

    test('srt content keeps its own timeline', () {
      const String srt = '''
1
00:00:01,000 --> 00:00:03,000
Hello there

2
00:00:03,500 --> 00:00:06,000
How are you
''';
      final SubtitleTextSource source = parseSubtitleTextFile(
        srt,
        fileName: 'lesson.en.srt',
      );

      expect(source.hasTimings, isTrue);
      expect(source.displayName, 'lesson.en.srt');
      expect(source.lines, hasLength(2));
      expect(source.lines.first.startMs, 1000);
      expect(source.lines.first.endMs, 3000);
      expect(source.lines.first.english, 'Hello there');
    });

    test('the app exported words json works as a timed source', () {
      const String json = '''
{"version":1,"language":"en","lines":[{"startMs":1000,"endMs":3000,"english":"Hello there","chinese":"你好","words":[{"text":"Hello","startMs":1000,"endMs":2000}]}]}
''';
      final SubtitleTextSource source = parseSubtitleTextFile(json);

      expect(source.hasTimings, isTrue);
      expect(source.lines, hasLength(1));
      expect(source.lines.single.english, 'Hello there');
      expect(source.lines.single.startMs, 1000);
    });

    test('empty or punctuation-only content yields no lines', () {
      expect(parseSubtitleTextFile('   \n\n  ').lines, isEmpty);
      expect(parseSubtitleTextFile('--- ===').lines, isEmpty);
    });

    test('loadSubtitleTextFile reads a utf8 file from disk', () async {
      final Directory dir = Directory.systemTemp.createTempSync(
        'subtitle-text-source-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final File file = File('${dir.path}/lesson.txt')
        ..writeAsStringSync('\uFEFFFirst sentence. Second sentence.\n');

      final SubtitleTextSource source = await loadSubtitleTextFile(file.path);

      expect(source.fileName, 'lesson.txt');
      expect(source.hasTimings, isFalse);
      expect(
        source.lines.map((PlayerSubtitleLine line) => line.english),
        <String>['First sentence.', 'Second sentence.'],
      );
    });
  });
}
