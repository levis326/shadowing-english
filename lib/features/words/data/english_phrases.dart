import 'english_lemmas.dart';

/// 在句子里匹配到的固定词组。
class EnglishPhraseMatch {
  const EnglishPhraseMatch({
    required this.phrase,
    required this.startIndex,
    required this.endIndex,
  });

  /// 词组的初始形态（取自词表，例如 `consist of`、`as well as`）。
  final String phrase;

  /// 在句子 token 里的起止下标（含）。
  final int startIndex;
  final int endIndex;

  int get length => endIndex - startIndex + 1;
}

/// 在 [contextSentence] 中找到包含 [clickedWord] 的固定词组。
///
/// 匹配前会把句子和词表都做词形还原，因此
/// `consists of` → `consist of`、`looking after` → `look after`、
/// `as well as` 里点任意一个词都能命中。找不到就返回 null（按单词查）。
EnglishPhraseMatch? matchEnglishPhrase({
  required String contextSentence,
  required String clickedWord,
  int? clickedIndex,
}) {
  final List<String> tokens = _tokenize(contextSentence);
  if (tokens.isEmpty) {
    return null;
  }
  final String target = englishLemma(clickedWord);
  if (target.isEmpty) {
    return null;
  }
  final List<String> lemmas = tokens.map(englishLemma).toList(growable: false);
  final List<int> hits = <int>[
    for (int index = 0; index < lemmas.length; index += 1)
      if (lemmas[index] == target) index,
  ];
  if (hits.isEmpty) {
    return null;
  }
  final int anchor = clickedIndex != null && clickedIndex >= 0
      ? (hits.contains(clickedIndex)
            ? clickedIndex
            : _nearest(hits, clickedIndex))
      : hits.first;
  return _matchAt(lemmas: lemmas, anchor: anchor);
}

EnglishPhraseMatch? _matchAt({
  required List<String> lemmas,
  required int anchor,
}) {
  // 最长的词组优先；其次选择离点击词最近、最靠前的窗口。
  for (int length = _maxPhraseWords; length >= 2; length -= 1) {
    for (int offset = 0; offset < length; offset += 1) {
      final int start = anchor - offset;
      final int end = start + length - 1;
      if (start < 0 || end >= lemmas.length) {
        continue;
      }
      final String candidate = lemmas.sublist(start, end + 1).join(' ');
      final String? canonical = kLemmaPhraseIndex[candidate];
      if (canonical != null) {
        return EnglishPhraseMatch(
          phrase: canonical,
          startIndex: start,
          endIndex: end,
        );
      }
    }
  }
  return null;
}

int _nearest(List<int> hits, int index) {
  int best = hits.first;
  int bestDistance = (best - index).abs();
  for (final int hit in hits) {
    final int distance = (hit - index).abs();
    if (distance < bestDistance) {
      best = hit;
      bestDistance = distance;
    }
  }
  return best;
}

const int _maxPhraseWords = 4;

List<String> _tokenize(String sentence) {
  return RegExp("[A-Za-z][A-Za-z'’-]*")
      .allMatches(sentence)
      .map((RegExpMatch match) => match.group(0)!)
      .toList(growable: false);
}

/// 词表索引：把每个词组也做词形还原，保证两边形态一致。
final Map<String, String> kLemmaPhraseIndex = <String, String>{
  for (final String phrase in kEnglishPhrases)
    phrase
        .split(' ')
        .map(englishLemma)
        .join(' '): phrase,
};

