import 'package:common_learn_english/features/words/data/offline_word_dictionary.dart';
import 'package:common_learn_english/features/words/data/word_formation.dart';
import 'package:flutter_test/flutter_test.dart';

Future<WordFormation?> _analyze(String word) => analyzeWordFormation(
  rawWord: word,
  dictionary: const OfflineWordDictionary(),
);

String _partsOf(WordFormation formation) => formation.parts
    .map((WordPart part) => '${part.kindLabel}:${part.text}')
    .join(' | ');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('前缀 + 词根 + 后缀都能拆出来', () async {
    final WordFormation? formation = await _analyze('inspection');
    expect(formation, isNotNull);
    expect(formation!.hasRoot, isTrue);
    // 词根在词干里以 spec 形式出现，就匹配表里的 spec（含义与 spect 相同）。
    expect(formation.roots.first, anyOf('spec', 'spect'));
    expect(_partsOf(formation), contains('前缀:in'));
    expect(_partsOf(formation), contains('词根:spec'));
    expect(_partsOf(formation), contains('后缀:tion'));
    expect(formation.breakdown, contains('看'));
  });

  test('没有前缀的派生词也能拆', () async {
    final WordFormation? formation = await _analyze('spectator');
    expect(formation, isNotNull);
    expect(formation!.roots.first, 'spect');
    expect(_partsOf(formation), contains('词根:spect'));
  });

  test('同根词来自内置词典，且不包含自己', () async {
    final WordFormation? formation = await _analyze('inspect');
    expect(formation, isNotNull);
    expect(formation!.relatedWords, isNotEmpty);
    expect(formation.relatedWords, isNot(contains('inspect')));
    expect(
      formation.relatedWords.any((String word) => word.contains('spect')),
      isTrue,
    );
  });

  test('前缀 + 后缀结构即使没有词根也会展示', () async {
    final WordFormation? formation = await _analyze('unhappiness');
    expect(formation, isNotNull);
    expect(_partsOf(formation!), contains('前缀:un'));
    expect(_partsOf(formation), contains('后缀:ness'));
  });

  test('拆不出来的普通单词不显示构词区块', () async {
    for (final String word in <String>['water', 'table', 'hello']) {
      expect(await _analyze(word), isNull, reason: '$word 不应该被硬拆');
    }
  });

  test('太短的词不分析', () async {
    expect(await _analyze('act'), isNull);
    expect(await _analyze('be'), isNull);
  });
}
