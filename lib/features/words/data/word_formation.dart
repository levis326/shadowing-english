import 'english_lemmas.dart';
import 'offline_word_dictionary.dart';
import 'word_formation_data.dart';

/// 构词成分类型。
enum WordPartKind { prefix, root, suffix, stem }

/// 构词拆解出的一段。
class WordPart {
  const WordPart({required this.text, required this.kind, this.meaning = ''});

  final String text;
  final WordPartKind kind;

  /// 中文含义（词干没有含义）。
  final String meaning;

  String get kindLabel => switch (kind) {
    WordPartKind.prefix => '前缀',
    WordPartKind.root => '词根',
    WordPartKind.suffix => '后缀',
    WordPartKind.stem => '词干',
  };
}

/// 一个单词的构词分析结果。
class WordFormation {
  const WordFormation({
    required this.word,
    required this.parts,
    required this.roots,
    this.relatedWords = const <String>[],
  });

  final String word;
  final List<WordPart> parts;

  /// 命中的词根（可能多个变体），用于查同根词。
  final List<String> roots;

  /// 同根词（来自内置词典）。
  final List<String> relatedWords;

  bool get hasRoot => roots.isNotEmpty;

  /// 形如 `un- 不 + believe + -able 可…的`。
  String get breakdown => parts
      .map(
        (WordPart part) => part.kind == WordPartKind.stem
            ? part.text
            : '${part.kind == WordPartKind.suffix ? '-' : ''}'
                  '${part.text}'
                  '${part.kind == WordPartKind.prefix ? '-' : ''}'
                  '${part.meaning.isEmpty ? '' : ' ${part.meaning}'}',
      )
      .join(' + ');
}

/// 拆解 [rawWord] 的构词：前缀 + 词根 + 后缀。
///
/// 完全离线：只用本文件内的词根词缀表 + 内置词典。拆不出词根（且没有
/// “前缀+后缀”这种明显结构）时返回 null，界面就不显示这个区块。
Future<WordFormation?> analyzeWordFormation({
  required String rawWord,
  required OfflineWordDictionary dictionary,
  int relatedLimit = 10,
}) async {
  final String word = normalizeEnglishToken(rawWord);
  if (word.length < 4 || word.contains(' ') || word.contains('-')) {
    return null;
  }
  if (word.contains(RegExp('[^a-z]'))) {
    return null;
  }

  final _Decomposition? decomposition = await _decompose(word, dictionary);
  if (decomposition == null) {
    return null;
  }

  List<String> related = const <String>[];
  if (decomposition.roots.isNotEmpty) {
    final String root = decomposition.roots.first;
    // 多取一些候选再按“同词根家族”过滤，避免恰好包含同一串字母的词。
    final List<String> candidates = await dictionary.wordsContaining(
      root,
      exclude: word,
      limit: relatedLimit * 12,
    );
    related = candidates
        .where((String candidate) => isSameRootFamily(candidate, root))
        .take(relatedLimit)
        .toList(growable: false);
  }
  return WordFormation(
    word: word,
    parts: decomposition.parts,
    roots: decomposition.roots,
    relatedWords: related,
  );
}

class _Decomposition {
  _Decomposition({
    required this.parts,
    required this.roots,
  });

  final List<WordPart> parts;
  final List<String> roots;
}

/// 尝试几种拆法并挑最合理的：
///  1. 能拆出词根的最优；
///  2. 否则“词干本身是词典里的真实单词 + 至少一个词缀”也可以（teacher → teach + -er）；
///  3. 都做不到就不显示（water、table、english）。
Future<_Decomposition?> _decompose(
  String word,
  OfflineWordDictionary dictionary,
) async {
  final List<WordPart> prefixes = _prefixCandidates(word);
  final List<WordPart?> prefixOptions = <WordPart?>[...prefixes, null];
  final List<_Attempt> attempts = <_Attempt>[];
  for (final WordPart? prefix in prefixOptions) {
    final String rest = prefix == null
        ? word
        : word.substring(prefix.text.length);
    for (final WordPart? suffix in <WordPart?>[
      ..._suffixCandidates(rest),
      null,
    ]) {
      attempts.add(_Attempt(word: word, prefix: prefix, suffix: suffix));
    }
  }

  _Attempt? best;
  for (final _Attempt attempt in attempts) {
    if (attempt.prefix == null && attempt.suffix == null) {
      continue;
    }
    final String middle = attempt.middle;
    if (middle.length < 3) {
      continue;
    }
    final _RootMatch? root = _matchRoot(middle);
    final bool middleIsWord =
        root == null && await _isRealWord(middle, dictionary);
    final int affixCount =
        (attempt.prefix == null ? 0 : 1) + (attempt.suffix == null ? 0 : 1);
    final int score =
        (root != null ? 6 : 0) + (middleIsWord ? 3 : 0) + affixCount;
    final _Attempt scored = attempt.copyWith(
      root: root,
      middleIsWord: middleIsWord,
      score: score,
    );
    if (best == null || scored.score > best.score) {
      best = scored;
    }
  }
  if (best == null) {
    return null;
  }
  final bool acceptable =
      best.root != null || (best.middleIsWord && best.affixCount >= 1);
  if (!acceptable) {
    return null;
  }
  return _buildDecomposition(best);
}

