import 'package:common_learn_english/features/home/presentation/pad_home_screen.dart';
import 'package:common_learn_english/features/player/presentation/pad_portrait_player_screen.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/player_screen.dart';
import 'package:common_learn_english/features/player/presentation/widgets/player_subtitle_list.dart';
import 'package:common_learn_english/features/player/presentation/widgets/player_video_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SubtitleListHarness extends StatefulWidget {
  const _SubtitleListHarness({this.height = 360, super.key});

  final double height;

  @override
  State<_SubtitleListHarness> createState() => _SubtitleListHarnessState();
}

class _SubtitleListHarnessState extends State<_SubtitleListHarness> {
  int _activeIndex = 0;
  bool _isPlaying = false;

  void setActiveIndex(int nextIndex) {
    setState(() {
      _activeIndex = nextIndex;
    });
  }

  void setPlaying({required bool value}) {
    setState(() {
      _isPlaying = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SizedBox(
        height: widget.height,
        child: PlayerSubtitleList(
          lines: PlayerMockState.fallbackLines,
          activeIndex: _activeIndex,
          subtitleMode: '双语',
          currentWordIndex: 0,
          fontScale: 1,
          highlightWords: true,
          onTapLine: (_) {},
          onCollectWord: (_) {},
          onBookmarkLine: (_) {},
          onLoopFromLine: (_) {},
          onDictationLine: (_) {},
          onAiExplain: (_) {},
          isPlaying: _isPlaying,
          onTogglePlaying: () => setPlaying(value: !_isPlaying),
        ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders pad home shell', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: PadHomeScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('语言避难所'), findsWidgets);
    expect(find.text('晚上好 Mark 👋'), findsOneWidget);
    expect(find.text('导入你的第一套英语视频课程'), findsOneWidget);
    expect(find.text('去导入课程'), findsOneWidget);
    expect(find.text('今日挑战'), findsOneWidget);
  });

  testWidgets('shows pad home scaffold background color', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: PadHomeScreen())),
    );
    await tester.pumpAndSettle();

    final Scaffold scaffold = tester.widget<Scaffold>(
      find.byType(Scaffold).first,
    );
    expect(scaffold.backgroundColor, const Color(0xFFFAFAFA));
  });

  testWidgets('renders pad player controls', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: PlayerScreen(episodeId: 'intern-ep3')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('课程名称'), findsOneWidget);
    expect(find.text('第 01 集'), findsOneWidget);
    expect(find.text('0.8'), findsOneWidget);
  });

  testWidgets('switches player speed state', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: PlayerScreen(episodeId: 'intern-ep3')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('0.8'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.25×').last);
    await tester.pumpAndSettle();

    expect(find.text('1.25'), findsOneWidget);
  });

  testWidgets('player progress slider seeks to another line', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: PlayerScreen(episodeId: 'intern-ep3')),
      ),
    );
    await tester.pumpAndSettle();

    final Finder slider = find.byKey(
      const ValueKey<String>('player-seek-slider'),
    );
    final Offset center = tester.getCenter(slider);
    final Size size = tester.getSize(slider);
    await tester.tapAt(Offset(center.dx + size.width * 0.42, center.dy));
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('renders portrait player shell', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(768, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: PadPortraitPlayerScreen(episodeId: 'intern-ep3'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('课程名称'), findsOneWidget);
    expect(find.text('第 01 集'), findsOneWidget);
  });

  testWidgets('player no longer shows daily discovery panel', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: PlayerScreen(episodeId: 'intern-ep3')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('今日发现'), findsNothing);
  });

  testWidgets('tapping subtitle word shows anchored dictionary popup', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: PlayerSubtitleList(
              lines: PlayerMockState.fallbackLines,
              activeIndex: 0,
              subtitleMode: '双语',
              currentWordIndex: 0,
              fontScale: 1,
              highlightWords: true,
              onTapLine: (_) {},
              onCollectWord: (_) {},
              onBookmarkLine: (_) {},
              onLoopFromLine: (_) {},
              onDictationLine: (_) {},
              onAiExplain: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('chaotic'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('word-lookup-popup-card')),
      findsOneWidget,
    );
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('dictionary popup close does not move the subtitle list', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final GlobalKey<_SubtitleListHarnessState> harnessKey =
        GlobalKey<_SubtitleListHarnessState>();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: _SubtitleListHarness(key: harnessKey, height: 180),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('chaotic'));
    await tester.pumpAndSettle();
    final ScrollableState scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    final double scrollOffsetBefore = scrollable.position.pixels;

    harnessKey.currentState!.setActiveIndex(1);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('word-lookup-popup-card')),
      findsOneWidget,
    );
    expect(scrollable.position.pixels, scrollOffsetBefore);

    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, scrollOffsetBefore);
  });

  testWidgets('subtitle list resumes following only after locating current', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final GlobalKey<_SubtitleListHarnessState> harnessKey =
        GlobalKey<_SubtitleListHarnessState>();

    await tester.pumpWidget(
      MaterialApp(home: _SubtitleListHarness(key: harnessKey)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Divider), findsWidgets);

    final Finder targetLine = find.text('一个他们最终可以休息的地方。');
    final Finder listFinder = find.byType(ListView);
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(listFinder),
    );
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();

    harnessKey.currentState!.setActiveIndex(2);
    await tester.pump();

    final double beforeReleaseCenter =
        tester.getCenter(targetLine).dy - tester.getCenter(listFinder).dy;

    await gesture.up();
    await tester.pumpAndSettle();

    expect(targetLine, findsOneWidget);
    final double afterReleaseCenter =
        tester.getCenter(targetLine).dy - tester.getCenter(listFinder).dy;
    expect(afterReleaseCenter, beforeReleaseCenter);

    await tester.tap(find.text('定位当前'));
    await tester.pumpAndSettle();

    final double afterLocateCenter =
        tester.getCenter(targetLine).dy - tester.getCenter(listFinder).dy;
    expect(afterLocateCenter.abs(), lessThan(afterReleaseCenter.abs()));

    harnessKey.currentState!
      ..setPlaying(value: true)
      ..setActiveIndex(1);
    await tester.pumpAndSettle();

    final Finder nextTargetLine = find.text('他们寻找一个远离喧嚣的安静避难所。');
    final double afterResumeCenter =
        tester.getCenter(nextTargetLine).dy - tester.getCenter(listFinder).dy;
    expect(afterResumeCenter.abs(), lessThan(afterReleaseCenter.abs()));
  });

  testWidgets('player video panel does not overflow with many scrubber dots', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: PlayerVideoPanel(
              line: PlayerMockState.fallbackLines.first,
              isPlaying: false,
              subtitleMode: '双语',
              subtitleModes: const <String>['双语', '单英'],
              speed: '1.0×',
              isShadowing: false,
              isLooping: false,
              isMuted: false,
              volumeLevel: 1,
              onTogglePlaying: () {},
              onPreviousLine: () {},
              onReplayLine: () {},
              onNextLine: () {},
              onSeekBackward: () {},
              onSeekForward: () {},
              activeIndex: 0,
              totalLines: 122,
              onSelectLine: (_) {},
              onSeek: (_) {},
              onSpeedSelected: (_) {},
              onSelectSubtitleMode: (_) {},
              onToggleShadowing: () {},
              onToggleLoop: () {},
              onToggleMuted: () {},
              onVolumeChanged: (_) {},
              onToggleFullscreen: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('player video panel changes the content frame ratio', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerVideoPanel(
            line: PlayerMockState.fallbackLines.first,
            isPlaying: false,
            subtitleMode: '双语',
            subtitleModes: const <String>['双语'],
            speed: '1.0×',
            isShadowing: false,
            isLooping: false,
            isMuted: false,
            volumeLevel: 1,
            onTogglePlaying: () {},
            onPreviousLine: () {},
            onReplayLine: () {},
            onNextLine: () {},
            onSeekBackward: () {},
            onSeekForward: () {},
            activeIndex: 0,
            totalLines: 1,
            onSelectLine: (_) {},
            onSeek: (_) {},
            onSpeedSelected: (_) {},
            onSelectSubtitleMode: (_) {},
            onToggleShadowing: () {},
            onToggleLoop: () {},
            onToggleMuted: () {},
            onVolumeChanged: (_) {},
            onToggleFullscreen: () {},
            videoSurface: const SizedBox.expand(),
            videoReady: true,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('画面比例'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1:1').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    final Size frameSize = tester.getSize(
      find.byKey(const ValueKey<String>('player-content-fit-frame')),
    );
    expect(frameSize.width, closeTo(frameSize.height, 0.01));
  });

  testWidgets('player video panel supports keyboard playback shortcuts', (
    WidgetTester tester,
  ) async {
    int toggles = 0;
    int backward = 0;
    int forward = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerVideoPanel(
            line: PlayerMockState.fallbackLines.first,
            isPlaying: false,
            subtitleMode: '双语',
            subtitleModes: const <String>['双语'],
            speed: '1.0×',
            isShadowing: false,
            isLooping: false,
            isMuted: false,
            volumeLevel: 1,
            onTogglePlaying: () => toggles++,
            onPreviousLine: () {},
            onReplayLine: () {},
            onNextLine: () {},
            onSeekBackward: () => backward++,
            onSeekForward: () => forward++,
            activeIndex: 0,
            totalLines: 1,
            onSelectLine: (_) {},
            onSeek: (_) {},
            onSpeedSelected: (_) {},
            onSelectSubtitleMode: (_) {},
            onToggleShadowing: () {},
            onToggleLoop: () {},
            onToggleMuted: () {},
            onVolumeChanged: (_) {},
            onToggleFullscreen: () {},
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);

    expect(toggles, 1);
    expect(backward, 1);
    expect(forward, 1);
  });
}
