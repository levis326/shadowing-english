import 'package:common_learn_english/features/navigation/presentation/floating_bottom_nav.dart';
import 'package:common_learn_english/features/navigation/presentation/navigation_destination.dart';
import 'package:common_learn_english/features/shared/data/daily_english_service.dart';
import 'package:common_learn_english/features/shared/data/word_pronunciation_service.dart';
import 'package:common_learn_english/features/shared/presentation/pad/pad_sidebar.dart';
import 'package:common_learn_english/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod/src/framework.dart' show Override;

void main() {
  test('pad prototype routes stay addressable', () {
    expect(
      AppNavDestination.values.map((AppNavDestination item) => item.route),
      containsAll(const <String>[
        '/home',
        '/library',
        '/growth',
        '/phrases',
        '/guide',
        '/settings',
        '/importCourse',
      ]),
    );
  });

  testWidgets('pad sidebar navigates on tap', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final GoRouter router = GoRouter(
      initialLocation: SGRoute.home.route,
      routes: <GoRoute>[
        GoRoute(
          path: SGRoute.home.route,
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(
                body: Row(
                  children: <Widget>[
                    PadSidebar(current: AppNavDestination.home),
                    Expanded(child: Center(child: Text('home page'))),
                  ],
                ),
              ),
        ),
        GoRoute(
          path: SGRoute.library.route,
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(
                body: Row(
                  children: <Widget>[
                    PadSidebar(current: AppNavDestination.library),
                    Expanded(child: Center(child: Text('library page'))),
                  ],
                ),
              ),
        ),
        GoRoute(
          path: SGRoute.phrases.route,
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(
                body: Row(
                  children: <Widget>[
                    PadSidebar(current: AppNavDestination.phrases),
                    Expanded(child: Center(child: Text('phrases page'))),
                  ],
                ),
              ),
        ),
        GoRoute(
          path: SGRoute.growth.route,
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Center(child: Text('growth page'))),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('home page'), findsOneWidget);
    expect(
      find.byKey(const Key('pad-sidebar-growth-avatar-1')),
      findsOneWidget,
    );

    await tester.tap(find.text('短语'));
    await tester.pumpAndSettle();
    expect(find.text('phrases page'), findsOneWidget);

    await tester.tap(find.text('学习'));
    await tester.pumpAndSettle();
    expect(find.text('library page'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pad-sidebar-growth-entry')));
    await tester.pumpAndSettle();
    expect(find.text('growth page'), findsOneWidget);
  });

  testWidgets('pad sidebar clears the system status bar', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MediaQuery(
          data: MediaQueryData(
            padding: EdgeInsets.only(top: 32),
            disableAnimations: true,
          ),
          child: MaterialApp(
            home: Scaffold(
              body: Row(
                children: <Widget>[
                  PadSidebar(current: AppNavDestination.home),
                  Expanded(child: SizedBox.shrink()),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.byKey(const Key('pad-sidebar-header'))).dy,
      46,
    );
  });

  testWidgets('level one sidebar companion uses its static level image', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: PadSidebar(current: AppNavDestination.home)),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/img/growth-level-1.png',
      ),
      findsOneWidget,
    );
  });

  testWidgets('portrait bottom navigation moves secondary pages into more', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          bottomNavigationBar: FloatingBottomNav(
            current: AppNavDestination.phrases,
          ),
        ),
      ),
    );

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('学习'), findsOneWidget);
    expect(find.text('成长'), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);
    expect(find.text('短语'), findsNothing);

    await tester.tap(find.byKey(const Key('bottom-nav-more')));
    await tester.pumpAndSettle();
    expect(find.text('短语'), findsOneWidget);
    expect(find.text('单词'), findsOneWidget);
    expect(find.text('怎么学'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('sidebar companion shows and cycles daily English', (
    WidgetTester tester,
  ) async {
    String? spoken;
    int playCount = 0;
    const List<DailyEnglishPhrase> phrases = <DailyEnglishPhrase>[
      DailyEnglishPhrase(english: 'First sentence.', translation: '第一句。'),
      DailyEnglishPhrase(english: 'Second sentence.', translation: '第二句。'),
      DailyEnglishPhrase(english: 'Third sentence.', translation: '第三句。'),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dailyEnglishServiceProvider.overrideWithValue(
            DailyEnglishService(loadOverride: () async => phrases),
          ),
          wordPronunciationServiceProvider.overrideWithValue(
            WordPronunciationService(
              speakOverride: (String text) async {
                playCount += 1;
                spoken = text;
              },
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PadSidebar(current: AppNavDestination.home)),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('pad-sidebar-daily-english-bubble')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('pad-sidebar-daily-english-entry')));
    await tester.pump();
    await tester.pump();
    expect(find.text('First sentence.'), findsOneWidget);
    expect(find.text('第一句。'), findsOneWidget);

    expect(find.text('播放声音'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pad-sidebar-daily-english-play')));
    await tester.pump();
    expect(spoken, 'First sentence.');
    expect(playCount, 1);

    await tester.tap(
      find.byKey(const Key('pad-sidebar-header')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(
      find.byKey(const Key('pad-sidebar-daily-english-bubble')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('pad-sidebar-daily-english-entry')));
    await tester.pump();
    expect(find.text('First sentence.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pad-sidebar-daily-english-close')));
    await tester.pump();
    expect(
      find.byKey(const Key('pad-sidebar-daily-english-bubble')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('pad-sidebar-daily-english-entry')));
    await tester.pump();
    await tester.tap(find.text('换一句'));
    await tester.pump();
    expect(find.text('Second sentence.'), findsOneWidget);
  });
}
