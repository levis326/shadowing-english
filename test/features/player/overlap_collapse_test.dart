import 'dart:io';

import 'package:common_learn_english/features/player/presentation/asr_subtitle_cache.dart';
import 'package:common_learn_english/features/player/presentation/asr_subtitle_job.dart';
import 'package:common_learn_english/features/player/presentation/asr_subtitle_service.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/player_subtitle_loader.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a nested/duplicated segment keeps a playable duration', () async {
    final Directory root = Directory.systemTemp.createTempSync('overlap-');
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
          }) async => <String, Object?>{
            'version': 1,
            'language': 'en',
            'lines': <Map<String, Object?>>[
              // 长段（例如 whisper 在音乐上的一长段幻觉/重复）。
              <String, Object?>{
                'startMs': 0,
                'endMs': 20000,
                'english': 'First long segment here.',
                'chinese': '',
                'words': <Map<String, Object?>>[
                  <String, Object?>{'text': 'First', 'startMs': 0, 'endMs': 3000},
                  <String, Object?>{'text': 'long', 'startMs': 3000, 'endMs': 6000},
                  <String, Object?>{'text': 'segment', 'startMs': 6000, 'endMs': 9000},
                  <String, Object?>{'text': 'here.', 'startMs': 9000, 'endMs': 12000},
                ],
              },
              // 完全落在上一段内部的一句（真实识别里很常见）。
              <String, Object?>{
                'startMs': 4000,
                'endMs': 8000,
                'english': 'A nested sentence.',
                'chinese': '',
                'words': <Map<String, Object?>>[
                  <String, Object?>{'text': 'A', 'startMs': 4000, 'endMs': 5000},
                  <String, Object?>{'text': 'nested', 'startMs': 5000, 'endMs': 6500},
                  <String, Object?>{'text': 'sentence.', 'startMs': 6500, 'endMs': 8000},
                ],
              },
            ],
          },
    );

    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: LearningSettingsState.defaults().copyWith(
        generateBilingualAsrSubtitles: false,
      ),
    );

    for (final PlayerSubtitleLine line in parseSubtitleLines(raw)) {
      // ignore: avoid_print
      print('OVERLAP ${line.startMs}-${line.endMs} ${line.english}');
      expect(
        line.endMs - line.startMs,
        greaterThanOrEqualTo(250),
        reason: '「${line.english}」被压成了不可播放的片段',
      );
    }
  });

  test('degenerate 1ms line is extended so clicking it plays audio', () async {
    final Directory root = Directory.systemTemp.createTempSync('degenerate-');
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk = File('${root.path}/chunk.wav')..writeAsStringSync('a');
    final List<Map<String, Object?>> lines = <Map<String, Object?>>[
      <String, Object?>{
        'startMs': 0,
        'endMs': 8000,
        'english': 'The first sentence is long enough.',
        'chinese': '',
        'words': <Map<String, Object?>>[
          <String, Object?>{'text': 'The', 'startMs': 0, 'endMs': 500},
          <String, Object?>{'text': 'first', 'startMs': 500, 'endMs': 1200},
          <String, Object?>{'text': 'sentence', 'startMs': 1200, 'endMs': 2000},
          <String, Object?>{'text': 'is', 'startMs': 2000, 'endMs': 2400},
          <String, Object?>{'text': 'long', 'startMs': 2400, 'endMs': 3000},
          <String, Object?>{'text': 'enough.', 'startMs': 3000, 'endMs': 8000},
        ],
      },
      <String, Object?>{
        // 被上一段完全包住的一句：旧逻辑会把它压成 1ms。
        'startMs': 100,
        'endMs': 200,
        'english': 'Tiny nested line.',
        'chinese': '',
        'words': <Map<String, Object?>>[
          <String, Object?>{'text': 'Tiny', 'startMs': 100, 'endMs': 130},
          <String, Object?>{'text': 'nested', 'startMs': 130, 'endMs': 165},
          <String, Object?>{'text': 'line.', 'startMs': 165, 'endMs': 200},
        ],
      },
    ];
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
          }) async => <String, Object?>{'version': 1, 'language': 'en', 'lines': lines},
    );

    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: LearningSettingsState.defaults().copyWith(
        generateBilingualAsrSubtitles: false,
      ),
    );

    final List<PlayerSubtitleLine> parsed = parseSubtitleLines(raw);
    expect(parsed, hasLength(2));
    for (final PlayerSubtitleLine line in parsed) {
      expect(
        line.endMs - line.startMs,
        greaterThanOrEqualTo(400),
        reason: '「${line.english}」时长过短，点击会立刻暂停',
      );
    }
    // 补足后每个词条仍然落在句子范围内。
    for (final PlayerSubtitleLine line in parsed) {
      for (final PlayerSubtitleWord word in line.words) {
        expect(word.startMs, greaterThanOrEqualTo(line.startMs));
        expect(word.endMs, lessThanOrEqualTo(line.endMs));
      }
    }
  });

  test('whisper loop and credit hallucinations are dropped', () async {
    final Directory root = Directory.systemTemp.createTempSync('hallucination-');
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk = File('${root.path}/chunk.wav')..writeAsStringSync('a');
    Map<String, Object?> wordLine(
      String text,
      int startMs,
      int endMs,
    ) {
      final List<String> words = text.split(' ');
      final int wordMs = (endMs - startMs) ~/ words.length;
      return <String, Object?>{
        'startMs': startMs,
        'endMs': endMs,
        'english': text,
        'chinese': '',
        'words': <Map<String, Object?>>[
          for (int index = 0; index < words.length; index += 1)
            <String, Object?>{
              'text': words[index],
              'startMs': startMs + index * wordMs,
              'endMs': index == words.length - 1
                  ? endMs
                  : startMs + (index + 1) * wordMs,
            },
        ],
      };
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
          }) async => <String, Object?>{
            'version': 1,
            'language': 'en',
            'lines': <Map<String, Object?>>[
              wordLine('John Smith.', 0, 2000),
              wordLine('John Smith.', 2000, 4000),
              wordLine('John Smith.', 4000, 6000),
              wordLine('Subtitles by Amara.org', 6000, 8000),
              wordLine('This is the real lesson content.', 28000, 32000),
            ],
          },
    );

    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: LearningSettingsState.defaults().copyWith(
        generateBilingualAsrSubtitles: false,
      ),
    );

    final List<PlayerSubtitleLine> parsed = parseSubtitleLines(raw);
    // 连续重复的人名幻觉只保留第一句，字幕组套话丢掉。
    expect(
      parsed.map((PlayerSubtitleLine line) => line.english),
      <String>['John Smith.', 'This is the real lesson content.'],
    );
  });
}
