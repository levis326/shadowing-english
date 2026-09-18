import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/widgets/subtitle_navigator_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildPanel({
    required int activeIndex,
    required ValueChanged<int> onTapLine,
    String subtitleMode = '双语',
  }) {
    const List<PlayerSubtitleLine> lines = <PlayerSubtitleLine>[
      PlayerSubtitleLine(
        startTime: '00:01',
        english: 'Try it today.',
        chinese: '今天就试试吧。',
        startMs: 1000,
        endMs: 2500,
      ),
      PlayerSubtitleLine(
        startTime: '00:03',
        english: 'Second line.',
        chinese: '第二句。',
        startMs: 3000,
        endMs: 4500,
      ),
    ];
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 480,
          height: 640,
          child: SubtitleNavigatorPanel(
            lines: lines,
            activeIndex: activeIndex,
            subtitleMode: subtitleMode,
            fontScale: 1,
            onTapLine: onTapLine,
            onCollectWord: (_) {},
            onBookmarkLine: (_) {},
            onLoopFromLine: (_) {},
            onDictationLine: (_) {},
            onAiExplain: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('没有字幕时提供「用字幕文本文件生成」入口', (WidgetTester tester) async {
    int taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 480,
            height: 640,
            child: SubtitleNavigatorPanel(
              lines: const <PlayerSubtitleLine>[],
              activeIndex: 0,
              subtitleMode: '双语',
              fontScale: 1,
              onTapLine: (_) {},
              onCollectWord: (_) {},
              onBookmarkLine: (_) {},
              onLoopFromLine: (_) {},
              onDictationLine: (_) {},
              onAiExplain: (_) {},
              showAiGenerateSubtitles: true,
              onGenerateAiSubtitles: () {},
              onGenerateFromSubtitleText: () => taps += 1,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI生成可跟读的词级同步字幕'), findsOneWidget);
    expect(find.text('用字幕文本文件生成（不识别文字）'), findsOneWidget);
    await tester.tap(find.text('用字幕文本文件生成（不识别文字）'));
    expect(taps, 1);
  });

  testWidgets('已有 AI 字幕时也能从字幕文本重新生成', (WidgetTester tester) async {
    int taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 480,
            height: 640,
            child: SubtitleNavigatorPanel(
              lines: const <PlayerSubtitleLine>[
                PlayerSubtitleLine(
                  startTime: '00:01',
                  english: 'Try it today.',
                  chinese: '今天就试试吧。',
                  startMs: 1000,
                  endMs: 2500,
                ),
              ],
              activeIndex: 0,
              subtitleMode: '双语',
              fontScale: 1,
              onTapLine: (_) {},
              onCollectWord: (_) {},
              onBookmarkLine: (_) {},
              onLoopFromLine: (_) {},
              onDictationLine: (_) {},
              onAiExplain: (_) {},
              onRegenerateAiSubtitles: () {},
              onGenerateFromSubtitleText: () => taps += 1,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('用文本生成'), findsOneWidget);
    await tester.tap(find.text('用文本生成'));
    expect(taps, 1);
  });

  testWidgets('字幕区显示全部双语字幕且无点击录音', (WidgetTester tester) async {
    await tester.pumpWidget(buildPanel(activeIndex: 0, onTapLine: (_) {}));
    await tester.pumpAndSettle();

    expect(find.text('字幕'), findsOneWidget);
    // 全部句子直接显示（带序号 + 中英双语）。
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Try'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('今天就试试吧。'), findsOneWidget);
    expect(find.text('第二句。'), findsOneWidget);
    // 字幕区没有录音功能。
    expect(find.text('点击录音'), findsNothing);
  });

  testWidgets('外文模式隐藏中文译文', (WidgetTester tester) async {
    await tester.pumpWidget(
      buildPanel(activeIndex: 0, onTapLine: (_) {}, subtitleMode: '外文'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Try'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('今天就试试吧。'), findsNothing);
    expect(find.text('第二句。'), findsNothing);
  });

  testWidgets('单击某句回调导航并高亮当前句', (WidgetTester tester) async {
    int? tapped;
    await tester.pumpWidget(
      buildPanel(
        activeIndex: 0,
        onTapLine: (int index) {
          tapped = index;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Second'));
    await tester.pump();

    expect(tapped, 1);
  });
}
