import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/widgets/shadowing_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('convertEcdictPhoneticToIpa 转换为接近 IPA 的音标', () {
    expect(convertEcdictPhoneticToIpa('trai'), 'traɪ');
    expect(convertEcdictPhoneticToIpa('it'), 'ɪt');
    expect(convertEcdictPhoneticToIpa("tә'dei"), 'təˈdeɪ');
    expect(convertEcdictPhoneticToIpa("'raitiŋ"), 'ˈraɪtɪŋ');
    expect(convertEcdictPhoneticToIpa('θiŋk'), 'θɪŋk');
    expect(convertEcdictPhoneticToIpa('bu:st'), 'buːst');
  });

  testWidgets('跟读面板显示编号句子与点击录音入口', (WidgetTester tester) async {
    final PlayerMockState state = PlayerMockState()
      ..loadLines(const <PlayerSubtitleLine>[
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
      ]);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 720,
              child: ShadowingPanel(
                lines: state.lines,
                activeIndex: 0,
                subtitleMode: '双语',
                currentWordIndex: 0,
                fontScale: 1,
                highlightWords: false,
                onTapLine: (_) {},
                onCollectWord: (_) {},
                onBookmarkLine: (_) {},
                onLoopFromLine: (_) {},
                onDictationLine: (_) {},
                onAiExplain: (_) {},
                isPlaying: false,
                onTogglePlaying: () {},
                onArmRecording: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 全部句子直接显示（带序号）。
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Try'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    // 双语模式显示中文。
    expect(find.text('今天就试试吧。'), findsOneWidget);
    // 点击录音入口 + 提示。
    expect(find.text('点击录音'), findsOneWidget);
    expect(find.text('句子播放完毕后会自动开始录音'), findsOneWidget);
  });

  testWidgets('跟读面板点击录音后进入已开启自动录音状态', (WidgetTester tester) async {
    final PlayerMockState state = PlayerMockState()
      ..loadLines(const <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Try it today.',
          chinese: '',
          startMs: 1000,
          endMs: 2500,
        ),
      ]);
    bool armed = false;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 720,
              child: ShadowingPanel(
                lines: state.lines,
                activeIndex: 0,
                subtitleMode: '外文',
                currentWordIndex: 0,
                fontScale: 1,
                highlightWords: false,
                onTapLine: (_) {},
                onCollectWord: (_) {},
                onBookmarkLine: (_) {},
                onLoopFromLine: (_) {},
                onDictationLine: (_) {},
                onAiExplain: (_) {},
                isPlaying: false,
                onTogglePlaying: () {},
                onArmRecording: () {
                  armed = true;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('点击录音'));
    await tester.pump();

    expect(armed, isTrue);
    expect(find.text('已开启自动录音'), findsOneWidget);
  });
}
