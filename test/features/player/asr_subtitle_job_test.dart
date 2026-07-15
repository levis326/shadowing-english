import 'dart:convert';
import 'dart:io';

import 'package:common_learn_english/features/player/presentation/asr_subtitle_cache.dart';
import 'package:common_learn_english/features/player/presentation/asr_subtitle_job.dart';
import 'package:common_learn_english/features/player/presentation/asr_subtitle_service.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/player_subtitle_loader.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'bilingual option fills missing Chinese with translation provider',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'asr-job-bilingual-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File video = File('${root.path}/lesson.mp4')
        ..writeAsStringSync('v');
      final File chunk = File('${root.path}/chunk.m4a')..writeAsStringSync('a');
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
            }) async => _chunkJson('Hello there', 1000),
        translateSentence:
            ({
              required String sentence,
              required LearningSettingsState settings,
            }) async => '你好。',
      );

      final String raw = await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: LearningSettingsState.defaults().copyWith(
          generateBilingualAsrSubtitles: true,
        ),
      );

      expect(parseSubtitleLines(raw).single.chinese, '你好。');
    },
  );

  test(
    'bilingual option validates translation settings before transcription',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'asr-job-bilingual-config-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File video = File('${root.path}/lesson.mp4')
        ..writeAsStringSync('v');

      await expectLater(
        const AsrSubtitleJobRunner().run(
          episodeId: 'episode-1',
          videoPath: video.path,
          settings: LearningSettingsState.defaults().copyWith(
            generateBilingualAsrSubtitles: true,
          ),
        ),
        throwsA(
          isA<AsrSubtitleGenerationException>().having(
            (AsrSubtitleGenerationException error) => error.message,
            'message',
            contains('填写 API Key'),
          ),
        ),
      );
    },
  );

  test('resume skips completed chunk files', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-resume-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk0 = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final File chunk1 = File('${root.path}/chunk1.m4a')..writeAsStringSync('1');
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk0, offsetMs: 0),
          AsrAudioChunk(file: chunk1, offsetMs: 300000),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async {
            return _chunkJson('chunk 1', chunk.offsetMs + 1000);
          },
    );
    final Directory jobDir = await runner.jobDirectory(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );
    await File('${jobDir.path}/chunks/00000.json')
        .create(recursive: true)
        .then((File file) => file.writeAsString(_rawChunk('chunk 0', 1000)));

    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(raw);
    expect(lines.map((PlayerSubtitleLine line) => line.english), <String>[
      'chunk 0',
      'chunk 1',
    ]);
  });

  test('empty chunks do not prevent other subtitles from completing', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-empty-chunk-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk0 = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final File chunk1 = File('${root.path}/chunk1.m4a')..writeAsStringSync('1');
    int calls = 0;
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk0, offsetMs: 0),
          AsrAudioChunk(file: chunk1, offsetMs: 58000),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async {
            calls += 1;
            return calls == 1
                ? <String, Object?>{
                    'version': 1,
                    'language': 'en',
                    'lines': const <Object?>[],
                  }
                : _chunkJson('recognized line', 59000);
          },
    );

    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );

    expect(calls, 2);
    expect(parseSubtitleLines(raw).single.english, 'recognized line');
  });

  test(
    'failed job does not write final cache until all chunks complete',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'asr-job-fail-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File video = File('${root.path}/lesson.mp4')
        ..writeAsStringSync('video');
      final File chunk0 = File('${root.path}/chunk0.m4a')
        ..writeAsStringSync('0');
      final File chunk1 = File('${root.path}/chunk1.m4a')
        ..writeAsStringSync('1');
      int calls = 0;
      final AsrSubtitleCache cache = AsrSubtitleCache(
        appSupportDirectory: () async => root,
      );
      final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
        supportDirectory: () async => root,
        cache: cache,
        service: AsrSubtitleService(
          prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
            AsrAudioChunk(file: chunk0, offsetMs: 0),
            AsrAudioChunk(file: chunk1, offsetMs: 300000),
          ],
        ),
        cloudTranscribeChunk:
            ({
              required AsrAudioChunk chunk,
              required LearningSettingsState settings,
            }) async {
              calls += 1;
              if (calls == 2) {
                throw StateError('asr failed');
              }
              return _chunkJson('chunk 0', 1000);
            },
      );

      await expectLater(
        runner.run(
          episodeId: 'episode-1',
          videoPath: video.path,
          settings: _settings(),
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        await cache.exists(episodeId: 'episode-1', videoPath: video.path),
        isFalse,
      );
    },
  );

  test('completed job writes final words json cache', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-complete-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk0 = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: cache,
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk0, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async {
            return _chunkJson('done', 1000);
          },
    );

    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );

    expect(
      await cache.read(episodeId: 'episode-1', videoPath: video.path),
      raw,
    );
    expect(parseSubtitleLines(raw).single.english, 'done');
    final Directory jobDir = await runner.jobDirectory(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );
    final Map<String, dynamic> report =
        jsonDecode(
              await File(
                '${jobDir.path}/subtitle_quality_report.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(report['finalStatus'], 'PASS');
    expect(report['chunks'], hasLength(1));
  });

  test('invalid final subtitle fails check and keeps cache empty', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-invalid-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk0 = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    int calls = 0;
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: cache,
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk0, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async {
            calls += 1;
            return _overlappingChunkJson();
          },
    );

    await expectLater(
      runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
      ),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('时间轴乱序或重叠过多'),
        ),
      ),
    );
    expect(
      await cache.exists(episodeId: 'episode-1', videoPath: video.path),
      isFalse,
    );
    expect(calls, 2);
    final Directory jobDir = await runner.jobDirectory(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );
    final Map<String, dynamic> report =
        jsonDecode(
              await File(
                '${jobDir.path}/subtitle_quality_report.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(report['finalStatus'], 'FAILED');
    expect(report['wordOverlap'], greaterThan(0));
    expect(report['sentenceOverlap'], greaterThan(0));
    final Map<String, dynamic> anomaly =
        (report['anomalies'] as List<dynamic>).first as Map<String, dynamic>;
    expect(anomaly, containsPair('provider', _settings().asrProvider));
    expect(anomaly, containsPair('sourceChunk', 0));
  });

  test('merge sorts, deduplicates, and repairs small overlaps', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-normalize-timeline-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
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
              _chunkLine('second line', 1740),
              _chunkLine('first line', 1000),
              _chunkLine('first line', 1050),
            ],
          },
    );

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(
      await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
      ),
    );

    expect(lines.map((PlayerSubtitleLine line) => line.english), <String>[
      'first line',
      'second line',
    ]);
    expect(lines.map((PlayerSubtitleLine line) => line.startMs), <int>[
      1000,
      2000,
    ]);
  });

  test('invalid chunk is retried once before finishing the job', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-retry-invalid-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    int calls = 0;
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
          }) async {
            calls += 1;
            return calls == 1
                ? _overlappingChunkJson()
                : _chunkJson('retried subtitle', 1000);
          },
    );

    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );

    expect(calls, 2);
    expect(parseSubtitleLines(raw).single.english, 'retried subtitle');
  });

  test('final subtitle without word timestamps fails check', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-no-words-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk0 = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: cache,
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk0, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async {
            return _chunkJsonWithoutWords('no words', 1000);
          },
    );

    await expectLater(
      runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
      ),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('未返回词级时间戳'),
        ),
      ),
    );
    expect(
      await cache.exists(episodeId: 'episode-1', videoPath: video.path),
      isFalse,
    );
  });

  test('progress follows recognized video timestamp', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-progress-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk0 = File('${root.path}/chunk0.wav')..writeAsStringSync('0');
    final File chunk1 = File('${root.path}/chunk1.wav')..writeAsStringSync('1');
    final List<AsrSubtitleProgress> progress = <AsrSubtitleProgress>[];
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk0, offsetMs: 0),
          AsrAudioChunk(file: chunk1, offsetMs: 60000),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async {
            return _chunkJson('chunk', chunk.offsetMs + 30000);
          },
    );

    await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
      onProgress: progress.add,
    );

    expect(progress.last.label, '已识别到 1:31 / 2:00');
    expect(progress.last.value, closeTo(91000 / 120000, 0.001));
    expect(progress.last.previewText, 'chunk');
  });
}

