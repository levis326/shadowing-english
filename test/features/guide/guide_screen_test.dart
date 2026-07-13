import 'package:common_learn_english/features/guide/presentation/guide_screen.dart';
import 'package:common_learn_english/features/guide/presentation/widgets/how_to_learn_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('guide screen guides learners through the three-pass method', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: GuideScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('每天 20 分钟，用一部剧练会真实英语'), findsOneWidget);
    expect(find.text('一集视频，只练这三件事'), findsOneWidget);
    expect(find.text('第 2 遍：听清表达'), findsOneWidget);
    expect(find.text('一句台词，具体应该怎么学？'), findsOneWidget);
    expect(find.text('选择适合你的第一部剧'), findsOneWidget);
    expect(find.text('查看学习资源'), findsNWidgets(3));
    expect(find.byKey(const Key('guide-start-learning')), findsOneWidget);
  });

  testWidgets('guide content stacks its learning flow on narrow screens', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: HowToLearnContent(
                onStart: () {},
                onPlayMethod: () {},
                onOpenResource: (GuideLearningResource _) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('第 1 遍：看懂剧情'), findsOneWidget);
    expect(find.text('第 2 遍：听清表达'), findsOneWidget);
    expect(find.text('第 3 遍：开口模仿'), findsOneWidget);
  });
}
