import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'english_lemmas.dart';

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
    final String word = normalizeEnglishToken(rawWord);
    if (word.isEmpty) {
      return null;
    }
    final Map<String, OfflineWordDefinition> entries = await _entries();
    final OfflineWordDefinition? direct = entries[word];
    if (direct != null) {
      return direct;
    }
    // 短语（多个词）不做词形还原，交给翻译服务。
    if (word.contains(' ')) {
      return null;
    }
    for (final String candidate in englishLemmaCandidates(word)) {
      final OfflineWordDefinition? definition = entries[candidate];
      if (definition != null) {
        return definition;
      }
    }
    return null;
  }

  /// 单词的初始形态：优先返回词典里真的存在的原形
  /// （`consists → consist`、`studies → study`、`children → child`），
  /// 词典里查不到时按规则还原，最后退回原词。
  Future<String> baseForm(String rawWord) async {
    final String word = normalizeEnglishToken(rawWord);
    if (word.isEmpty || word.contains(' ')) {
      return word;
    }
    final Map<String, OfflineWordDefinition> entries = await _entries();
    if (entries.containsKey(word)) {
      // 本身已经是词表里的形式（例如 bus / series）就直接用。
      if (!_looksInflected(word)) {
        return word;
      }
    }
    for (final String candidate in englishLemmaCandidates(word)) {
      if (entries.containsKey(candidate)) {
        return candidate;
      }
    }
    final String lemma = englishLemma(word);
    return entries.containsKey(lemma) ? lemma : word;
  }

  /// 词表里包含某个片段（词根）的单词，短的优先，用于“同根词”。
  Future<List<String>> wordsContaining(
    String fragment, {
    String exclude = '',
    int limit = 12,
  }) async {
    final String needle = normalizeEnglishToken(fragment);
    if (needle.isEmpty) {
      return const <String>[];
    }
    final Map<String, OfflineWordDefinition> entries = await _entries();
    final String excludeWord = exclude.trim().toLowerCase();
    final List<String> hits = <String>[
      for (final String word in entries.keys)
        if (word != excludeWord &&
            word.length <= needle.length + 8 &&
            word.contains(needle))
          word,
    ];
    return (hits
          ..sort((String a, String b) {
            final int byLength = a.length.compareTo(b.length);
            return byLength != 0 ? byLength : a.compareTo(b);
          }))
        .take(limit)
        .toList(growable: false);
  }

  /// 词组的中文提示：把各组成词在词典里的释义拼起来（离线可用）。
  Future<String> componentGloss(String phrase) async {
    final Map<String, OfflineWordDefinition> entries = await _entries();
    final List<String> parts = <String>[];
    for (final String token in normalizeEnglishToken(phrase).split(' ')) {
      if (token.isEmpty) {
        continue;
      }
      OfflineWordDefinition? definition = entries[token];
      if (definition == null) {
        for (final String candidate in englishLemmaCandidates(token)) {
          definition = entries[candidate];
          if (definition != null) {
            break;
          }
        }
      }
      final String translation = definition?.translation.trim() ?? '';
      if (translation.isNotEmpty) {
        parts.add('$token：$translation');
      }
    }
    return parts.join('；');
  }

  /// 看起来像变形（复数/过去式/分词等）时才继续找原形。
  bool _looksInflected(String word) {
    return englishLemmaCandidates(word).isNotEmpty;
  }

  Future<Map<String, OfflineWordDefinition>> _entries() async =>
      (await (_entriesFuture ??= _load())).cast<String, OfflineWordDefinition>();



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