LearningSettingsState _settings() {
  return LearningSettingsState.defaults().copyWith(
    asrApiKey: 'demo-key',
    asrBaseUrl: 'https://api.example.com/v1',
    asrModel: 'whisper-1',
  );
}

Map<String, Object?> _chunkJson(String english, int startMs) {
  final List<String> words = english
      .split(RegExp(r'\s+'))
      .where((String word) => word.isNotEmpty)
      .toList(growable: false);
  final int wordMs = (1000 / words.length).round();
  return <String, Object?>{
    'version': 1,
    'language': 'en',
    'lines': <Map<String, Object?>>[
      <String, Object?>{
        'startMs': startMs,
        'endMs': startMs + 1000,
        'english': english,
        'chinese': '',
        'words': words
            .asMap()
            .entries
            .map((MapEntry<int, String> entry) {
              final int wordStartMs = startMs + entry.key * wordMs;
              return <String, Object?>{
                'text': entry.value,
                'startMs': wordStartMs,
                'endMs': entry.key == words.length - 1
                    ? startMs + 1000
                    : wordStartMs + wordMs,
              };
            })
            .toList(growable: false),
      },
    ],
  };
}

Map<String, Object?> _chunkJsonWithoutWords(String english, int startMs) {
  return <String, Object?>{
    'version': 1,
    'language': 'en',
    'lines': <Map<String, Object?>>[
      <String, Object?>{
        'startMs': startMs,
        'endMs': startMs + 1000,
        'english': english,
        'chinese': '',
        'words': const <Object?>[],
      },
    ],
  };
}

Map<String, Object?> _chunkLine(String english, int startMs) {
  return (_chunkJson(english, startMs)['lines']! as List<Map<String, Object?>>)
      .single;
}

Map<String, Object?> _overlappingChunkJson() {
  return <String, Object?>{
    'version': 1,
    'language': 'en',
    'lines': <Map<String, Object?>>[
      <String, Object?>{
        'startMs': 1000,
        'endMs': 3000,
        'english': 'first line',
        'chinese': '',
        'words': const <Map<String, Object?>>[
          <String, Object?>{'text': 'first', 'startMs': 1000, 'endMs': 2000},
          <String, Object?>{'text': 'line', 'startMs': 2000, 'endMs': 3000},
        ],
      },
      <String, Object?>{
        'startMs': 2000,
        'endMs': 4000,
        'english': 'second line',
        'chinese': '',
        'words': const <Map<String, Object?>>[
          <String, Object?>{'text': 'second', 'startMs': 2000, 'endMs': 3000},
          <String, Object?>{'text': 'line', 'startMs': 3000, 'endMs': 4000},
        ],
      },
    ],
  };
}

String _rawChunk(String english, int startMs) {
  return const JsonEncoder().convert(_chunkJson(english, startMs));
}
