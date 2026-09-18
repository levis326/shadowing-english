import 'dart:io';
import 'dart:math';

import 'package:common_learn_english/features/player/presentation/asr_subtitle_cache.dart';
import 'package:common_learn_english/features/player/presentation/asr_subtitle_job.dart';
import 'package:common_learn_english/features/player/presentation/asr_subtitle_service.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/player_subtitle_loader.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _word(String text, int startMs, int endMs) =>
    <String, Object?>{'text': text, 'startMs': startMs, 'endMs': endMs};

Map<String, Object?> _line(
  String english,
  List<Map<String, Object?>> words, {
  int startMs = 0,
  int endMs = 6000,
}) => <String, Object?>{
  'startMs': startMs,
  'endMs': endMs,
  'english': english,
  'chinese': '',
  'words': words,
};

Map<String, Object?> _chunk(List<Map<String, Object?>> lines) =>
    <String, Object?>{'version': 1, 'language': 'en', 'lines': lines};

void main() {
  test('punctuation-only and malformed lines are dropped instead of failing',
      () async {
    final Directory root = Directory.systemTemp.createTempSync('coverage-drop-');
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk = File('${root.path}/chunk.wav')..writeAsStringSync('a');
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async => _chunk(<Map<String, Object?>>[
            // 服务商偶尔会返回“只有标点”的行。
            _line(',', <Map<String, Object?>>[_word('.', 0, 300)], endMs: 300),
            // 词级文本与正文对不上的行（应该被重新合成，而不是让整段失败）。
            _line(
              'This is a proper sentence.',
              <Map<String, Object?>>[
                _word('wrong', 600, 900),
                _word('words', 900, 1200),
              ],
              startMs: 600,
              endMs: 3000,
            ),
            // 完全正常的行。
            _line(
              'Another fine line.',
              <Map<String, Object?>>[
                _word('Another', 3200, 3600),
                _word('fine', 3600, 3900),
                _word('line.', 3900, 4200),
              ],
              startMs: 3200,
              endMs: 4200,
            ),
          ]),
    );

    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: LearningSettingsState.defaults().copyWith(
        generateBilingualAsrSubtitles: false,
      ),
    );

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(raw);
    expect(lines, hasLength(2));
    expect(
      lines.map((PlayerSubtitleLine line) => line.english),
      <String>['This is a proper sentence.', 'Another fine line.'],
    );
    for (final PlayerSubtitleLine line in lines) {
      final String wordText = line.words
          .map((PlayerSubtitleWord word) => word.text)
          .join(' ');
      expect(
        wordText.replaceAll(RegExp('[^A-Za-z0-9]'), '').toLowerCase(),
        line.english.replaceAll(RegExp('[^A-Za-z0-9]'), '').toLowerCase(),
      );
      expect(line.words, isNotEmpty);
      for (final PlayerSubtitleWord word in line.words) {
        expect(word.endMs, greaterThan(word.startMs));
        expect(word.startMs, greaterThanOrEqualTo(line.startMs));
        expect(word.endMs, lessThanOrEqualTo(line.endMs));
      }
    }
  });

  test('fuzz: adversarial word data never breaks subtitle generation', () async {
    final Directory root = Directory.systemTemp.createTempSync('coverage-fuzz-');
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk = File('${root.path}/chunk.wav')..writeAsStringSync('a');
    final Random random = Random(20240911);
    final List<String> pool = <String>[
      'Hello',
      'there,',
      'my',
      'friend.',
      ',',
      '.',
      '',
      ' ',
      'HELLO',
      '1,000',
      '2020',
      'e-mail',
      "don't",
    ];
    final List<String> failures = <String>[];
    for (int round = 0; round < 200; round += 1) {
      final List<Map<String, Object?>> lines = <Map<String, Object?>>[
        // 保证有一段正常内容，模拟真实视频里的少量脏数据。
        _line(
          'A valid sentence here.',
          <Map<String, Object?>>[
            _word('A', 0, 100),
            _word('valid', 100, 300),
            _word('sentence', 300, 600),
            _word('here.', 600, 900),
          ],
          endMs: 900,
        ),
      ];
      final int extra = random.nextInt(3);
      int cursor = 1000;
      for (int i = 0; i < extra; i += 1) {
        final List<Map<String, Object?>> words = <Map<String, Object?>>[];
        final int wordCount = random.nextInt(5);
        int wordCursor = cursor;
        for (int w = 0; w < wordCount; w += 1) {
          final int duration = random.nextInt(300);
          words.add(
            _word(
              pool[random.nextInt(pool.length)],
              wordCursor,
              wordCursor + duration,
            ),
          );
          wordCursor += duration + random.nextInt(40) - 20;
        }
        final String english = <String>[
          for (int t = 0; t < 1 + random.nextInt(4); t += 1)
            pool[random.nextInt(pool.length)],
        ].where((String text) => text.trim().isNotEmpty).join(' ');
        if (english.trim().isEmpty) {
          continue;
        }
        lines.add(
          _line(
            english,
            words,
            startMs: cursor,
            endMs: cursor + max(wordCursor - cursor, 600),
          ),
        );
        cursor += 1200;
      }
      final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
        supportDirectory: () async => root,
        cache: AsrSubtitleCache(appSupportDirectory: () async => root),
        service: AsrSubtitleService(
          prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
            AsrAudioChunk(file: chunk, offsetMs: 0),
          ],
        ),
        cloudTranscribeChunk:
            ({
              required AsrAudioChunk chunk,
              required LearningSettingsState settings,
            }) async => _chunk(lines),
      );
      try {
        final String raw = await runner.run(
          episodeId: 'episode-$round',
          videoPath: video.path,
          settings: LearningSettingsState.defaults().copyWith(
            generateBilingualAsrSubtitles: false,
          ),
          forceRegenerate: true,
        );
        expect(parseSubtitleLines(raw), isNotEmpty);
      } catch (error) {
        failures.add('round=$round lines=$lines => $error');
      }
    }
    if (failures.isNotEmpty) {
      // ignore: avoid_print
      print('FUZZ ${failures.take(3).join('\nFUZZ ')}');
    }
    expect(failures, isEmpty);
  });

  test('split cue keeps separated punctuation out of its own subtitle', () async {
    final Directory root = Directory.systemTemp.createTempSync('coverage-split-');
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk = File('${root.path}/chunk.wav')..writeAsStringSync('a');
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async => _chunk(<Map<String, Object?>>[
            _line(
              'Hello there , my friend .',
              <Map<String, Object?>>[
                _word('Hello', 0, 300),
                _word('there', 300, 600),
                _word('my', 700, 900),
                _word('friend', 900, 1200),
              ],
              endMs: 1300,
            ),
          ]),
    );

    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: LearningSettingsState.defaults().copyWith(
        generateBilingualAsrSubtitles: false,
      ),
    );

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(raw);
    expect(lines, hasLength(2));
    expect(
      lines.map((PlayerSubtitleLine line) => line.english),
      <String>['Hello there ,', 'my friend .'],
    );
    for (final PlayerSubtitleLine line in lines) {
      expect(line.words, isNotEmpty);
    }
  });
}
