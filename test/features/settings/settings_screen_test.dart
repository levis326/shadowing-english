import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:common_learn_english/features/settings/presentation/settings_screen.dart';
import 'package:common_learn_english/features/settings/presentation/widgets/settings_group_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/src/framework.dart' show Override;

void main() {
  testWidgets('settings screen shows prototype sections', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsWidgets);
    expect(find.text('播放'), findsOneWidget);
    expect(find.text('学习').last, findsOneWidget);
    expect(find.text('默认字幕模式'), findsOneWidget);
    expect(find.text('单词高亮样式'), findsOneWidget);
    expect(find.text('单词高亮边框粗细'), findsOneWidget);
    expect(find.text('每日打卡提醒'), findsOneWidget);
    expect(find.text('词典来源'), findsNothing);

    await _scrollToTranslationSettings(tester);

    expect(find.text('翻译'), findsOneWidget);
    expect(find.text('翻译来源'), findsOneWidget);
    expect(find.text('API Key'), findsNothing);
    expect(find.text('获取模型'), findsNothing);
    expect(find.text('Model'), findsNothing);
    expect(find.text('API Secret'), findsNothing);
    expect(find.text('App ID'), findsNothing);
    expect(find.text('AccessKey ID'), findsNothing);
  });

  testWidgets('settings screen shows AI translation fields for OpenAI', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();

    await _scrollToTranslationSettings(tester);
    await tester.tap(_translationProviderDropdown());
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenAI').last);
    await tester.pumpAndSettle();

    expect(find.text('API Key'), findsOneWidget);
    expect(find.text('获取模型'), findsWidgets);
    expect(find.text('Model'), findsOneWidget);
  });

  testWidgets('settings screen shows DeepSeek as AI provider option', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();

    await _scrollToTranslationSettings(tester);
    await tester.tap(_translationProviderDropdown());
    await tester.pumpAndSettle();

    expect(find.text('DeepSeek').last, findsOneWidget);
  });

  testWidgets('settings screen shows direct translation fields for baidu', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();

    await _scrollToTranslationSettings(tester);
    await tester.tap(_translationProviderDropdown());
    await tester.pumpAndSettle();
    await tester.tap(find.text('百度翻译').last);
    await tester.pumpAndSettle();

    expect(find.text('App ID'), findsOneWidget);
    expect(find.text('Secret'), findsOneWidget);
  });

  testWidgets('settings screen shows fetched models dropdown for AI provider', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          learningSettingsProvider.overrideWith(
            () => _TestLearningSettingsNotifier(
              LearningSettingsState.defaults().copyWith(
                translationProvider: 'DeepSeek',
                translationModel: 'deepseek-v4-flash',
                availableTranslationModels: const <String>[
                  'deepseek-v4-flash',
                  'deepseek-v4-pro',
                ],
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await _scrollToTranslationSettings(tester);

    expect(find.text('模型选择'), findsOneWidget);
    expect(find.text('deepseek-v4-flash'), findsWidgets);
  });

  testWidgets('settings links to AI subtitle management', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();
    for (
      int index = 0;
      index < 8 && find.text('管理 AI 字幕').evaluate().isEmpty;
      index++
    ) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();
    }

    expect(find.text('管理 AI 字幕'), findsOneWidget);
    expect(find.text('导出 AI 字幕'), findsNothing);
  });

  testWidgets('settings offers deleting all imported courses', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();
    for (
      int index = 0;
      index < 10 && find.text('删除所有课程（含视频和字幕）').evaluate().isEmpty;
      index++
    ) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();
    }

    // 入口存在，并且说明里写清了会删除视频/字幕、保留原始文件。
    expect(find.text('删除所有课程（含视频和字幕）'), findsOneWidget);
    expect(
      find.textContaining('复制到程序数据目录的视频、字幕文件'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('删除所有课程（含视频和字幕）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除所有课程（含视频和字幕）'));
    await tester.pumpAndSettle();

    // 确认弹窗给出影响范围，可取消。
    expect(find.text('删除所有课程'), findsOneWidget);
    expect(
      find.textContaining('原始视频文件不会被删除'),
      findsOneWidget,
    );
    expect(find.text('全部删除'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('全部删除'), findsNothing);
  });

  testWidgets('settings offers restoring the initial state', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();
    for (
      int index = 0;
      index < 12 && find.text('恢复初始状态（重置应用）').evaluate().isEmpty;
      index++
    ) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();
    }

    expect(find.text('恢复初始状态（重置应用）'), findsOneWidget);

    await tester.ensureVisible(find.text('恢复初始状态（重置应用）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复初始状态（重置应用）'));
    await tester.pumpAndSettle();

    // 弹窗列出会删除的内容，并提供「同时删除本地模型」选项。
    expect(find.textContaining('将应用恢复到刚安装的状态'), findsOneWidget);
    expect(find.textContaining('同时删除已下载的本地模型'), findsWidgets);
    expect(find.textContaining('原始视频文件和已有的本地备份'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
  });
}

Future<void> _scrollToTranslationSettings(WidgetTester tester) async {
  for (
    int index = 0;
    index < 4 && find.text('翻译来源').evaluate().isEmpty;
    index++
  ) {
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
  }
}

Finder _translationProviderDropdown() {
  return find.descendant(
    of: find.ancestor(
      of: find.text('翻译来源'),
      matching: find.byType(SettingsGroupCard),
    ),
    matching: find.byType(DropdownButton<String>),
  );
}

class _TestLearningSettingsNotifier extends LearningSettingsNotifier {
  _TestLearningSettingsNotifier(this._state);

  final LearningSettingsState _state;

  @override
  LearningSettingsState build() => _state;
}
