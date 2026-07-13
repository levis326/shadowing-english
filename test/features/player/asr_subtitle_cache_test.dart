import 'dart:io';

import 'package:common_learn_english/features/player/presentation/asr_subtitle_cache.dart';
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
}
