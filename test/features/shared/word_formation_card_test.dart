import 'package:common_learn_english/features/shared/domain/word_lookup_entry.dart';
import 'package:common_learn_english/features/shared/presentation/word_lookup_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void _noop() {}

void main() {
  testWidgets('查词卡片展示词根词缀与同根词', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 820,
              child: WordLookupPopupCard(
                rawWord: 'inspection',
                contextSentence: 'The inspection starts tomorrow.',
                onClose: _noop,
              ),
            ),
          ),
        ),
      ),
    );
    // 词典资源是 4MB JSON，真实 IO 需要 runAsync 才能跑完。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 800)),
    );
    await tester.pumpAndSettle();

    expect(find.text('词根词缀'), findsOneWidget);
    expect(find.text('spect-'), findsNothing);
    expect(find.text('in-'), findsOneWidget);
    expect(find.text('-tion'), findsOneWidget);
    // 词根 chip 带类型与含义；同根词里可能也有同名词条。
    expect(find.text('spec'), findsWidgets);
    expect(find.textContaining('词根·'), findsOneWidget);
    expect(find.textContaining('前缀·'), findsOneWidget);
    // 同根词来自内置词典，点一下会切换到那个词。
    expect(find.text('同根词（点击查看）'), findsOneWidget);
    final Finder related = find.byType(ActionChip);
    expect(related, findsWidgets);
    final ActionChip chip = tester.widget<ActionChip>(related.first);
    final String relatedWord = (chip.label as Text).data!;
    await tester.tap(related.first);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pumpAndSettle();
    // 卡片标题切换成那个同根词（首字母大写显示）。
    final String relatedTitle =
        relatedWord[0].toUpperCase() + relatedWord.substring(1);
    expect(find.text(relatedTitle), findsWidgets);
  });

  testWidgets('加入短语库时收藏的是词/词组与释义，而不是整句字幕', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    WordLookupEntry? collected;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 820,
              child: WordLookupPopupCard(
                rawWord: 'Inspection',
                contextSentence: 'The inspection starts tomorrow.',
                onClose: _noop,
                onCollect: (WordLookupEntry entry) => collected = entry,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 800)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('加入短语库'));
    await tester.pumpAndSettle();

    expect(collected, isNotNull);
    // 单词用初始形态，并且带上词典释义。
    expect(collected!.word, 'Inspection');
    expect(collected!.definitionCn, isNotEmpty);
    expect(collected!.definitionCn, isNot(contains('The inspection starts')));
  });

  testWidgets('没有构词结构的单词不显示该区块', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 820,
              child: WordLookupPopupCard(
                rawWord: 'water',
                contextSentence: 'I drink water every day.',
                onClose: _noop,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 800)),
    );
    await tester.pumpAndSettle();

    expect(find.text('词根词缀'), findsNothing);
  });
}