_Decomposition _buildDecomposition(_Attempt attempt) {
  final List<WordPart> parts = <WordPart>[
    if (attempt.prefix != null) attempt.prefix!,
  ];
  final List<String> roots = <String>[];
  final String middle = attempt.middle;
  final _RootMatch? root = attempt.root;
  if (root != null) {
    if (root.start > 0) {
      parts.add(
        WordPart(
          text: middle.substring(0, root.start),
          kind: WordPartKind.stem,
        ),
      );
    }
    parts.add(
      WordPart(
        text: root.root,
        kind: WordPartKind.root,
        meaning: root.meaning,
      ),
    );
    roots.add(root.root);
    final String tail = middle.substring(root.start + root.root.length);
    if (tail.isNotEmpty) {
      final String suffixInTail = _knownSuffixIn(tail);
      if (suffixInTail.isNotEmpty) {
        final String stemInTail = tail.substring(
          0,
          tail.length - suffixInTail.length,
        );
        if (stemInTail.isNotEmpty) {
          parts.add(
            WordPart(text: stemInTail, kind: WordPartKind.stem),
          );
        }
        parts.add(
          WordPart(
            text: suffixInTail,
            kind: WordPartKind.suffix,
            meaning: kWordSuffixes[suffixInTail] ?? '',
          ),
        );
      } else {
        parts.add(WordPart(text: tail, kind: WordPartKind.stem));
      }
    }
  } else {
    parts.add(WordPart(text: middle, kind: WordPartKind.stem));
  }
  if (attempt.suffix != null) {
    parts.add(attempt.suffix!);
  }
  return _Decomposition(parts: parts, roots: roots);
}

/// 词干是否是词典里真实存在的单词（含常见词形变化）。
Future<bool> _isRealWord(
  String stem,
  OfflineWordDictionary dictionary,
) async {
  if (stem.length < 4) {
    return false;
  }
  if (await dictionary.lookup(stem) != null) {
    return true;
  }
  // 词形还原后的候选至少 4 个字母，避免 est 这种碎片被当成词。
  for (final String candidate in <String>[
    if (stem.endsWith('i')) '${stem.substring(0, stem.length - 1)}y',
    ...englishLemmaCandidates(stem),
  ]) {
    if (candidate.length >= 4 && await dictionary.lookup(candidate) != null) {
      return true;
    }
  }
  return false;
}

class _Attempt {
  const _Attempt({
    required this.word,
    this.prefix,
    this.suffix,
    this.root,
    this.middleIsWord = false,
    this.score = 0,
  });

  final String word;
  final WordPart? prefix;
  final WordPart? suffix;
  final _RootMatch? root;
  final bool middleIsWord;
  final int score;

  /// 去掉前缀与后缀后剩下的部分。
  String get middle {
    String text = word;
    final WordPart? prefixPart = prefix;
    if (prefixPart != null) {
      text = text.substring(prefixPart.text.length);
    }
    final WordPart? suffixPart = suffix;
    if (suffixPart != null) {
      text = text.substring(0, text.length - suffixPart.text.length);
    }
    return text;
  }

  int get affixCount => (prefix == null ? 0 : 1) + (suffix == null ? 0 : 1);

  _Attempt copyWith({_RootMatch? root, bool? middleIsWord, int? score}) {
    return _Attempt(
      word: word,
      prefix: prefix,
      suffix: suffix,
      root: root ?? this.root,
      middleIsWord: middleIsWord ?? this.middleIsWord,
      score: score ?? this.score,
    );
  }
}

/// 可能的前缀（最多 [limit] 个，长的优先）。
List<WordPart> _prefixCandidates(String word, {int limit = 3}) {
  final List<WordPart> result = <WordPart>[];
  for (final MapEntry<String, String> entry in _prefixesByLength) {
    if (result.length >= limit) {
      break;
    }
    if (!word.startsWith(entry.key)) {
      continue;
    }
    final String rest = word.substring(entry.key.length);
    if (rest.length < 3 || rest == entry.key) {
      continue;
    }
    result.add(
      WordPart(
        text: entry.key,
        kind: WordPartKind.prefix,
        meaning: entry.value,
      ),
    );
  }
  return result;
}