/// 常用固定词组（初始形态）：短语动词、动词搭配与多词连接词。
///
/// 只用来“判断这里是不是一个词组”，中文释义仍走查词/翻译流程。
const List<String> kEnglishPhrases = <String>[
  // 短语动词 / 动词 + 介词
  'ask for',
  'back up',
  'be about to',
  'be back',
  'be over',
  'belong to',
  'blow up',
  'break down',
  'break into',
  'break out',
  'break up',
  'bring about',
  'bring back',
  'bring down',
  'bring in',
  'bring out',
  'bring up',
  'build up',
  'burn down',
  'call back',
  'call for',
  'call off',
  'call on',
  'call up',
  'calm down',
  'carry on',
  'carry out',
  'catch up',
  'check in',
  'check out',
  'cheer up',
  'clean up',
  'clear up',
  'close down',
  'come across',
  'come along',
  'come back',
  'come down',
  'come from',
  'come in',
  'come on',
  'come out',
  'come over',
  'come true',
  'come up',
  'come up with',
  'compare with',
  'complain about',
  'concentrate on',
  'consist of',
  'count on',
  'cut down',
  'cut off',
  'cut out',
  'deal with',
  'depend on',
  'die out',
  'differ from',
  'do without',
  'dress up',
  'drop by',
  'drop in',
  'drop off',
  'drop out',
  'eat out',
  'end up',
  'fall asleep',
  'fall behind',
  'fall down',
  'fall in love',
  'fall over',
  'figure out',
  'fill in',
  'fill out',
  'fill up',
  'find out',
  'finish off',
  'focus on',
  'follow up',
  'get along',
  'get away',
  'get back',
  'get down',
  'get in',
  'get off',
  'get on',
  'get out',
  'get over',
  'get rid of',
  'get through',
  'get together',
  'get up',
  'get used to',
  'give away',
  'give back',
  'give in',
  'give out',
  'give up',
  'go ahead',
  'go away',
  'go back',
  'go by',
  'go down',
  'go in',
  'go off',
  'go on',
  'go out',
  'go over',
  'go through',
  'go up',
  'grow up',
  'hand in',
  'hand out',
  'hang on',
  'hang out',
  'hang up',
  'happen to',
  'hear about',
  'hear from',
  'hear of',
  'heat up',
  'help out',
  'hold back',
  'hold on',
  'hold up',
  'hurry up',
  'join in',
  'keep away',
  'keep in touch',
  'keep off',
  'keep on',
  'keep out',
  'keep up',
  'keep up with',
  'knock down',
  'knock out',
  'laugh at',
  'lay off',
  'lead to',
  'leave behind',
  'leave out',
  'let down',
  'let in',
  'let out',
  'lie down',
  'light up',
  'line up',
  'listen to',
  'live on',
  'log in',
  'log out',
  'look after',
  'look around',
  'look at',
  'look back',
  'look down on',
  'look for',
  'look forward to',
  'look into',
  'look like',
  'look out',
  'look over',
  'look through',
  'look up',
  'look up to',
  'make sure',
  'make up',
  'make up for',
  'mix up',
  'move in',
  'move on',
  'move out',
  'pass away',
  'pass by',
  'pass on',
  'pay attention to',
  'pay back',
  'pay off',
  'pick out',
  'pick up',
  'play with',
  'point out',
  'pull down',
  'pull off',
  'pull out',
  'pull over',
  'put away',
  'put back',
  'put down',
  'put off',
  'put on',
  'put out',
  'put together',
  'put up',
  'put up with',
  'refer to',
  'rely on',
  'result in',
  'ring up',
  'run away',
  'run into',
  'run out',
  'run out of',
  'run over',
  'save up',
  'see off',
  'sell out',
  'send for',
  'send off',
  'set off',
  'set out',
  'set up',
  'settle down',
  'show off',
  'show up',
  'shut down',
  'shut up',
  'sit down',
  'slow down',
  'sort out',
  'speak up',
  'speed up',
  'stand by',
  'stand for',
  'stand out',
  'stand up',
  'stay up',
  'stick to',
  'stop by',
  'sum up',
  'switch off',
  'switch on',
  'take after',
  'take apart',
  'take away',
  'take back',
  'take care of',
  'take down',
  'take in',
  'take off',
  'take on',
  'take out',
  'take over',
  'take part in',
  'take place',
  'take up',
  'talk about',
  'talk to',
  'tell apart',
  'think about',
  'think of',
  'think over',
  'throw away',
  'throw up',
  'tidy up',
  'try on',
  'try out',
  'turn around',
  'turn down',
  'turn in',
  'turn into',
  'turn off',
  'turn on',
  'turn out',
  'turn over',
  'turn to',
  'turn up',
  'use up',
  'wait for',
  'wake up',
  'walk away',
  'warm up',
  'wash up',
  'watch out',
  'wear out',
  'work out',
  'worry about',
  'write down',
  'write off',
  // 多词连接词 / 固定表达
  'a few of',
  'a lot of',
  'a number of',
  'according to',
  'across from',
  'after all',
  'ahead of',
  'all over',
  'all the time',
  'apart from',
  'as a result',
  'as far as',
  'as if',
  'as long as',
  'as soon as',
  'as though',
  'as usual',
  'as well',
  'as well as',
  'at all',
  'at first',
  'at last',
  'at least',
  'at once',
  'at present',
  'at the same time',
  'because of',
  'before long',
  'by accident',
  'by chance',
  'by hand',
  'by mistake',
  'by the way',
  'close to',
  'due to',
  'each other',
  'even if',
  'even though',
  'ever since',
  'except for',
  'far away',
  'for example',
  'for instance',
  'for sale',
  'from time to time',
  'in addition',
  'in addition to',
  'in case',
  'in charge of',
  'in common',
  'in fact',
  'in front of',
  'in general',
  'in order to',
  'in other words',
  'in particular',
  'in place of',
  'in public',
  'in short',
  'in spite of',
  'in the end',
  'in the future',
  'in the meantime',
  'in time',
  'in total',
  'in touch',
  'instead of',
  'just in case',
  'kind of',
  'lots of',
  'more and more',
  'no longer',
  'of course',
  'on average',
  'on board',
  'on foot',
  'on purpose',
  'on the other hand',
  'on time',
  'once again',
  'once more',
  'one another',
  'out of',
  'out of date',
  'over and over',
  'plenty of',
  'point of view',
  'rather than',
  'right away',
  'so far',
  'so that',
  'sooner or later',
  'such as',
  'thanks to',
  'the same as',
  'to be honest',
  'too much',
  'up to',
  'up to date',
  'what about',
];
