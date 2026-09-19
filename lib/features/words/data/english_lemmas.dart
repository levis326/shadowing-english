/// 英语词形还原：把复数和分词等形态变回初始形态。
///
/// 只做“够用且可控”的规则 + 常见不规则表，不引入大型 NLP 依赖：
/// `consists → consist`、`studies → study`、`stopped → stop`、
/// `running → run`、`making → make`、`children → child`、`went → go`。
library;

/// 生成候选原形（按可信度排序，不含输入本身）。
List<String> englishLemmaCandidates(String rawWord) {
  final String word = normalizeEnglishToken(rawWord);
  if (word.isEmpty || word.contains(' ')) {
    return const <String>[];
  }
  final List<String> result = <String>[];
  void add(String candidate) {
    if (candidate.length >= 2 && candidate != word && !result.contains(candidate)) {
      result.add(candidate);
    }
  }

  final int length = word.length;
  // 名词复数 / 动词三单
  if (word.endsWith('ies') && length > 4) {
    add('${word.substring(0, length - 3)}y'); // studies → study
  }
  if (word.endsWith('es') && length > 3) {
    add(word.substring(0, length - 2)); // boxes → box
  }
  if (word.endsWith('s') && !word.endsWith('ss') && length > 2) {
    add(word.substring(0, length - 1)); // books → book
  }
  // 过去式 / 过去分词
  if (word.endsWith('ied') && length > 4) {
    add('${word.substring(0, length - 3)}y'); // studied → study
  }
  if (word.endsWith('ed') && length > 3) {
    final String stem = word.substring(0, length - 2);
    add(stem); // played → play
    if (stem.isNotEmpty && 'bdgklmnprt'.contains(stem[stem.length - 1])) {
      add('$stem${stem[stem.length - 1]}'); // stopped → stop
    }
    add('${word.substring(0, length - 1)}e'); // loved → love
  }
  // 现在分词 / 动名词
  if (word.endsWith('ing') && length > 4) {
    final String stem = word.substring(0, length - 3);
    add(stem); // drinking → drink
    add('${stem}e'); // making → make
    if (stem.length > 1 &&
        stem[stem.length - 1] == stem[stem.length - 2]) {
      add(stem.substring(0, stem.length - 1)); // running → run
    }
  }
  // 比较级 / 最高级 / 副词
  if (word.endsWith('est') && length > 4) {
    final String stem = word.substring(0, length - 3);
    if (stem.length > 1 && stem[stem.length - 1] == stem[stem.length - 2]) {
      add(stem.substring(0, stem.length - 1)); // biggest → big
    }
    add(stem); // fastest → fast
  }
  if (word.endsWith('er') && length > 3) {
    final String stem = word.substring(0, length - 2);
    if (stem.length > 1 && stem[stem.length - 1] == stem[stem.length - 2]) {
      add(stem.substring(0, stem.length - 1)); // bigger → big
    }
    add(stem); // faster → fast
  }
  if (word.endsWith('ly') && length > 4) {
    add(word.substring(0, length - 2)); // quickly → quick
    if (word.endsWith('ily')) {
      add('${word.substring(0, length - 3)}y'); // happily → happy
    }
  }
  final String? irregular = kIrregularLemmas[word];
  if (irregular != null) {
    add(irregular);
  }
  return result;
}

/// 最常见的原形：优先不规则表，其次只用**高置信度**的规则
/// （复数、三单、-ing、-ed；不含 -er/-est/-ly，避免把 water 变成 wat）。
///
/// 需要“词典里真的存在这个形式”时请用 `OfflineWordDictionary.baseForm()`，
/// 它会逐个候选去词典确认，因而能正确处理 bigger → big、happily → happy。
String englishLemma(String rawWord) {
  final String word = normalizeEnglishToken(rawWord);
  if (word.isEmpty || word.contains(' ')) {
    return word;
  }
  final String? irregular = kIrregularLemmas[word];
  if (irregular != null) {
    return irregular;
  }
  final List<String> candidates = _highConfidenceCandidates(word);
  return candidates.isEmpty ? word : candidates.first;
}

