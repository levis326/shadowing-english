import 'package:common_learn_english/features/words/data/english_lemmas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('常见词形还原到初始形态', () {
    const Map<String, String> cases = <String, String>{
      'consists': 'consist',
      'consisted': 'consist',
      'drinking': 'drink',
      'studies': 'study',
      'studied': 'study',
      'stopped': 'stop',
      'running': 'run',
      'cities': 'city',
      'boxes': 'box',
      'plays': 'play',
      'played': 'play',
      'children': 'child',
      'went': 'go',
      'better': 'good',
      'was': 'be',
      'has': 'have',
    };
    for (final MapEntry<String, String> entry in cases.entries) {
      expect(
        englishLemma(entry.key),
        entry.value,
        reason: '${entry.key} 应该还原成 ${entry.value}',
      );
    }
  });

  test('比较级与副词在候选里（交给词典确认）', () {
    // making / taking 这类“去掉 ing 后要补 e”的形式交给词典确认。
    expect(englishLemmaCandidates('making'), contains('make'));
    expect(englishLemmaCandidates('bigger'), contains('big'));
    expect(englishLemmaCandidates('biggest'), contains('big'));
    expect(englishLemmaCandidates('happily'), contains('happy'));
    expect(englishLemmaCandidates('quickly'), contains('quick'));
    // 高置信度还原不会误伤本身是原形的词。
    expect(englishLemma('water'), 'water');
    expect(englishLemma('bigger'), 'bigger');
  });

  test('已经是一般形式的词保持不变', () {
    for (final String word in <String>['consist', 'water', 'body', 'english']) {
      expect(englishLemma(word), word);
    }
  });

  test('标点与大小写不影响还原', () {
    expect(englishLemma('Consists,'), 'consist');
    expect(englishLemma('“Water.”'), 'water');
  });
}
