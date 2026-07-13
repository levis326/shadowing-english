import 'package:common_learn_english/features/growth/presentation/growth_screen.dart';
import 'package:common_learn_english/features/home/presentation/pad_home_screen.dart';
import 'package:common_learn_english/features/import_course/presentation/import_course_screen.dart';
import 'package:common_learn_english/features/library/presentation/library_screen.dart';
import 'package:common_learn_english/features/phrases/presentation/phrases_screen.dart';
import 'package:common_learn_english/features/player/presentation/player_screen.dart';
import 'package:common_learn_english/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('home quick entries and hero navigate to prototype targets', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final GoRouter router = GoRouter(
      initialLocation: SGRoute.home.route,
      routes: <GoRoute>[
        GoRoute(
          path: SGRoute.home.route,
          builder: (BuildContext context, GoRouterState state) =>
              const PadHomeScreen(),
        ),
        GoRoute(
          path: SGRoute.phrases.route,
          builder: (BuildContext context, GoRouterState state) =>
              const PhrasesScreen(),
        ),
        GoRoute(
          path: SGRoute.library.route,
          builder: (BuildContext context, GoRouterState state) =>
              const LibraryScreen(),
        ),
        GoRoute(
          path: SGRoute.growth.route,
          builder: (BuildContext context, GoRouterState state) =>
              const GrowthScreen(),
        ),
        GoRoute(
          path: SGRoute.importCourse.route,
          builder: (BuildContext context, GoRouterState state) =>
              const ImportCourseScreen(),
        ),
        GoRoute(
          path: '/episodes/:episodeId',
          name: SGRoute.player.name,
          builder: (BuildContext context, GoRouterState state) =>
              PlayerScreen(episodeId: state.pathParameters['episodeId']!),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    expect(find.text('晚上好 Mark 👋'), findsOneWidget);
    expect(find.text('继续你的英语成长旅程'), findsOneWidget);
    expect(find.text('今日挑战'), findsOneWidget);
    expect(find.text('英语成长'), findsWidgets);
    await tester.tap(find.text('英语成长').last);
    await tester.pumpAndSettle();
    expect(find.text('英语成长之旅'), findsOneWidget);

    router.go(SGRoute.home.route);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('复习我的短语'),
      400,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey<String>('home-page-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('复习我的短语'), findsOneWidget);
    await tester.ensureVisible(find.text('复习我的短语'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复习我的短语'));
    await tester.pumpAndSettle();

    expect(find.text('新增短语'), findsOneWidget);

    router.go(SGRoute.home.route);
    await tester.pumpAndSettle();

    await tester.tap(find.text('导入你的第一套英语视频课程'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, SGRoute.home.route);
    expect(find.text('导入影视'), findsOneWidget);
    expect(find.text('选择视频文件夹'), findsWidgets);
  });
}
