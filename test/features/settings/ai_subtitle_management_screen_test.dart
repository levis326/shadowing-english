import 'dart:io';

import 'package:common_learn_english/features/player/presentation/asr_subtitle_cache.dart';
import 'package:common_learn_english/features/settings/presentation/ai_subtitle_management_screen.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'management supports selecting and exporting multiple subtitles',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final _CacheFixture fixture = (await tester.runAsync(_createFixture))!;
      addTearDown(fixture.dispose);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: AiSubtitleManagementScreen(cache: fixture.cache),
          ),
        ),
      );
      await _pumpFrames(tester);
      await tester.tap(find.text('批量选择'));
      await _pumpFrames(tester);
      await tester.tap(find.text('全选 2 项'));
      await _pumpFrames(tester);

      expect(find.text('已选择 2 项'), findsOneWidget);
      expect(find.text('导出所选'), findsOneWidget);
      expect(find.text('删除所选'), findsOneWidget);

      await tester.tap(find.text('导出所选'));
      await _pumpFrames(tester);
      final Directory exportDirectory = Directory(
        '${fixture.downloads.path}${Platform.pathSeparator}Shadowing English'
        '${Platform.pathSeparator}AI Subtitles',
      );
      expect(
        exportDirectory.listSync().whereType<File>().where(
          (File file) => file.path.endsWith('.words.json'),
        ),
        hasLength(2),
      );
    },
  );

  testWidgets('management supports deleting multiple subtitles', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final _CacheFixture fixture = (await tester.runAsync(_createFixture))!;
    addTearDown(fixture.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: AiSubtitleManagementScreen(cache: fixture.cache),
        ),
      ),
    );
    await _pumpFrames(tester);
    await tester.tap(find.text('批量选择'));
    await _pumpFrames(tester);
    await tester.tap(find.text('全选 2 项'));
    await _pumpFrames(tester);
    await tester.tap(find.text('删除所选'));
    await _pumpFrames(tester);
    await tester.tap(find.text('删除所选').last);
    await _pumpFrames(tester);

    expect(await tester.runAsync(fixture.cache.listEntries), isEmpty);
    expect(find.text('还没有生成过 AI 字幕'), findsOneWidget);
  });

  testWidgets('word editing changes text without changing word timestamps', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final _CacheFixture fixture = (await tester.runAsync(
      () => _createFixture(count: 1),
    ))!;
    addTearDown(fixture.dispose);
    final AiSubtitleCacheEntry entry = fixture.entries.single;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: AiSubtitleEditorScreen(entry: entry, cache: fixture.cache),
        ),
      ),
    );
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey<String>('ai-subtitle-line-0')));
    await _pumpFrames(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('ai-subtitle-word-0-0')),
    );
    await _pumpFrames(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-subtitle-word-field')),
      'Hi',
    );
    await tester.tap(find.text('确定'));
    await _pumpFrames(tester);
    await tester.tap(find.text('保存'));
    await _pumpFrames(tester);

    final Map<String, dynamic> content = (await tester.runAsync(
      () => fixture.cache.readEntry(entry),
    ))!;
    final Map<String, dynamic> line =
        (content['lines'] as List<dynamic>).single as Map<String, dynamic>;
    final Map<String, dynamic> firstWord =
        (line['words'] as List<dynamic>).first as Map<String, dynamic>;
    expect(line['english'], 'Hi world');
    expect(firstWord['text'], 'Hi');
    expect(firstWord['startMs'], 1000);
    expect(firstWord['endMs'], 1500);
  });
}

class _CacheFixture {
  const _CacheFixture({
    required this.root,
    required this.downloads,
    required this.cache,
    required this.entries,
  });

  final Directory root;
  final Directory downloads;
  final AsrSubtitleCache cache;
  final List<AiSubtitleCacheEntry> entries;

  void dispose() {
    if (root.existsSync()) root.deleteSync(recursive: true);
    if (downloads.existsSync()) downloads.deleteSync(recursive: true);
  }
}

Future<_CacheFixture> _createFixture({int count = 2}) async {
  final Directory root = Directory.systemTemp.createTempSync(
    'ai-subtitle-management-',
  );
  final Directory downloads = Directory.systemTemp.createTempSync(
    'ai-subtitle-management-downloads-',
  );
  final AsrSubtitleCache cache = AsrSubtitleCache(
    appSupportDirectory: () async => root,
    downloadsDirectory: () async => downloads,
  );
  final LearningSettingsState settings = LearningSettingsState.defaults()
      .copyWith(asrProvider: '腾讯云', asrModel: '16k_en');
  for (int index = 0; index < count; index += 1) {
    final Directory videoDirectory = Directory('${root.path}/video-$index')
      ..createSync();
    final File video = File('${videoDirectory.path}/lesson.mp4')
      ..writeAsStringSync('video-$index');
    await cache.write(
      episodeId: 'episode-$index',
      videoPath: video.path,
      settings: settings,
      content: '''
{"version":1,"lines":[{"startMs":1000,"endMs":2000,"english":"hello world","chinese":"你好，世界","words":[{"text":"hello","startMs":1000,"endMs":1500},{"text":"world","startMs":1500,"endMs":2000}]}]}
''',
    );
  }
  return _CacheFixture(
    root: root,
    downloads: downloads,
    cache: cache,
    entries: await cache.listEntries(),
  );
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (int index = 0; index < 6; index += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
