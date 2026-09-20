import 'dart:convert';
import 'dart:io';

import 'package:common_learn_english/features/player/presentation/asr_subtitle_cache.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/player_subtitle_loader.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cache file uses episode folder and video base name', () async {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'asr-cache-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => tempDir,
      downloadsDirectory: () async => tempDir,
    );

    final File file = await cache.cacheFileFor(
      episodeId: 'episode/01',
      videoPath: '${tempDir.path}${Platform.pathSeparator}My Movie.mp4',
    );

    expect(file.path, contains('asr_subtitles'));
    expect(file.path, contains('episode_01'));
    expect(file.path.endsWith('My Movie.words.json'), isTrue);
  });

  test('export copies cached words json to downloads folder', () async {
    final Directory supportDir = Directory.systemTemp.createTempSync(
      'asr-cache-support-',
    );
    final Directory downloadsDir = Directory.systemTemp.createTempSync(
      'asr-cache-downloads-',
    );
    addTearDown(() {
      supportDir.deleteSync(recursive: true);
      downloadsDir.deleteSync(recursive: true);
    });

    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => supportDir,
      downloadsDirectory: () async => downloadsDir,
    );

    await cache.write(
      episodeId: 'ep01',
      videoPath: '/videos/Lesson01.mp4',
      content: '{"lines":[]}',
    );

    final File exported = await cache.exportOne(
      episodeId: 'ep01',
      videoPath: '/videos/Lesson01.mp4',
    );

    expect(exported.path, contains('Shadowing English'));
    expect(exported.path, contains('AI Subtitles'));
    expect(exported.path.endsWith('Lesson01.words.json'), isTrue);
    expect(exported.readAsStringSync(), '{"lines":[]}');
  });

  test('delete removes cached words json for current video', () async {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'asr-cache-delete-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => tempDir,
      downloadsDirectory: () async => tempDir,
    );

    await cache.write(
      episodeId: 'ep01',
      videoPath: '/videos/Lesson01.mp4',
      content: '{"lines":[]}',
    );
    await cache.delete(episodeId: 'ep01', videoPath: '/videos/Lesson01.mp4');

    expect(
      await cache.exists(episodeId: 'ep01', videoPath: '/videos/Lesson01.mp4'),
      isFalse,
    );
  });

  test('export all copies existing cached words files', () async {
    final Directory supportDir = Directory.systemTemp.createTempSync(
      'asr-cache-support-all-',
    );
    final Directory downloadsDir = Directory.systemTemp.createTempSync(
      'asr-cache-downloads-all-',
    );
    addTearDown(() {
      supportDir.deleteSync(recursive: true);
      downloadsDir.deleteSync(recursive: true);
    });

    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => supportDir,
      downloadsDirectory: () async => downloadsDir,
    );
    await cache.write(
      episodeId: 'ep01',
      videoPath: '/videos/Lesson01.mp4',
      content: '{"lines":[]}',
    );

    final int count = await cache.exportAll();

    expect(count, 1);
    expect(
      File(
        '${downloadsDir.path}${Platform.pathSeparator}Shadowing English'
        '${Platform.pathSeparator}AI Subtitles'
        '${Platform.pathSeparator}Lesson01.words.json',
      ).existsSync(),
      isTrue,
    );
  });

  test('cache rejects changed generation settings', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-cache-identity-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    final LearningSettingsState settings = LearningSettingsState.defaults()
        .copyWith(
          asrProvider: '腾讯云',
          asrBaseUrl: 'https://asr.tencentcloudapi.com',
          asrModel: '16k_en',
        );
    await cache.write(
      episodeId: 'ep01',
      videoPath: video.path,
      content: '{"version":1,"lines":[]}',
      settings: settings,
    );

    expect(
      await cache.read(
        episodeId: 'ep01',
        videoPath: video.path,
        settings: settings,
      ),
      isNotNull,
    );
    expect(
      await cache.read(
        episodeId: 'ep01',
        videoPath: video.path,
        settings: settings.copyWith(asrModel: 'changed-model'),
      ),
      isNull,
    );
  });

  test('cache and management entry preserve reference identity', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-cache-reference-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    final LearningSettingsState settings = LearningSettingsState.defaults();
    await cache.write(
      episodeId: 'ep01',
      videoPath: video.path,
      content: '{"version":1,"lines":[]}',
      settings: settings,
      referenceSignature: 'reference-v1',
    );

    expect(
      await cache.read(
        episodeId: 'ep01',
        videoPath: video.path,
        settings: settings,
        referenceSignature: 'reference-v1',
      ),
      isNotNull,
    );
    expect(
      (await cache.listEntries()).single.referenceSignature,
      'reference-v1',
    );
  });

  test(
    'cache can validate settings when reference identity is unavailable',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'asr-cache-unknown-reference-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File video = File('${root.path}/lesson.mp4')
        ..writeAsStringSync('video');
      final AsrSubtitleCache cache = AsrSubtitleCache(
        appSupportDirectory: () async => root,
      );
      final LearningSettingsState settings = LearningSettingsState.defaults();
      await cache.write(
        episodeId: 'ep01',
        videoPath: video.path,
        content: '{"version":1,"lines":[]}',
        settings: settings,
        referenceSignature: 'embedded-reference',
      );

      expect(
        await cache.read(
          episodeId: 'ep01',
          videoPath: video.path,
          settings: settings,
        ),
        isNotNull,
      );
      expect(
        await cache.read(
          episodeId: 'ep01',
          videoPath: video.path,
          settings: settings.copyWith(asrModel: 'changed-model'),
        ),
        isNull,
      );
    },
  );

  test(
    'standalone cache (no stored reference) stays valid when a derived srt '
    'reference appears after restart',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'asr-cache-restart-bilingual-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File video = File('${root.path}/lesson.mp4')
        ..writeAsStringSync('video');
      final AsrSubtitleCache cache = AsrSubtitleCache(
        appSupportDirectory: () async => root,
      );
      final LearningSettingsState settings = LearningSettingsState.defaults();
      await cache.write(
        episodeId: 'ep01',
        videoPath: video.path,
        content: '{"version":1,"lines":[]}',
        settings: settings,
      );

      // 重新打开节目：参考字幕（生成的 .en.srt）存在并带签名，但缓存是
      // 无参考独立生成的，此时不应因签名不匹配而丢弃双语 AI 字幕。
      expect(
        await cache.read(
          episodeId: 'ep01',
          videoPath: video.path,
          settings: settings,
          referenceSignature: 'derived-srt-signature',
        ),
        isNotNull,
      );

      // 有参考生成的缓存仍然会被不同参考签名正确地判为失效。
      final File video2 = File('${root.path}/lesson2.mp4')
        ..writeAsStringSync('video2');
      await cache.write(
        episodeId: 'ep01',
        videoPath: video2.path,
        content: '{"version":1,"lines":[]}',
        settings: settings,
        referenceSignature: 'original-reference',
      );
      expect(
        await cache.read(
          episodeId: 'ep01',
          videoPath: video2.path,
          settings: settings,
          referenceSignature: 'different-reference',
        ),
        isNull,
      );
    },
  );

  test('cache removes old adopted reference subtitles', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-cache-adopted-reference-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    final LearningSettingsState settings = LearningSettingsState.defaults();
    await cache.write(
      episodeId: 'ep01',
      videoPath: video.path,
      content: '{"lines":[]}',
      settings: settings,
    );

    expect(
      await cache.read(
        episodeId: 'ep01',
        videoPath: video.path,
        settings: settings,
      ),
      isNull,
    );
  });

  test('cache rejects changed video and removes corrupt json', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-cache-video-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    final LearningSettingsState settings = LearningSettingsState.defaults();
    await cache.write(
      episodeId: 'ep01',
      videoPath: video.path,
      content: '{"version":1,"lines":[]}',
      settings: settings,
    );
    video.writeAsStringSync('replaced-video-content');

    expect(
      await cache.read(
        episodeId: 'ep01',
        videoPath: video.path,
        settings: settings,
      ),
      isNull,
    );

    final File cacheFile = await cache.cacheFileFor(
      episodeId: 'ep01',
      videoPath: video.path,
    );
    await cacheFile.create(recursive: true);
    await cacheFile.writeAsString('{broken');
    expect(await cache.read(episodeId: 'ep01', videoPath: video.path), isNull);
    expect(cacheFile.existsSync(), isFalse);
  });

  test('management lists, edits, exports, and deletes a cache entry', () async {
    final Directory supportDir = Directory.systemTemp.createTempSync(
      'asr-cache-management-',
    );
    final Directory downloadsDir = Directory.systemTemp.createTempSync(
      'asr-cache-management-downloads-',
    );
    addTearDown(() {
      supportDir.deleteSync(recursive: true);
      downloadsDir.deleteSync(recursive: true);
    });
    final File video = File('${supportDir.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => supportDir,
      downloadsDirectory: () async => downloadsDir,
    );
    final LearningSettingsState settings = LearningSettingsState.defaults()
        .copyWith(asrProvider: '腾讯云', asrModel: '16k_en');
    await cache.write(
      episodeId: 'episode-1',
      videoPath: video.path,
      content:
          '{"version":1,"lines":[{"english":"hello","chinese":"你好","words":[]}]}',
      settings: settings,
    );

    final AiSubtitleCacheEntry entry = (await cache.listEntries()).single;
    expect(entry.episodeId, 'episode-1');
    expect(entry.videoPath, video.absolute.path);
    expect(entry.lineCount, 1);
    expect(entry.provider, '腾讯云');
    expect(entry.model, '16k_en');

    final Map<String, dynamic> content = await cache.readEntry(entry);
    final List<dynamic> lines = content['lines'] as List<dynamic>;
    (lines.single as Map<String, dynamic>)['chinese'] = '您好';
    await cache.updateEntry(entry, content);
    expect(await entry.cacheFile.readAsString(), contains('您好'));
    expect((await cache.exportEntry(entry)).existsSync(), isTrue);

    await cache.deleteEntry(entry);
    expect(await cache.listEntries(), isEmpty);
  });

  test(
    'stale cache is kept on disk (settings change / missing video / changed '
    'reference) so the management list never goes blank',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'asr-cache-keep-stale-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final File video = File('${root.path}/lesson.mp4')
        ..writeAsStringSync('video');
      final AsrSubtitleCache cache = AsrSubtitleCache(
        appSupportDirectory: () async => root,
      );
      final LearningSettingsState settings = LearningSettingsState.defaults();
      await cache.write(
        episodeId: 'ep01',
        videoPath: video.path,
        content:
            '{"version":1,"lines":[{"english":"hello","chinese":"你好","words":[]}]}',
        settings: settings,
        referenceSignature: 'original-reference',
        generatedSignature: 'generated-srt',
      );

      // 1) 设置变了：读取返回 null，但文件必须留在磁盘上。
      expect(
        await cache.read(
          episodeId: 'ep01',
          videoPath: video.path,
          settings: settings.copyWith(asrModel: 'changed-model'),
        ),
        isNull,
      );
      // 2) 参考字幕变成程序自己保存的 .en.srt/.zh.srt：仍然有效（重启后双语字幕不丢）。
      expect(
        await cache.read(
          episodeId: 'ep01',
          videoPath: video.path,
          settings: settings,
          referenceSignature: 'generated-srt',
        ),
        isNotNull,
      );
      // 3) 参考字幕被换成别的：读取返回 null，但仍不删除文件。
      expect(
        await cache.read(
          episodeId: 'ep01',
          videoPath: video.path,
          settings: settings,
          referenceSignature: 'another-reference',
        ),
        isNull,
      );
      // 4) 视频暂时不可访问：不抛异常、不删缓存。
      expect(
        await cache.read(
          episodeId: 'ep01',
          videoPath: '${root.path}/missing.mp4',
          settings: settings,
        ),
        isNull,
      );

      final List<AiSubtitleCacheEntry> entries = await cache.listEntries();
      expect(entries, hasLength(1));
      expect(entries.single.cacheFile.existsSync(), isTrue);
    },
  );

  test('management entry exposes chinese coverage and translation warning', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-cache-chinese-status-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    const String warning = '外文字幕已生成，但本地中文翻译失败：还没有下载本地翻译模型。';
    await cache.write(
      episodeId: 'ep01',
      videoPath: video.path,
      content: jsonEncode(<String, Object?>{
        'version': 1,
        'translationWarning': warning,
        'lines': <Map<String, Object?>>[
          <String, Object?>{
            'english': 'hello there',
            'chinese': '',
            'words': <Object?>[],
          },
          <String, Object?>{
            'english': 'bye',
            'chinese': '再见',
            'words': <Object?>[],
          },
        ],
      }),
      settings: LearningSettingsState.defaults(),
    );

    final AiSubtitleCacheEntry entry = (await cache.listEntries()).single;
    expect(entry.lineCount, 2);
    expect(entry.chineseLineCount, 1);
    expect(entry.translationWarning, warning);
  });

  test('isUpToDate ignores the reference signature (management view)', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-cache-uptodate-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    final LearningSettingsState settings = LearningSettingsState.defaults();
    await cache.write(
      episodeId: 'ep01',
      videoPath: video.path,
      content: '{"version":1,"lines":[]}',
      settings: settings,
      referenceSignature: 'original-reference',
    );

    final AiSubtitleCacheEntry entry = (await cache.listEntries()).single;
    expect(cache.isUpToDate(entry: entry, settings: settings), isTrue);
    expect(
      cache.isUpToDate(
        entry: entry,
        settings: settings.copyWith(asrModel: 'changed-model'),
      ),
      isFalse,
    );
  });

  test('management also lists srt subtitles saved next to imported videos',
      () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-cache-srt-list-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final Directory course =
        Directory('${root.path}/imported_sources/course-1')..createSync(recursive: true);
    final File video = File('${course.path}/lesson.mp4')
      ..writeAsStringSync('video');
    File('${course.path}/lesson.en.srt').writeAsStringSync('''
1
00:00:01,000 --> 00:00:03,000
Hello there

2
00:00:04,000 --> 00:00:06,000
How are you
''');
    File('${course.path}/lesson.zh.srt').writeAsStringSync('''
1
00:00:01,000 --> 00:00:03,000
你好
''');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );

    final List<AiSubtitleCacheEntry> entries = await cache.listEntries();
    expect(entries, hasLength(1));
    final AiSubtitleCacheEntry entry = entries.single;
    expect(entry.isSrt, isTrue);
    expect(entry.lineCount, 2);
    expect(entry.videoPath, video.path);
    expect(entry.generationSource, 'srt');
    // 中文文件作为附属文件一起管理（删除时一并删除）。
    expect(entry.companionFile?.path, endsWith('lesson.zh.srt'));

    await cache.deleteEntry(entry);
    expect(File('${course.path}/lesson.en.srt').existsSync(), isFalse);
    expect(File('${course.path}/lesson.zh.srt').existsSync(), isFalse);
    expect(await cache.listEntries(), isEmpty);
  });

  test('deleting a words cache also removes the generated srt copies',
      () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-cache-srt-cleanup-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final Directory course =
        Directory('${root.path}/imported_sources/course-1')..createSync(recursive: true);
    final File video = File('${course.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final File enSrt = File('${course.path}/lesson.en.srt')
      ..writeAsStringSync('1\n00:00:01,000 --> 00:00:02,000\nHello\n');
    final File zhSrt = File('${course.path}/lesson.zh.srt')
      ..writeAsStringSync('1\n00:00:01,000 --> 00:00:02,000\n你好\n');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    await cache.write(
      episodeId: 'ep01',
      videoPath: video.path,
      content: '{"version":1,"lines":[{"english":"hello","chinese":"你好","words":[]}]}',
      settings: LearningSettingsState.defaults(),
    );

    expect(cache.generatedSrtFiles(video.path), hasLength(2));
    expect(cache.deleteGeneratedSrtFiles(video.path), 2);
    expect(enSrt.existsSync(), isFalse);
    expect(zhSrt.existsSync(), isFalse);
  });

  test('srt entries can be read and updated from the editor', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-cache-srt-edit-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final Directory course =
        Directory('${root.path}/imported_sources/course-1')
          ..createSync(recursive: true);
    File('${course.path}/lesson.mp4').writeAsStringSync('video');
    File('${course.path}/lesson.en.srt').writeAsStringSync('''
1
00:00:01,000 --> 00:00:03,000
Hello there

2
00:00:04,000 --> 00:00:06,000
How are you
''');
    File('${course.path}/lesson.zh.srt').writeAsStringSync('''
1
00:00:01,000 --> 00:00:03,000
你好

2
00:00:04,000 --> 00:00:06,000
你好吗
''');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    final AiSubtitleCacheEntry entry = (await cache.listEntries()).single;

    // 读成与词级缓存相同的结构（含中文）。
    final Map<String, dynamic> content = await cache.readEntry(entry);
    final List<dynamic> lines = content['lines'] as List<dynamic>;
    expect(lines, hasLength(2));
    expect((lines.first as Map<String, dynamic>)['english'], 'Hello there');
    expect((lines.first as Map<String, dynamic>)['chinese'], '你好');

    // 改一句后写回 srt（中英两个文件都要更新）。
    (lines.first as Map<String, dynamic>)['english'] = 'Hello there!';
    (lines.first as Map<String, dynamic>)['chinese'] = '你好！';
    await cache.updateEntry(entry, content);

    final String enText = File('${course.path}/lesson.en.srt').readAsStringSync();
    final String zhText = File('${course.path}/lesson.zh.srt').readAsStringSync();
    expect(enText, contains('Hello there!'));
    expect(zhText, contains('你好！'));
    // 读回来确认修改生效。
    final Map<String, dynamic> reloaded = await cache.readEntry(entry);
    final List<dynamic> reloadedLines = reloaded['lines'] as List<dynamic>;
    expect(
      (reloadedLines.first as Map<String, dynamic>)['english'],
      'Hello there!',
    );
    expect(
      (reloadedLines.first as Map<String, dynamic>)['chinese'],
      '你好！',
    );
  });

  test('saveLines writes the player edits back to the cache', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-cache-save-lines-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final File video = File('${root.path}/lesson.mp4')
      ..writeAsStringSync('video');
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );

    // 没有缓存时用当前设置新建一份。
    await cache.saveLines(
      episodeId: 'ep01',
      videoPath: video.path,
      settings: LearningSettingsState.defaults(),
      lines: <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Fixed sentence.',
          chinese: '修正后的句子。',
          startMs: 1000,
          endMs: 3000,
        ),
      ],
    );
    final String? raw = await cache.read(episodeId: 'ep01', videoPath: video.path);
    expect(raw, isNotNull);
    expect(parseSubtitleLines(raw!).single.english, 'Fixed sentence.');
    expect(parseSubtitleLines(raw).single.chinese, '修正后的句子。');

    // 已有缓存时再改一遍。
    await cache.saveLines(
      episodeId: 'ep01',
      videoPath: video.path,
      lines: <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Fixed again.',
          chinese: '再改一次。',
          startMs: 1000,
          endMs: 3000,
        ),
      ],
    );
    final String? updated = await cache.read(
      episodeId: 'ep01',
      videoPath: video.path,
    );
    expect(parseSubtitleLines(updated!).single.english, 'Fixed again.');
  });

  test('management can delete all subtitle caches and checkpoints', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'asr-cache-delete-all-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final AsrSubtitleCache cache = AsrSubtitleCache(
      appSupportDirectory: () async => root,
    );
    await cache.write(
      episodeId: 'episode-1',
      videoPath: '/videos/lesson.mp4',
      content: '{"version":1,"lines":[]}',
    );

    await cache.deleteAll();

    expect(await cache.listEntries(), isEmpty);
  });
}
