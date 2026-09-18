import 'dart:convert';
import 'dart:io';

import 'package:common_learn_english/features/player/presentation/asr_subtitle_cache.dart';
import 'package:common_learn_english/features/player/presentation/asr_subtitle_job.dart';
import 'package:common_learn_english/features/player/presentation/asr_subtitle_service.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/player_subtitle_loader.dart';
import 'package:common_learn_english/features/player/presentation/subtitle_text_source.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

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
        'endMs': startMs + 3000,
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
                    ? startMs + 3000
                    : wordStartMs + wordMs,
              };
            })
            .toList(growable: false),
      },
    ],
  };
}

void main() {
  test(
    'subtitle text file drives the wording while local whisper only times it',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'asr-text-job-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File video = File('${root.path}/lesson.mp4')
        ..writeAsStringSync('video');
      final File chunk = File('${root.path}/chunk.wav')..writeAsStringSync('a');
      final AsrSubtitleCache cache = AsrSubtitleCache(
        appSupportDirectory: () async => root,
      );
      final List<LearningSettingsState> transcribeSettings =
          <LearningSettingsState>[];
      final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
        supportDirectory: () async => root,
        cache: cache,
        whisperAvailabilityChecker: () async => null,
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
              transcribeSettings.add(settings);
              // Whisper 的识别结果（用词与用户文件略有差别）。
              return _chunkJson('Hello there, my dear friend', 1000);
            },
      );

      // 用户手上的完全正确字幕文本：一句一行，没有时间轴。
      final SubtitleTextSource source = parseSubtitleTextFile('''
Hello there, my dear friend.
''');

      final String raw = await runner.runFromSubtitleText(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: LearningSettingsState.defaults(),
        textSource: source,
      );

      final List<PlayerSubtitleLine> lines = parseSubtitleLines(raw);
      // 文字来自用户的文件，并按句读标点拆成独立字幕行（和 AI 字幕一致）。
      expect(
        lines.map((PlayerSubtitleLine line) => line.english),
        <String>['Hello there,', 'my dear friend.'],
      );
      // 时间轴来自本地 Whisper。
      expect(lines.first.startMs, 1000);
      expect(lines.last.endMs, 4000);
      expect(lines.first.words, isNotEmpty);
      // 强制本地 Whisper：不管“设置 → ASR 来源”选了什么。
      expect(transcribeSettings, hasLength(1));
      expect(transcribeSettings.single.asrProvider, localWhisperProviderName);
      // 标记来源，管理页可以据此用同一条路径重新生成。
      expect(subtitleGenerationSource(raw), subtitleTextSourceLabel);
      // 参考字幕快照被保存下来（重新生成/重新打开时可用）。
      expect(subtitleReferenceLinesFromCache(raw), hasLength(1));
      // 缓存可读取，管理页能看到。
      final List<AiSubtitleCacheEntry> entries = await cache.listEntries();
      expect(entries, hasLength(1));
      expect(entries.single.generationSource, subtitleTextSourceLabel);
    },
  );

  test('translation still fills chinese for text based subtitles', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-text-translate-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File chunk = File('${root.path}/chunk.wav')..writeAsStringSync('a');
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      whisperAvailabilityChecker: () async => null,
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

    final String raw = await runner.runFromSubtitleText(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: LearningSettingsState.defaults().copyWith(
        generateBilingualAsrSubtitles: true,
        translationProvider: 'OpenAI',
      ),
      textSource: parseSubtitleTextFile('Hello there.'),
    );

    expect(parseSubtitleLines(raw).single.chinese, '你好。');
  });

  test('a subtitle file that already has timings never touches the audio',
      () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-text-srt-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async =>
            throw StateError('audio must not be extracted'),
      ),
      whisperAvailabilityChecker: () async =>
          throw StateError('whisper must not be required'),
      cloudTranscribeChunk:
          ({
            required AsrAudioChunk chunk,
            required LearningSettingsState settings,
          }) async => throw StateError('no transcription expected'),
    );

    final SubtitleTextSource source = parseSubtitleTextFile('''
1
00:00:01,000 --> 00:00:04,000
Hello there, my friend

2
00:00:05,000 --> 00:00:08,000
See you tomorrow
''');

    final String raw = await runner.runFromSubtitleText(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: LearningSettingsState.defaults(),
      textSource: source,
    );

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(raw);
    expect(
      lines.map((PlayerSubtitleLine line) => line.english),
      <String>['Hello there,', 'my friend', 'See you tomorrow'],
    );
    expect(lines.first.startMs, 1000);
    expect(lines.last.endMs, 8000);
    expect(subtitleGenerationSource(raw), subtitleTextSourceLabel);
  });

  test('explains how to install local whisper when it is missing', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-text-no-whisper-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
    );

    await expectLater(
      runner.runFromSubtitleText(
        episodeId: 'episode-1',
        videoPath: video.path,
        settings: LearningSettingsState.defaults(),
        textSource: parseSubtitleTextFile('Hello there.'),
      ),
      throwsA(
        isA<AsrSubtitleGenerationException>().having(
          (AsrSubtitleGenerationException error) => error.message,
          'message',
          contains('本地模型'),
        ),
      ),
    );
  });

  test('reuses a cached timing skeleton without running whisper again',
      () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-text-skeleton-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final AsrSubtitleJobRunner runner = AsrSubtitleJobRunner(
      supportDirectory: () async => root,
      cache: AsrSubtitleCache(appSupportDirectory: () async => root),
      service: AsrSubtitleService(
        prepareAudioChunksOverride: (_) async =>
            throw StateError('audio must not be extracted'),
      ),
      whisperAvailabilityChecker: () async =>
          throw StateError('whisper must not be required'),
    );

    final String raw = await runner.runFromSubtitleText(
      episodeId: 'episode-1',
      videoPath: video.path,
      settings: LearningSettingsState.defaults(),
      textSource: parseSubtitleTextFile('Hello there. See you tomorrow.'),
      timingRecognition: const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'hello there',
          chinese: '',
          startMs: 1000,
          endMs: 3000,
        ),
        PlayerSubtitleLine(
          startTime: '00:05',
          english: 'see you tomorrow',
          chinese: '',
          startMs: 5000,
          endMs: 8000,
        ),
      ],
    );

    final List<PlayerSubtitleLine> lines = parseSubtitleLines(raw);
    expect(
      lines.map((PlayerSubtitleLine line) => line.english),
      <String>['Hello there.', 'See you tomorrow.'],
    );
    expect(lines.first.startMs, 1000);
    expect(lines.last.endMs, 8000);
    expect(
      jsonDecode(raw),
      isA<Map<String, dynamic>>(),
    );
    expect(subtitleGenerationSource(raw), subtitleTextSourceLabel);
  });
}