List<String> _highConfidenceCandidates(String word) {
  final List<String> result = <String>[];
  void add(String candidate) {
    if (candidate.length >= 2 && candidate != word && !result.contains(candidate)) {
      result.add(candidate);
    }
  }

  final int length = word.length;
  if (word.endsWith('ies') && length > 4) {
    add('${word.substring(0, length - 3)}y');
  }
  if (word.endsWith('ied') && length > 4) {
    add('${word.substring(0, length - 3)}y');
  }
  if (word.endsWith('es') && length > 3) {
    add(word.substring(0, length - 2));
  }
  if (word.endsWith('s') && !word.endsWith('ss') && length > 3) {
    add(word.substring(0, length - 1));
  }
  if (word.endsWith('ed') && length > 3) {
    final String stem = word.substring(0, length - 2);
    if (stem.length > 1 && stem[stem.length - 1] == stem[stem.length - 2]) {
      add(stem.substring(0, stem.length - 1));
    }
    add(stem);
    add('${word.substring(0, length - 1)}e');
  }
  if (word.endsWith('ing') && length > 4) {
    final String stem = word.substring(0, length - 3);
    if (stem.length > 1 && stem[stem.length - 1] == stem[stem.length - 2]) {
      add(stem.substring(0, stem.length - 1));
    }
    add(stem);
    add('${stem}e');
  }
  return result;
}

/// 小写、去掉首尾标点，保留词内连字符与撇号。
String normalizeEnglishToken(String rawWord) {
  return rawWord
      .trim()
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r'^[^a-z0-9]+|[^a-z0-9]+$'), '');
}

/// 常见不规则变化（含 be/have/do 与常见不规则动词、复数、比较级）。
const Map<String, String> kIrregularLemmas = <String, String>{
  'am': 'be',
  'is': 'be',
  'are': 'be',
  'was': 'be',
  'were': 'be',
  'been': 'be',
  'being': 'be',
  'has': 'have',
  'had': 'have',
  'having': 'have',
  'does': 'do',
  'did': 'do',
  'done': 'do',
  'doing': 'do',
  'went': 'go',
  'gone': 'go',
  'said': 'say',
  'made': 'make',
  'took': 'take',
  'taken': 'take',
  'came': 'come',
  'saw': 'see',
  'seen': 'see',
  'got': 'get',
  'gotten': 'get',
  'gave': 'give',
  'given': 'give',
  'knew': 'know',
  'known': 'know',
  'thought': 'think',
  'told': 'tell',
  'found': 'find',
  'left': 'leave',
  'felt': 'feel',
  'kept': 'keep',
  'met': 'meet',
  'ran': 'run',
  'wrote': 'write',
  'written': 'write',
  'spoke': 'speak',
  'spoken': 'speak',
  'brought': 'bring',
  'bought': 'buy',
  'taught': 'teach',
  'caught': 'catch',
  'drank': 'drink',
  'drunk': 'drink',
  'ate': 'eat',
  'eaten': 'eat',
  'began': 'begin',
  'begun': 'begin',
  'broke': 'break',
  'broken': 'break',
  'chose': 'choose',
  'chosen': 'choose',
  'drove': 'drive',
  'driven': 'drive',
  'fell': 'fall',
  'fallen': 'fall',
  'flew': 'fly',
  'flown': 'fly',
  'forgot': 'forget',
  'forgotten': 'forget',
  'grew': 'grow',
  'grown': 'grow',
  'held': 'hold',
  'hurt': 'hurt',
  'lent': 'lend',
  'lost': 'lose',
  'paid': 'pay',
  'put': 'put',
  'read': 'read',
  'rode': 'ride',
  'ridden': 'ride',
  'rose': 'rise',
  'risen': 'rise',
  'sent': 'send',
  'showed': 'show',
  'shown': 'show',
  'sang': 'sing',
  'sung': 'sing',
  'sat': 'sit',
  'slept': 'sleep',
  'spent': 'spend',
  'stood': 'stand',
  'swam': 'swim',
  'swum': 'swim',
  'threw': 'throw',
  'thrown': 'throw',
  'understood': 'understand',
  'woke': 'wake',
  'woken': 'wake',
  'wore': 'wear',
  'worn': 'wear',
  'won': 'win',
  'children': 'child',
  'men': 'man',
  'women': 'woman',
  'feet': 'foot',
  'teeth': 'tooth',
  'mice': 'mouse',
  'geese': 'goose',
  'people': 'person',
  'better': 'good',
  'best': 'good',
  'worse': 'bad',
  'worst': 'bad',
  'more': 'many',
  'most': 'many',
  'further': 'far',
  'furthest': 'far',
};
