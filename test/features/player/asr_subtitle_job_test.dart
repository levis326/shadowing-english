import 'dart:async';
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
    'reference subtitles keep authoritative text while ASR supplies word timings',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'asr-job-reference-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File video = File('${root.path}/lesson.mp4')
        ..writeAsStringSync('v');
      final File chunk = File('${root.path}/chunk.m4a')..writeAsStringSync('a');
      final AsrSubtitleCache cache = AsrSubtitleCache(
        appSupportDirectory: () async => root,
      );
      final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
        supportDirectory: () async => root,
        cache: cache,
        service: AsrSubtitleService(
          prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
            AsrAudioChunk(file: chunk, offsetMs: 0),
          ],
        ),
        cloudTranscribeChunk:
            ({
              required AsrAudioChunk chunk,
              required LearningSettingsState settings,
            }) async => _chunkJson('I like go home', 1000),
      );

      final String raw = await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings().copyWith(generateBilingualAsrSubtitles: true),
        referenceSignatureOverride: 'original-reference-signature',
        referenceSubtitleLines: const <PlayerSubtitleLine>[
          PlayerSubtitleLine(
            startTime: '00:01',
            english: 'I would like to go home.',
            chinese: '我想回家。',
            startMs: 1000,
            endMs: 4000,
          ),
        ],
      );

      final PlayerSubtitleLine line = parseSubtitleLines(raw).single;
      expect(line.english, 'I would like to go home.');
      expect(line.chinese, '我想回家。');
      expect(subtitleGenerationWarning(raw), isNull);
      final Map<String, dynamic> decoded =
          jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['referenceLines'], isA<List<dynamic>>());
      final Map<String, dynamic> storedReference =
          (decoded['referenceLines'] as List<dynamic>).single
              as Map<String, dynamic>;
      expect(storedReference['english'], 'I would like to go home.');
      expect(storedReference['chinese'], '我想回家。');
      expect(line.words.map((PlayerSubtitleWord word) => word.text), <String>[
        'I',
        'would',
        'like',
        'to',
        'go',
        'home',
      ]);
      expect(
        await cache.read(
          episodeId: 'episode-1',
          videoPath: video.path,
          settings: _settings().copyWith(generateBilingualAsrSubtitles: true),
          referenceSignature: 'original-reference-signature',
        ),
        isNotNull,
      );
    },
  );

  test('reference subtitle overlap does not fail final validation', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-reference-overlap-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')..writeAsStringSync('v');
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
          }) async => _chunkJson('First line', 1000),
    );

    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
      referenceSubtitleLines: const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'First line.',
          chinese: '',
          startMs: 1000,
          endMs: 2500,
        ),
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Second line.',
          chinese: '',
          startMs: 1800,
          endMs: 3200,
        ),
      ],
    );

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(raw);
    expect(lines, hasLength(2));
    expect(lines.last.startMs, lessThan(lines.first.endMs - 250));
  });

  test('transcription retries after a transient provider failure', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-provider-retry-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')..writeAsStringSync('v');
    final File chunk = File('${root.path}/chunk.m4a')..writeAsStringSync('a');
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
            if (calls == 1) throw StateError('temporary-provider-error');
            return _chunkJson('Recovered subtitle', 1000);
          },
    );

    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );

    expect(calls, 2);
    expect(parseSubtitleLines(raw).single.english, 'Recovered subtitle');
  });

  test(
    'reference subtitles survive persistent transcription failure',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'asr-job-reference-provider-fallback-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File video = File('${root.path}/lesson.mp4')
        ..writeAsStringSync('v');
      final File chunk = File('${root.path}/chunk.m4a')..writeAsStringSync('a');
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
              throw StateError('provider-unavailable');
            },
      );

      final String raw = await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
        referenceSubtitleLines: const <PlayerSubtitleLine>[
          PlayerSubtitleLine(
            startTime: '00:01',
            english: 'Authoritative subtitle.',
            chinese: '权威字幕。',
            startMs: 1000,
            endMs: 3000,
          ),
        ],
      );

      expect(calls, 2);
      final PlayerSubtitleLine line = parseSubtitleLines(raw).single;
      expect(line.english, 'Authoritative subtitle.');
      expect(line.words, hasLength(2));
      expect(subtitleGenerationWarning(raw), contains('本地估算'));
    },
  );

  test('reference subtitles survive audio preparation failure', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-reference-audio-fallback-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')..writeAsStringSync('v');
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async =>
            throw StateError('audio-tools-unavailable'),
      ),
    );

    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
      referenceSubtitleLines: const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Local fallback works.',
          chinese: '',
          startMs: 1000,
          endMs: 3000,
        ),
      ],
    );

    expect(parseSubtitleLines(raw).single.english, 'Local fallback works.');
    expect(subtitleGenerationWarning(raw), contains('本地估算'));
  });

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
          translationProvider: 'OpenAI',
        ),
      );

      expect(parseSubtitleLines(raw).single.chinese, '你好。');
    },
  );

  test(
    'local NLLB provider translates all pending lines in a single batch',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'asr-job-nllb-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File video = File('${root.path}/lesson.mp4')
        ..writeAsStringSync('v');
      final File chunk = File('${root.path}/chunk.m4a')..writeAsStringSync('a');
      final List<String> batched = <String>[];
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
        translateBatch:
            ({
              required List<String> sentences,
              required LearningSettingsState settings,
              required String sourceLanguage,
            }) async {
              batched.addAll(sentences);
              return sentences.map((String _) => '你好。').toList(growable: false);
            },
      );

      final String raw = await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: LearningSettingsState.defaults().copyWith(
          generateBilingualAsrSubtitles: true,
          translationProvider: localNllbTranslationProviderName,
        ),
      );

      expect(batched, <String>['Hello there']);
      expect(parseSubtitleLines(raw).single.chinese, '你好。');
    },
  );

  test(
    'missing translation settings keep the generated English subtitles',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'asr-job-bilingual-config-',
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
      );

      final String raw = await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: LearningSettingsState.defaults().copyWith(
          generateBilingualAsrSubtitles: true,
          translationProvider: 'OpenAI',
        ),
      );

      expect(parseSubtitleLines(raw).single.english, 'Hello there');
      expect(subtitleGenerationWarning(raw), contains('填写 API Key'));
    },
  );

  test('bilingual translation resumes from sentence checkpoint', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-translation-resume-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk = File('${root.path}/chunk.m4a')
      ..writeAsStringSync('audio');
    final Map<String, int> calls = <String, int>{};
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
          }) async => _twoLineChunkJson(),
      translateSentence:
          ({
            required String sentence,
            required LearningSettingsState settings,
          }) async {
            calls.update(sentence, (int count) => count + 1, ifAbsent: () => 1);
            if (sentence == 'second line.' && calls[sentence] == 1) return null;
            return '翻译：$sentence';
          },
    );
    final LearningSettingsState settings = _settings().copyWith(
      generateBilingualAsrSubtitles: true,
      translationProvider: 'OpenAI',
    );

    final String partialRaw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: settings,
    );
    expect(subtitleGenerationWarning(partialRaw), isNotNull);
    expect(
      parseSubtitleLines(
        partialRaw,
      ).map((PlayerSubtitleLine line) => line.chinese),
      <String>['翻译：first line.', ''],
    );
    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: settings,
    );

    expect(calls['first line.'], 1);
    expect(calls['second line.'], 2);
    expect(
      parseSubtitleLines(raw).map((PlayerSubtitleLine line) => line.chinese),
      <String>['翻译：first line.', '翻译：second line.'],
    );
    expect(subtitleGenerationWarning(raw), isNull);
  });

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
            return _chunkJson('chunk 1.', chunk.offsetMs + 1000);
          },
    );
    final Directory jobDir = await runner.jobDirectory(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );
    await File('${jobDir.path}/chunks/00000.json')
        .create(recursive: true)
        .then((File file) => file.writeAsString(_rawChunk('chunk 0.', 1000)));

    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(raw);
    expect(lines.map((PlayerSubtitleLine line) => line.english), <String>[
      'chunk 0.',
      'chunk 1.',
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
              if (chunk.offsetMs == 300000) {
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

      expect(calls, 3);

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

  test('overlapping final subtitle is repaired and cached', () async {
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

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(
      await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
      ),
    );
    expect(lines, hasLength(2));
    expect(lines.last.startMs, lines.first.endMs);
    expect(
      await cache.exists(episodeId: 'episode-1', videoPath: video.path),
      isTrue,
    );
    expect(calls, 1);
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
    expect(report['repairCount'], greaterThan(0));
    expect(report['sentenceOverlap'], greaterThan(0));
    final Map<String, dynamic> anomaly =
        (report['anomalies'] as List<dynamic>).first as Map<String, dynamic>;
    expect(anomaly, containsPair('provider', _settings().asrProvider));
    expect(anomaly, containsPair('sourceChunk', 0));
    final AsrSubtitleRepairSummary repairSummary = await runner
        .readRepairSummary(
          episodeId: 'episode-1',
          videoPath: video.path,
          settings: _settings(),
        );
    expect(repairSummary.itemCount, greaterThan(0));
    expect(repairSummary.appendTo('AI 字幕已生成'), contains('已自动修复'));
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
              _chunkLine('second line.', 1740),
              _chunkLine('first line.', 1000),
              _chunkLine('first line.', 1050),
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
      'first line.',
      'second line.',
    ]);
    expect(lines.map((PlayerSubtitleLine line) => line.startMs), <int>[
      1000,
      2000,
    ]);
  });

  test(
    'merge trims a previous chunk word that overruns the next chunk',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'asr-job-chunk-overrun-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File video = File('${root.path}/lesson.mp4')
        ..writeAsStringSync('video');
      final File chunk0 = File('${root.path}/chunk0.m4a')
        ..writeAsStringSync('0');
      final File chunk1 = File('${root.path}/chunk1.m4a')
        ..writeAsStringSync('1');
      final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
        supportDirectory: () async => root,
        cache: AsrSubtitleCache(appSupportDirectory: () async => root),
        service: AsrSubtitleService(
          prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
            AsrAudioChunk(file: chunk0, offsetMs: 0),
            AsrAudioChunk(file: chunk1, offsetMs: 290000),
          ],
        ),
        cloudTranscribeChunk:
            ({
              required AsrAudioChunk chunk,
              required LearningSettingsState settings,
            }) async => chunk.file.path == chunk0.path
            ? <String, Object?>{
                'version': 1,
                'language': 'en',
                'lines': <Map<String, Object?>>[
                  <String, Object?>{
                    'startMs': 273068,
                    'endMs': 294108,
                    'english': 'Ha ha.',
                    'chinese': '',
                    'words': <Map<String, Object?>>[
                      <String, Object?>{
                        'text': 'Ha',
                        'startMs': 273068,
                        'endMs': 273488,
                      },
                      <String, Object?>{
                        'text': 'ha',
                        'startMs': 278508,
                        'endMs': 294108,
                      },
                    ],
                  },
                ],
              }
            : <String, Object?>{
                'version': 1,
                'language': 'en',
                'lines': <Map<String, Object?>>[
                  _chunkLine('Peppa Pig.', 291000),
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
        'Ha ha.',
        'Peppa Pig.',
      ]);
      expect(lines.first.endMs, 290000);
      expect(lines.first.words.last.endMs, 290000);
      expect(lines.last.startMs, 291000);
    },
  );

  test('merges sentence fragments across chunk boundaries', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-sentence-merge-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')..writeAsStringSync('v');
    final File chunk0 = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final File chunk1 = File('${root.path}/chunk1.m4a')..writeAsStringSync('1');
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
          }) async => chunk.file.path == chunk0.path
          ? _chunkJson('I want to learn', 1000)
          : _chunkJson('English.', 59000),
    );

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(
      await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
      ),
    );

    expect(lines, hasLength(1));
    expect(lines.single.english, 'I want to learn English.');
    expect(lines.single.startMs, 1000);
  });

  test('starts a new subtitle line after semicolons and other punctuation', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-semicolon-split-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')..writeAsStringSync('v');
    final File chunk0 = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final File chunk1 = File('${root.path}/chunk1.m4a')..writeAsStringSync('1');
    final File chunk2 = File('${root.path}/chunk2.m4a')..writeAsStringSync('2');
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk0, offsetMs: 0),
          AsrAudioChunk(file: chunk1, offsetMs: 58000),
          AsrAudioChunk(file: chunk2, offsetMs: 116000),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async => chunk.file.path == chunk0.path
          ? _chunkJson('First part;', 1000)
          : chunk.file.path == chunk1.path
          ? _chunkJson('Second part?', 59000)
          : _chunkJson('Final part.', 117000),
    );

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(
      await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
      ),
    );

    // 分号、问号、句号结尾的片段各自成行，不合并。
    expect(lines, hasLength(3));
    expect(lines[0].english, 'First part;');
    expect(lines[1].english, 'Second part?');
    expect(lines[2].english, 'Final part.');
  });

  test('splits one long recognized line into separate subtitle cues', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-long-line-split-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')..writeAsStringSync('v');
    final File chunk0 = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk0, offsetMs: 0),
        ],
      ),
      // 服务商把多个句子识别成同一行（长字幕）。
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async => _chunkJson(
            'Hello world; This is a test. Final question?',
            1000,
          ),
    );

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(
      await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
      ),
    );

    // 遇到分号、句号、问号分别生成一行新字幕，避免一句字幕过长。
    expect(lines, hasLength(3));
    expect(lines[0].english, 'Hello world;');
    expect(lines[1].english, 'This is a test.');
    expect(lines[2].english, 'Final question?');
    // 每一行都带有对应的词级时间戳。
    expect(
      lines[0].words.map((PlayerSubtitleWord w) => w.text).join(' '),
      'Hello world;',
    );
    expect(
      lines[1].words.map((PlayerSubtitleWord w) => w.text).join(' '),
      'This is a test.',
    );
    expect(
      lines[2].words.map((PlayerSubtitleWord w) => w.text).join(' '),
      'Final question?',
    );
    // 时间轴连续且不重叠。
    expect(lines[0].startMs, lessThan(lines[0].endMs));
    expect(lines[0].endMs, lessThanOrEqualTo(lines[1].startMs));
    expect(lines[1].endMs, lessThanOrEqualTo(lines[2].startMs));
  });

  test('splits reference-aligned lines by comma, period, and question mark', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-clause-split-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')..writeAsStringSync('v');
    final File chunk0 = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk0, offsetMs: 0),
        ],
      ),
      // 参考字幕对齐后的词不携带标点（与真实流程一致），
      // 长行必须在逗号、句号、问号处拆开。
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async => _chunkJsonWithStrippedWords(
            "And I'm Beth. Menstruation, or periods. Final question?",
            1000,
          ),
    );

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(
      await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
      ),
    );

    expect(lines, hasLength(4));
    expect(lines[0].english, "And I'm Beth.");
    expect(lines[1].english, 'Menstruation,');
    expect(lines[2].english, 'or periods.');
    expect(lines[3].english, 'Final question?');
    // 每行携带对应的词级时间戳（词文本无标点，行文本有标点）。
    expect(
      lines[0].words.map((PlayerSubtitleWord w) => w.text).join(' '),
      "And I'm Beth",
    );
    expect(
      lines[1].words.map((PlayerSubtitleWord w) => w.text).join(' '),
      'Menstruation',
    );
    expect(lines[0].endMs, lessThanOrEqualTo(lines[1].startMs));
    expect(lines[1].endMs, lessThanOrEqualTo(lines[2].startMs));
  });

  test('split cues are contiguous so clicked lines play their full audio', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-contiguous-split-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')..writeAsStringSync('v');
    final File chunk0 = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk0, offsetMs: 0),
        ],
      ),
      // 词尾时间戳偏早（真实 ASR/参考估计常见）："Unfortunately" 实际发音
      // 到 1900ms 左右，但词条 endMs 只到 1400ms，后面词从 1950ms 开始。
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async => <String, Object?>{
            'version': 1,
            'language': 'en',
            'lines': <Map<String, Object?>>[
              <String, Object?>{
                'startMs': 1000,
                'endMs': 2400,
                'english': 'Unfortunately, the news.',
                'chinese': '',
                'words': <Map<String, Object?>>[
                  <String, Object?>{
                    'text': 'Unfortunately',
                    'startMs': 1000,
                    'endMs': 1400,
                  },
                  <String, Object?>{
                    'text': 'the',
                    'startMs': 1950,
                    'endMs': 2100,
                  },
                  <String, Object?>{
                    'text': 'news',
                    'startMs': 2100,
                    'endMs': 2400,
                  },
                ],
              },
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

    expect(lines, hasLength(2));
    expect(lines[0].english, 'Unfortunately,');
    expect(lines[1].english, 'the news.');
    // 首尾相接：点击 "Unfortunately," 会播放到下一行起点（覆盖被低估的
    // 词尾音节），点击下一行则从它自己的词开始。
    expect(lines[0].startMs, 1000);
    expect(lines[0].endMs, lines[1].startMs);
    expect(lines[1].startMs, 1950);
    expect(lines[1].endMs, 2400);
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
                ? _chunkJsonWithoutWords('', 1000)
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

  test('missing word timestamps are synthesized from usable text', () async {
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

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(
      await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
      ),
    );
    expect(lines.single.english, 'no words');
    expect(
      lines.single.words.map((PlayerSubtitleWord word) => word.text),
      <String>['no', 'words'],
    );
    expect(
      await cache.exists(episodeId: 'episode-1', videoPath: video.path),
      isTrue,
    );
  });

  test('fully out-of-range timestamps are rebuilt inside the chunk', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-out-of-range-',
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
          }) async => _chunkJson('outside range', 70000),
    );

    final PlayerSubtitleLine line = parseSubtitleLines(
      await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
      ),
    ).single;

    expect(line.english, 'outside range');
    expect(line.startMs, 0);
    expect(line.endMs, lessThanOrEqualTo(58000));
    expect(line.words, hasLength(2));
  });

  test('valid short word timestamp is preserved', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-short-word-',
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
          }) async {
            final Map<String, Object?> result = _chunkJson('I agree', 1000);
            final Map<String, Object?> line =
                (result['lines']! as List<Map<String, Object?>>).single;
            final List<Map<String, Object?>> words =
                line['words']! as List<Map<String, Object?>>;
            words.first['endMs'] = 1020;
            words.last['startMs'] = 1020;
            return result;
          },
    );

    final String raw = await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );

    expect(
      parseSubtitleLines(
        raw,
      ).single.words.map((PlayerSubtitleWord word) => word.text),
      <String>['I', 'agree'],
    );
  });

  test('large word overlap is repaired locally', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-word-overlap-',
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
              <String, Object?>{
                'startMs': 1000,
                'endMs': 2200,
                'english': 'one two',
                'chinese': '',
                'words': const <Map<String, Object?>>[
                  <String, Object?>{
                    'text': 'one',
                    'startMs': 1000,
                    'endMs': 2000,
                  },
                  <String, Object?>{
                    'text': 'two',
                    'startMs': 1200,
                    'endMs': 2200,
                  },
                ],
              },
            ],
          },
    );

    final PlayerSubtitleLine line = parseSubtitleLines(
      await runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
      ),
    ).single;
    expect(line.words.first.endMs, line.words.last.startMs);
  });

  test('cancellation stops before the next cloud chunk', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-cancel-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk0 = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final File chunk1 = File('${root.path}/chunk1.m4a')..writeAsStringSync('1');
    final AsrSubtitleCancellationToken cancellationToken =
        AsrSubtitleCancellationToken();
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
            return _chunkJson('chunk', chunk.offsetMs + 1000);
          },
    );

    await expectLater(
      runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
        cancellationToken: cancellationToken,
        onProgress: (AsrSubtitleProgress progress) {
          if (progress.completedChunks == 1) cancellationToken.cancel();
        },
      ),
      throwsA(isA<AsrSubtitleGenerationException>()),
    );
    expect(calls, 1);
  });

  test('same video cannot start two generation jobs', () async {
    final Directory root = Directory.systemTemp.createTempSync('asr-job-lock-');
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final Completer<void> started = Completer<void>();
    final Completer<void> release = Completer<void>();
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
            if (!started.isCompleted) started.complete();
            await release.future;
            return _chunkJson('locked', 1000);
          },
    );

    final Future<String> first = runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );
    await started.future;
    await expectLater(
      runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
      ),
      throwsA(
        isA<AsrSubtitleGenerationException>().having(
          (AsrSubtitleGenerationException error) => error.message,
          'message',
          contains('正在生成'),
        ),
      ),
    );
    release.complete();
    await first;
  });

  test('force regeneration ignores completed chunk checkpoints', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-force-regenerate-',
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
            return _chunkJson('generation $calls', 1000);
          },
    );

    await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );
    await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
      forceRegenerate: true,
    );

    expect(calls, 2);
  });

  test('failed force regeneration keeps the previous final cache', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-force-failure-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk = File('${root.path}/chunk0.m4a')..writeAsStringSync('0');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    final LearningSettingsState settings = _settings();
    final String previous = _rawChunk('old subtitle', 1000);
    await cache.write(
      episodeId: 'episode-1',
      videoPath: video.path,
      content: previous,
      settings: settings,
    );
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: cache,
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async => _chunkJsonWithoutWords('', 1000),
    );

    await expectLater(
      runner.run(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: settings,
        forceRegenerate: true,
      ),
      throwsA(anything),
    );

    expect(
      await cache.read(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: settings,
      ),
      previous,
    );
  });

  test('temporary audio chunks are cleaned after generation', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-temp-cleanup-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final Directory chunkDir = Directory('${root.path}/cle_asr_test')
      ..createSync();
    final File chunk = File('${chunkDir.path}/chunk0.m4a')
      ..writeAsStringSync('0');
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
          }) async => _chunkJson('cleaned', 1000),
    );

    await runner.run(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: _settings(),
    );

    expect(chunkDir.existsSync(), isFalse);
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

    final AsrSubtitleProgress chunkProgress = progress.lastWhere(
      (AsrSubtitleProgress item) => item.previewText == 'chunk',
    );
    expect(chunkProgress.label, '已识别到 1:31 / 2:00');
    expect(chunkProgress.value, closeTo(91000 / 120000, 0.001));
    expect(chunkProgress.previewText, 'chunk');
    expect(progress.last.label, '正在校准词级时间轴...');
  });

  test(
    'regenerates only the selected line and persists the replacement',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'asr-job-regenerate-line-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File video = File('${root.path}/lesson.mp4')
        ..writeAsStringSync('v');
      final File chunk = File('${root.path}/chunk.m4a')..writeAsStringSync('a');
      final AsrSubtitleCache cache = AsrSubtitleCache(
        appSupportDirectory: () async => root,
      );
      const List<PlayerSubtitleLine> original = <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Keep this line.',
          chinese: '保留这一句。',
          startMs: 1000,
          endMs: 2000,
        ),
        PlayerSubtitleLine(
          startTime: '00:03',
          english: 'Wrong sentence.',
          chinese: '错误的句子。',
          startMs: 3000,
          endMs: 4500,
        ),
      ];
      final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
        supportDirectory: () async => root,
        cache: cache,
        service: AsrSubtitleService(
          prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
            AsrAudioChunk(file: chunk, offsetMs: 0),
          ],
        ),
        cloudTranscribeChunk:
            ({
              required AsrAudioChunk chunk,
              required LearningSettingsState settings,
            }) async => _chunkJson('Correct sentence.', 3200),
      );

      final AsrRegeneratedLineResult result = await runner.regenerateLine(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
        currentLines: original,
        lineIndex: 1,
      );

      expect(result.line.english, 'Correct sentence.');
      expect(result.line.startMs, 3000);
      expect(result.line.endMs, 4500);
      expect(result.line.words, hasLength(2));
      final String cached = (await cache.read(
        episodeId: 'episode-1',
        videoPath: video.path,
      ))!;
      final List<PlayerSubtitleLine> cachedLines = parseSubtitleLines(cached);
      expect(cachedLines.first.english, 'Keep this line.');
      expect(cachedLines.last.english, 'Correct sentence.');
    },
  );

  test('keeps the cached sentence when line regeneration fails', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-job-regenerate-line-failure-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')..writeAsStringSync('v');
    final File chunk = File('${root.path}/chunk.m4a')..writeAsStringSync('a');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    const String cachedBefore =
        '{"version":1,"lines":[{"startMs":3000,"endMs":4500,'
        '"english":"Original sentence.","chinese":"原句。","words":[]}]}';
    await cache.write(
      episodeId: 'episode-1',
      videoPath: video.path,
      content: cachedBefore,
    );
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: cache,
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async => <AsrAudioChunk>[
          AsrAudioChunk(file: chunk, offsetMs: 0),
        ],
      ),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async => throw StateError('provider-down'),
    );

    await expectLater(
      runner.regenerateLine(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: _settings(),
        currentLines: const <PlayerSubtitleLine>[
          PlayerSubtitleLine(
            startTime: '00:03',
            english: 'Original sentence.',
            chinese: '原句。',
            startMs: 3000,
            endMs: 4500,
          ),
        ],
        lineIndex: 0,
      ),
      throwsA(isA<AsrSubtitleGenerationException>()),
    );
    expect(
      await cache.read(episodeId: 'episode-1', videoPath: video.path),
      cachedBefore,
    );
  });
}

