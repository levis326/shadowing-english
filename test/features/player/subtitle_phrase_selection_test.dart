import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/widgets/player_subtitle_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const List<PlayerSubtitleLine> _lines = <PlayerSubtitleLine>[
  PlayerSubtitleLine(
    startTime: '00:01',
    english: 'remember you can download all the words',
    chinese: '记住你可以下载所有单词',
    startMs: 1000,
    endMs: 4000,
  ),
];

Widget _buildList({ValueChanged<String>? onCollect}) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 700,
          child: PlayerSubtitleList(
            lines: _lines,
            activeIndex: 0,
            subtitleMode: '外文',
            currentWordIndex: 0,
            fontScale: 1,
            highlightWords: false,
            onTapLine: (_) {},
            onCollectWord: onCollect ?? (_) {},
            onBookmarkLine: (_) {},
            onLoopFromLine: (_) {},
            onDictationLine: (_) {},
            onAiExplain: (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('长按后再点一个词即可选择整段词组', (WidgetTester tester) async {
    await tester.pumpWidget(_buildList());
    await tester.pumpAndSettle();

    // 长按第一个词，作为词组起点。
    await tester.longPress(find.text('remember'));
    await tester.pumpAndSettle();
    expect(find.textContaining('词组选择'), findsOneWidget);

    // 点第四个词，选中 "remember you can download"。
    await tester.tap(find.text('download'));
    await tester.pumpAndSettle();

    // 查词卡片用的就是整段词组文本（首字母大写显示）。
    expect(find.text('Remember you can download'), findsOneWidget);
  });

  testWidgets('单击仍然是查单个单词', (WidgetTester tester) async {
    await tester.pumpWidget(_buildList());
    await tester.pumpAndSettle();

    await tester.tap(find.text('words'));
    await tester.pumpAndSettle();

    expect(find.text('words'), findsWidgets);
    expect(find.text('Remember you can download'), findsNothing);
  });
}
