import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String _dictionaryAsset = 'assets/dictionary/ecdict_core.json';

final Provider<OfflineWordDictionary> offlineWordDictionaryProvider =
    Provider<OfflineWordDictionary>((Ref ref) => const OfflineWordDictionary());

class OfflineWordDefinition {
  const OfflineWordDefinition({
    required this.translation,
    required this.phonetic,
    required this.partOfSpeech,
  });

  final String translation;
  final String phonetic;
  final String partOfSpeech;
}

class OfflineWordDictionary {
  const OfflineWordDictionary();

  /// 词典资源只需解析一次；多个实例共用同一份缓存。
  static Future<Map<String, OfflineWordDefinition>>? _entriesFuture;

  /// 查词。先查原形，再依次尝试常见词形变化（drinking → drink、
  /// studies → study、stopped → stop 等），本地词典命中就不必依赖联网翻译。
  Future<OfflineWordDefinition?> lookup(String rawWord) async {
    final String word = rawWord.trim().toLowerCase().replaceAll('’', "'");
    if (word.isEmpty) return null;
    final Map<String, OfflineWordDefinition> entries =
        (await (_entriesFuture ??= _load())).cast<String, OfflineWordDefinition>();
    final OfflineWordDefinition? direct = entries[word];
    if (direct != null) return direct;
    // 短语（多个词）不做词形还原，交给翻译服务。
    if (word.contains(' ')) return null;
    for (final String candidate in _lemmaCandidates(word)) {
      final OfflineWordDefinition? definition = entries[candidate];
      if (definition != null) return definition;
    }
    return null;
  }

  /// 生成可能的原形候选（按可信度排序）。
  Iterable<String> _lemmaCandidates(String word) sync* {
    yield* _candidates(word).where((String c) => c.length >= 2 && c != word);
  }

  Iterable<String> _candidates(String word) sync* {
    final int length = word.length;
    // 名词复数 / 动词三单
    if (word.endsWith('ies') && length > 4) {
      yield '${word.substring(0, length - 3)}y'; // studies → study
    }
    if (word.endsWith('es') && length > 3) {
      yield word.substring(0, length - 2); // boxes → box
    }
    if (word.endsWith('s') && !word.endsWith('ss') && length > 2) {
      yield word.substring(0, length - 1); // books → book
    }
    // 过去式 / 过去分词
    if (word.endsWith('ied') && length > 4) {
      yield '${word.substring(0, length - 3)}y'; // studied → study
    }
    if (word.endsWith('ed') && length > 3) {
      final String stem = word.substring(0, length - 2);
      yield stem; // played → play
      if (stem.isNotEmpty) {
        final String last = stem[stem.length - 1];
        if ('bdgklmnprt'.contains(last)) {
          yield '$stem$last'; // stopped → stop
        }
      }
      yield '${word.substring(0, length - 1)}e'; // loved → love
    }
    // 现在分词 / 动名词
    if (word.endsWith('ing') && length > 4) {
      final String stem = word.substring(0, length - 3);
      yield stem; // drinking → drink
      yield '${stem}e'; // making → make
      if (stem.length > 1 && stem[stem.length - 1] == stem[stem.length - 2]) {
        yield stem.substring(0, stem.length - 1); // running → run
      }
    }
    // 比较级 / 最高级 / 副词
    if (word.endsWith('est') && length > 4) {
      yield word.substring(0, length - 3); // biggest → big
    }
    if (word.endsWith('er') && length > 3) {
      yield word.substring(0, length - 2); // bigger → big
    }
    if (word.endsWith('ly') && length > 4) {
      yield word.substring(0, length - 2); // quickly → quick
      if (word.endsWith('ily')) {
        yield '${word.substring(0, length - 3)}y'; // happily → happy
      }
    }
    final String? irregular = _irregularLemmas[word];
    if (irregular != null) {
      yield irregular;
    }
  }

  static const Map<String, String> _irregularLemmas = <String, String>{
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
    'children': 'child',
    'men': 'man',
    'women': 'woman',
    'feet': 'foot',
    'teeth': 'tooth',
    'mice': 'mouse',
    'people': 'person',
    'better': 'good',
    'best': 'good',
    'worse': 'bad',
    'worst': 'bad',
    'more': 'many',
    'most': 'many',
  };

  Future<Map<String, OfflineWordDefinition>> _load() async {
    final Map<String, dynamic> decoded =
        jsonDecode(await rootBundle.loadString(_dictionaryAsset))
            as Map<String, dynamic>;
    final Map<String, dynamic> rawEntries =
        decoded['entries'] as Map<String, dynamic>;
    return rawEntries.map((String word, dynamic value) {
      final List<dynamic> fields = value as List<dynamic>;
      return MapEntry<String, OfflineWordDefinition>(
        word,
        OfflineWordDefinition(
          translation: fields[0] as String,
          phonetic: fields[1] as String,
          partOfSpeech: fields[2] as String,
        ),
      );
    });
  }
}
