import 'package:common_learn_english/features/growth/presentation/growth_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('growth screen keeps its carousel and presents learning loops', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: GrowthScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('英语成长之旅'), findsOneWidget);
    expect(find.text('当前等级'), findsOneWidget);
    expect(find.text('今日成长值'), findsOneWidget);
    expect(find.text('十日坚持'), findsOneWidget);
    expect(find.text('年度沟通者'), findsOneWidget);
    expect(find.text('英语成长冒险 · 当前阶段'), findsOneWidget);
    expect(find.text('完成今天的一次练习'), findsOneWidget);
    expect(find.text('回顾收藏过的表达'), findsOneWidget);
    expect(find.textContaining('先在课程库导入一个本地视频与英文字幕'), findsOneWidget);
    expect(find.text('英语成长等级'), findsNothing);
  });

  testWidgets('growth screen stacks its Pad content at narrow widths', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(700, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: GrowthScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('英语成长冒险 · 当前阶段'), findsOneWidget);
    expect(find.text('完成今天的一次练习'), findsOneWidget);
    expect(find.text('成长勋章'), findsOneWidget);
  });

  testWidgets('growth carousel switches on horizontal drag', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: GrowthScreen())),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('growth-level-carousel')),
      const Offset(-180, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lv.2 学习路线'), findsOneWidget);
  });

  testWidgets('today growth items open their corresponding practice area', (
    WidgetTester tester,
  ) async {
    final GoRouter router = GoRouter(
      initialLocation: '/growth',
      routes: <RouteBase>[
        GoRoute(path: '/growth', builder: (_, _) => const GrowthScreen()),
        GoRoute(
          path: '/library',
          builder: (_, _) => const Scaffold(body: Text('library destination')),
        ),
        GoRoute(
          path: '/phrases',
          builder: (_, _) => const Scaffold(body: Text('phrases destination')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    final Finder savedPhrases = find
        .byKey(const Key('growth-value-action-收藏表达'))
        .first;
    await tester.ensureVisible(savedPhrases);
    await tester.pumpAndSettle();
    await tester.tap(savedPhrases);
    await tester.pumpAndSettle();

    expect(find.text('phrases destination'), findsOneWidget);
  });

  testWidgets('a badge explains its condition in a dialog', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: GrowthScreen())),
    );
    await tester.pumpAndSettle();

    final Finder badge = find.byKey(const Key('growth-badge-首部影片完成'));
    await tester.ensureVisible(badge);
    await tester.pumpAndSettle();
    await tester.tap(badge);
    await tester.pumpAndSettle();

    expect(find.text('首部影片完成'), findsWidgets);
    expect(find.textContaining('获得条件：完成 1 部影片'), findsOneWidget);
    expect(find.textContaining('当前进度：'), findsOneWidget);
    expect(find.textContaining('建议下一步：在学习页选一集'), findsOneWidget);
    expect(find.text('去开始学习'), findsOneWidget);
  });

  testWidgets('top status chips show the real learning status on tap', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: GrowthScreen())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pad-status-timer')));
    await tester.pumpAndSettle();

    expect(find.text('今日学习状态'), findsOneWidget);
    expect(find.textContaining('累计学习'), findsOneWidget);
  });
}
