import 'dart:io';

import 'package:common_learn_english/features/import_course/domain/android_import_picker.dart';
import 'package:common_learn_english/features/import_course/domain/import_match.dart';
import 'package:common_learn_english/features/import_course/presentation/widgets/import_course_flow.dart';
import 'package:common_learn_english/features/library/presentation/library_catalog_provider.dart';
import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<ImportMatchRow>> _syncParse({
  required String videoFolder,
  required String? subtitleFolder,
  List<String>? videoFiles,
  List<String>? subtitleFiles,
}) async {
  return ImportMatcher.parse(
    videoFolder: videoFolder,
    subtitleFolder: subtitleFolder,
    videoFiles: videoFiles,
    subtitleFiles: subtitleFiles,
  );
}

void main() {
  testWidgets('import screen follows the redesigned three-step import flow', (
    WidgetTester tester,
  ) async {
    final Directory root = Directory.systemTemp.createTempSync('import-course-test-');
    addTearDown(() => root.deleteSync(recursive: true));

    final Directory videoFolder = Directory('${root.path}/videos')..createSync();
    final Directory subtitleFolder = Directory('${root.path}/subs')..createSync();
    File('${videoFolder.path}/lesson1.mp4').writeAsStringSync('video1');
    File('${subtitleFolder.path}/lesson1.srt').writeAsStringSync('subtitle1');
    File('${subtitleFolder.path}/lesson1.zh.srt').writeAsStringSync('字幕1');

    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ImportCourseFlow(
              onCancel: () {},
              onImportCompleted: () {},
              parseMatches: _syncParse,
              pickVideoFolder: () => Future<String?>.value(videoFolder.path),
              pickSubtitleFolder: () => Future<String?>.value(subtitleFolder.path),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('导入影视'), findsOneWidget);
    expect(find.text('把本地视频和字幕整理成新的学习片库。'), findsOneWidget);
    expect(find.textContaining('选择视频文件'), findsWidgets);
    expect(find.text('确认导入并建立课程'), findsNothing);

    await tester.tap(find.textContaining('选择视频文件').last);
    await tester.pumpAndSettle();

    expect(find.text('选择字幕文件夹并开始解析'), findsOneWidget);
    expect(find.text('开始解析'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '开始解析'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '选择字幕文件夹'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '开始解析'));
    await tester.pump();
    expect(find.text('正在分析视频和字幕...'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.textContaining('智能解析匹配剧集'), findsWidgets);
    expect(find.byTooltip('返回上一步'), findsOneWidget);

    // 导入会把媒体文件真实复制进应用数据目录（真实 IO），
    // 必须在 runAsync 中触发并等待完成。
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, '确认导入并建立课程'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pumpAndSettle();

    expect(find.textContaining('智能导入课程成功'), findsOneWidget);
    final LibraryEpisodeItem importedEpisode = container
        .read(libraryCatalogProvider)
        .first
        .episodes
        .first;
    final Directory copiedDir = File(importedEpisode.videoAsset!).parent;
    addTearDown(() {
      if (copiedDir.existsSync()) {
        copiedDir.deleteSync(recursive: true);
      }
    });
  });

  testWidgets('import screen no longer shows cover generation progress while importing', (
    WidgetTester tester,
  ) async {
    final Directory root = Directory.systemTemp.createTempSync('import-course-progress-');
    addTearDown(() => root.deleteSync(recursive: true));

    final Directory videoFolder = Directory('${root.path}/videos')..createSync();
    final Directory subtitleFolder = Directory('${root.path}/subs')..createSync();
    File('${videoFolder.path}/lesson1.mp4').writeAsStringSync('video1');
    File('${subtitleFolder.path}/lesson1.srt').writeAsStringSync('subtitle1');

    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ImportCourseFlow(
              onCancel: () {},
              onImportCompleted: () {},
              parseMatches: _syncParse,
              pickVideoFolder: () => Future<String?>.value(videoFolder.path),
              pickSubtitleFolder: () => Future<String?>.value(subtitleFolder.path),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('选择视频文件').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '选择字幕文件夹'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '开始解析'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    // 导入会把媒体文件真实复制进应用数据目录（真实 IO），
    // 必须在 runAsync 中触发并等待完成。
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, '确认导入并建立课程'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });

    expect(find.textContaining('正在生成封面'), findsNothing);
    await tester.pumpAndSettle();
    final ProviderContainer usedContainer = ProviderScope.containerOf(
      tester.element(find.byType(ImportCourseFlow)),
    );
    final LibraryEpisodeItem importedEpisode = usedContainer
        .read(libraryCatalogProvider)
        .first
        .episodes
        .first;
    final Directory copiedDir = File(importedEpisode.videoAsset!).parent;
    addTearDown(() {
      if (copiedDir.existsSync()) {
        copiedDir.deleteSync(recursive: true);
      }
    });
  });

  testWidgets('android import uses picked folder name instead of first episode name', (
    WidgetTester tester,
  ) async {
    final Directory root = Directory.systemTemp.createTempSync('import-course-android-');
    addTearDown(() => root.deleteSync(recursive: true));

    final File video = File('${root.path}/01.mp4')..writeAsStringSync('video1');
    final File subtitle = File('${root.path}/01.srt')..writeAsStringSync('subtitle1');

    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ImportCourseFlow(
              onCancel: () {},
              onImportCompleted: () {},
              parseMatches: _syncParse,
              pickAndroidVideoDirectory: () async => AndroidImportDirectorySelection(
                folderName: 'Friends',
                label: 'Friends（1 个文件）',
                files: <String>[video.path],
                sourceUris: const <String, String>{},
              ),
              pickAndroidSubtitleDirectory: () async => AndroidImportDirectorySelection(
                folderName: 'Friends Subs',
                label: 'Friends Subs（1 个文件）',
                files: <String>[subtitle.path],
                sourceUris: const <String, String>{},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('选择视频文件').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '选择字幕文件夹'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '开始解析'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    // 导入会把媒体文件真实复制进应用数据目录（真实 IO），
    // 必须在 runAsync 中触发并等待完成。
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, '确认导入并建立课程'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pumpAndSettle();

    expect(container.read(libraryCatalogProvider).first.title, 'Friends');
    final LibraryEpisodeItem importedEpisode = container
        .read(libraryCatalogProvider)
        .first
        .episodes
        .first;
    final Directory copiedDir = File(importedEpisode.videoAsset!).parent;
    addTearDown(() {
      if (copiedDir.existsSync()) {
        copiedDir.deleteSync(recursive: true);
      }
    });
  });
}