LearningSettingsState _settings() {
  return LearningSettingsState.defaults().copyWith(
    asrApiKey: 'demo-key',
    asrBaseUrl: 'https://api.example.com/v1',
    asrModel: 'whisper-1',
    generateBilingualAsrSubtitles: false,
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

/// 模拟参考字幕对齐后的词条：词文本不含标点，与 [english] 中的 token 一一对应。
Map<String, Object?> _chunkJsonWithStrippedWords(String english, int startMs) {
  final List<String> words = RegExp("[A-Za-z0-9]+(?:[’'-][A-Za-z0-9]+)?")
      .allMatches(english)
      .map((Match match) => match.group(0)!)
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

Map<String, Object?> _twoLineChunkJson() {
  return <String, Object?>{
    'version': 1,
    'language': 'en',
    'lines': <Map<String, Object?>>[
      _chunkLine('first line.', 1000),
      _chunkLine('second line.', 2000),
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
        'english': 'first line.',
        'chinese': '',
        'words': const <Map<String, Object?>>[
          <String, Object?>{'text': 'first', 'startMs': 1000, 'endMs': 2000},
          <String, Object?>{'text': 'line', 'startMs': 2000, 'endMs': 3000},
        ],
      },
      <String, Object?>{
        'startMs': 2000,
        'endMs': 4000,
        'english': 'second line.',
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
