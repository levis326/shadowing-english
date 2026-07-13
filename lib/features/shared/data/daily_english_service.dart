import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

const String _dailyEnglishStorageKey = 'daily_english_v1';

final Provider<DailyEnglishService> dailyEnglishServiceProvider =
    Provider<DailyEnglishService>((Ref ref) => DailyEnglishService());

class DailyEnglishPhrase {
  const DailyEnglishPhrase({required this.english, required this.translation});

  factory DailyEnglishPhrase.fromJson(Map<String, dynamic> json) {
    return DailyEnglishPhrase(
      english: json['english'] as String? ?? '',
      translation: json['translation'] as String? ?? '',
    );
  }

  final String english;
  final String translation;

  Map<String, String> toJson() => <String, String>{
    'english': english,
    'translation': translation,
  };
}

class DailyEnglishService {
  DailyEnglishService({
    Dio? client,
    DateTime Function()? now,
    this.loadOverride,
  }) : _client =
           client ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 5),
               receiveTimeout: const Duration(seconds: 5),
             ),
           ),
       _now = now ?? DateTime.now;

  final Dio _client;
  final DateTime Function() _now;
  final Future<List<DailyEnglishPhrase>> Function()? loadOverride;

  Future<List<DailyEnglishPhrase>> loadToday() async {
    if (loadOverride != null) return loadOverride!();
    if (!Hive.isBoxOpen('prefs')) {
      return List<DailyEnglishPhrase>.generate(
        3,
        (int index) => DailyEnglishPhrase(
          english: _fallback[index],
          translation: _fallbackTranslations[index],
        ),
      );
    }

    final String today = _dayKey(_now());
    final List<DailyEnglishPhrase>? cached = _readCache(today);
    if (cached != null) return cached;

    final List<String> sentences = await _loadSentences();
    final List<DailyEnglishPhrase> phrases = await Future.wait(
      sentences.map((String sentence) async {
        return DailyEnglishPhrase(
          english: sentence,
          translation: await _translate(sentence),
        );
      }),
    );
    _writeCache(today, phrases);
    return phrases;
  }

  List<DailyEnglishPhrase>? _readCache(String today) {
    if (!Hive.isBoxOpen('prefs')) return null;
    try {
      final Object? decoded = jsonDecode(
        Hive.box<String>('prefs').get(_dailyEnglishStorageKey) ?? '',
      );
      if (decoded is! Map<Object?, Object?> ||
          decoded['day'] != today ||
          decoded['phrases'] is! List) {
        return null;
      }
      final List<Object?> items = List<Object?>.from(
        decoded['phrases']! as List<Object?>,
      );
      final List<DailyEnglishPhrase> phrases = items
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> item) =>
                DailyEnglishPhrase.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((DailyEnglishPhrase phrase) => phrase.english.isNotEmpty)
          .toList(growable: false);
      return phrases.length == 3 ? phrases : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _loadSentences() async {
    try {
      final List<Response<dynamic>> responses = await Future.wait(
        List<Future<Response<dynamic>>>.generate(
          3,
          (int index) => _client.get<dynamic>(
            'https://api.adviceslip.com/advice',
            queryParameters: <String, int>{
              't': _now().millisecondsSinceEpoch + index,
            },
          ),
        ),
      );
      final List<String> sentences = responses
          .map((Response<dynamic> response) {
            final dynamic data = response.data;
            final Object? slip = data is Map<Object?, Object?>
                ? data['slip']
                : null;
            return slip is Map<Object?, Object?>
                ? (slip['advice'] as String? ?? '').trim()
                : '';
          })
          .where((String value) => value.isNotEmpty && value.length <= 140)
          .toSet()
          .toList(growable: false);
      return sentences.length == 3 ? sentences : _fallback;
    } catch (_) {
      return _fallback;
    }
  }

  Future<String> _translate(String sentence) async {
    try {
      final Response<dynamic> response = await _client.get<dynamic>(
        'https://api.mymemory.translated.net/get',
        queryParameters: <String, String>{
          'q': sentence,
          'langpair': 'en|zh-CN',
        },
      );
      final dynamic data = response.data;
      final Object? responseData = data is Map<Object?, Object?>
          ? data['responseData']
          : null;
      final String translation = responseData is Map<Object?, Object?>
          ? (responseData['translatedText'] as String? ?? '').trim()
          : '';
      return translation.isEmpty ? _fallbackTranslation(sentence) : translation;
    } catch (_) {
      return _fallbackTranslation(sentence);
    }
  }

  void _writeCache(String today, List<DailyEnglishPhrase> phrases) {
    if (!Hive.isBoxOpen('prefs')) return;
    Hive.box<String>('prefs').put(
      _dailyEnglishStorageKey,
      jsonEncode(<String, Object>{
        'day': today,
        'phrases': phrases
            .map((DailyEnglishPhrase item) => item.toJson())
            .toList(),
      }),
    );
  }
}

String _dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _fallbackTranslation(String sentence) {
  final int index = _fallback.indexOf(sentence);
  return index < 0 ? '点击朗读，慢慢体会这句话。' : _fallbackTranslations[index];
}

const List<String> _fallback = <String>[
  'Small steps every day lead to big changes.',
  'The best time to start is now.',
  'Practice makes progress, not perfection.',
];

const List<String> _fallbackTranslations = <String>[
  '每天一小步，终会带来大改变。',
  '开始的最佳时机就是现在。',
  '练习带来进步，而非完美。',
];