/// 可能的后缀（最多 [limit] 个，长的优先）。
List<WordPart> _suffixCandidates(String word, {int limit = 3}) {
  final List<WordPart> result = <WordPart>[];
  for (final MapEntry<String, String> entry in _suffixesByLength) {
    if (result.length >= limit) {
      break;
    }
    if (!word.endsWith(entry.key)) {
      continue;
    }
    final String stem = word.substring(0, word.length - entry.key.length);
    if (stem.length < 3) {
      continue;
    }
    result.add(
      WordPart(
        text: entry.key,
        kind: WordPartKind.suffix,
        meaning: entry.value,
      ),
    );
  }
  return result;
}

class _RootMatch {
  const _RootMatch({
    required this.root,
    required this.meaning,
    required this.start,
  });

  final String root;
  final String meaning;
  final int start;
}

_RootMatch? _matchRoot(String middle) {
  if (middle.length < 3) {
    return null;
  }
  _RootMatch? best;
  for (final MapEntry<String, String> entry in _rootsByLength) {
    final int index = middle.indexOf(entry.key);
    if (index < 0) {
      continue;
    }
    // 词根前面最多允许一个连接元音（bi-o-logy），后面允许 1~2 个连接字母
    // 或直接跟一个已知后缀（vis-ible、duct-ion）。
    final int tail = middle.length - index - entry.key.length;
    final String tailText = middle.substring(index + entry.key.length);
    final bool tailLooksLikeSuffix =
        tailText.isEmpty || _startsWithKnownSuffix(tailText);
    if (index > 1 ||
        (index == 1 && !'aeiou'.contains(middle[0])) ||
        (tail > 2 && !tailLooksLikeSuffix)) {
      continue;
    }
    final _RootMatch candidate = _RootMatch(
      root: entry.key,
      meaning: entry.value,
      start: index,
    );
    // 取最长词根；同样长度时取更靠前的。
    if (best == null ||
        candidate.root.length > best.root.length ||
        (candidate.root.length == best.root.length &&
            candidate.start < best.start)) {
      best = candidate;
    }
  }
  return best;
}

/// 词根家族：含义相同的拼写变体（spec / spect / spic）。
final Map<String, Set<String>> _rootFamilies = <String, Set<String>>{
  for (final MapEntry<String, String> entry in kWordRoots.entries)
    entry.value: <String>{
      for (final MapEntry<String, String> other in kWordRoots.entries)
        if (other.value == entry.value) other.key,
    },
};

bool _startsWithKnownSuffix(String text) => _knownSuffixIn(text).isNotEmpty;

/// [text] 末尾是否是已知后缀（返回该后缀，否则空串）。
String _knownSuffixIn(String text) {
  for (final MapEntry<String, String> entry in _suffixesByLength) {
    if (text.endsWith(entry.key) && text.length - entry.key.length >= 0) {
      return entry.key;
    }
  }
  return '';
}

/// 同根词过滤：只保留“前缀/结尾都说得通”的词，避免 speck、blog 这类
/// 只是恰好包含同一串字母的词混进来。
bool isSameRootFamily(String word, String root) {
  final Set<String> family = _rootFamilies[kWordRoots[root]] ?? <String>{root};
  final List<String> spellings = family.toList()
    ..sort((String a, String b) => b.length.compareTo(a.length));
  for (final String spelling in spellings) {
    if (_matchesRootSpelling(word, spelling)) {
      return true;
    }
  }
  return false;
}

bool _matchesRootSpelling(String word, String spelling) {
  if (word == spelling) {
    return true;
  }
  if (word.startsWith(spelling)) {
    final String tail = word.substring(spelling.length);
    return tail.isEmpty || _startsWithKnownSuffix(tail);
  }
  for (final MapEntry<String, String> prefix in _prefixesByLength) {
    if (!word.startsWith(prefix.key)) {
      continue;
    }
    final String rest = word.substring(prefix.key.length);
    if (rest == spelling) {
      return true;
    }
    if (rest.startsWith(spelling)) {
      final String tail = rest.substring(spelling.length);
      if (tail.isEmpty || _startsWithKnownSuffix(tail)) {
        return true;
      }
    }
  }
  return false;
}

List<MapEntry<String, String>> _byLengthDesc(Map<String, String> table) {
  final List<MapEntry<String, String>> entries = table.entries.toList()
    ..sort((MapEntry<String, String> a, MapEntry<String, String> b) {
      final int byLength = b.key.length.compareTo(a.key.length);
      return byLength != 0 ? byLength : a.key.compareTo(b.key);
    });
  return entries;
}

final List<MapEntry<String, String>> _prefixesByLength = _byLengthDesc(
  kWordPrefixes,
);
final List<MapEntry<String, String>> _suffixesByLength = _byLengthDesc(
  kWordSuffixes,
);
final List<MapEntry<String, String>> _rootsByLength = _byLengthDesc(kWordRoots);
