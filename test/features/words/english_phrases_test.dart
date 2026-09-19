import 'package:common_learn_english/features/words/data/english_phrases.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('点击动词时命中短语动词并使用初始形态', () {
    final EnglishPhraseMatch? match = matchEnglishPhrase(
      contextSentence:
          'I mentioned that over half the human body consists of water.',
      clickedWord: 'Consists',
    );
    expect(match, isNotNull);
    expect(match!.phrase, 'consist of');
  });

  test('点击小品词也能命中同一个词组', () {
    final EnglishPhraseMatch? match = matchEnglishPhrase(
      contextSentence: 'The human body consists of water.',
      clickedWord: 'of',
    );
    expect(match?.phrase, 'consist of');
  });

  test('过去式与分词同样能命中', () {
    expect(
      matchEnglishPhrase(
        contextSentence: 'She looked after the children yesterday.',
        clickedWord: 'looked',
      )?.phrase,
      'look after',
    );
    expect(
      matchEnglishPhrase(
        contextSentence: 'I am looking forward to the holiday.',
        clickedWord: 'looking',
      )?.phrase,
      'look forward to',
    );
  });

  test('多词连接词里点任意一个词都能命中', () {
    for (final String clicked in <String>['front', 'of', 'in']) {
      expect(
        matchEnglishPhrase(
          contextSentence: 'He stood in front of the door.',
          clickedWord: clicked,
        )?.phrase,
        'in front of',
        reason: '点击 $clicked 应该命中 in front of',
      );
    }
    expect(
      matchEnglishPhrase(
        contextSentence: 'She sings as well as she dances.',
        clickedWord: 'well',
      )?.phrase,
      'as well as',
    );
  });

  test('普通单词不会误判成词组', () {
    expect(
      matchEnglishPhrase(
        contextSentence: 'I mentioned that over half the human body consists of water.',
        clickedWord: 'water',
      ),
      isNull,
    );
    expect(
      matchEnglishPhrase(
        contextSentence: 'The body is mostly water.',
        clickedWord: 'body',
      ),
      isNull,
    );
  });

  test('最长词组优先', () {
    expect(
      matchEnglishPhrase(
        contextSentence: 'I cannot put up with the noise.',
        clickedWord: 'put',
      )?.phrase,
      'put up with',
    );
  });
}
