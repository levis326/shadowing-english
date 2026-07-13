import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

const String _phraseBookStorageKey = 'phrase_book_v2';
const Set<String> _legacySamplePhraseIds = <String>{
  'phrase-1',
  'phrase-2',
  'phrase-3',
  'phrase-4',
};

final NotifierProvider<PhraseBookNotifier, List<PhraseEntry>>
phraseBookProvider = NotifierProvider<PhraseBookNotifier, List<PhraseEntry>>(
  PhraseBookNotifier.new,
);

class PhraseEntry {
  const PhraseEntry({
    required this.id,
    required this.english,
    required this.chinese,
    required this.course,
    required this.episode,
    required this.time,
    required this.rating,
    required this.needsReview,
    required this.today,
    this.courseId,
    this.episodeId,
    this.startTime,
    this.endTime,
    this.note,
    this.collectedAt,
    this.lastReviewedAt,
    this.nextReviewAt,
    this.reviewCount = 0,
    this.lapseCount = 0,
  });

  factory PhraseEntry.fromJson(Map<String, Object?> json) {
    return PhraseEntry(
      id: json['id']! as String,
      english: json['english']! as String,
      chinese: json['chinese']! as String,
      course: json['course']! as String,
      episode: json['episode']! as String,
      time: json['time']! as String,
      rating: json['rating'] as int? ?? 1,
      needsReview: json['needsReview'] as bool? ?? true,
      today: json['today'] as bool? ?? false,
      courseId: json['courseId'] as String?,
      episodeId: json['episodeId'] as String?,
      startTime: json['startTime'] as String?,
      endTime: json['endTime'] as String?,
      note: json['note'] as String?,
      collectedAt: json['collectedAt'] as String?,
      lastReviewedAt: json['lastReviewedAt'] as String?,
      nextReviewAt: json['nextReviewAt'] as String?,
      reviewCount: json['reviewCount'] as int? ?? 0,
      lapseCount: json['lapseCount'] as int? ?? 0,
    );
  }

  final String id;
  final String english;
  final String chinese;
  final String course;
  final String episode;
  final String time;
  final int rating;
  final bool needsReview;
  final bool today;
  final String? courseId;
  final String? episodeId;
  final String? startTime;
  final String? endTime;
  final String? note;
  final String? collectedAt;
  final String? lastReviewedAt;
  final String? nextReviewAt;
  final int reviewCount;
  final int lapseCount;

  bool isDue([DateTime? now]) {
    if (needsReview) return true;
    final DateTime? next = DateTime.tryParse(nextReviewAt ?? '');
    return next != null && !next.isAfter(now ?? DateTime.now());
  }

  bool get isMastered => rating >= 5;

  PhraseEntry copyWith({
    String? id,
    String? english,
    String? chinese,
    String? course,
    String? episode,
    String? time,
    int? rating,
    bool? needsReview,
    bool? today,
    String? courseId,
    String? episodeId,
    String? startTime,
    String? endTime,
    String? note,
    String? collectedAt,
    String? lastReviewedAt,
    String? nextReviewAt,
    int? reviewCount,
    int? lapseCount,
  }) {
    return PhraseEntry(
      id: id ?? this.id,
      english: english ?? this.english,
      chinese: chinese ?? this.chinese,
      course: course ?? this.course,
      episode: episode ?? this.episode,
      time: time ?? this.time,
      rating: rating ?? this.rating,
      needsReview: needsReview ?? this.needsReview,
      today: today ?? this.today,
      courseId: courseId ?? this.courseId,
      episodeId: episodeId ?? this.episodeId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      note: note ?? this.note,
      collectedAt: collectedAt ?? this.collectedAt,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      nextReviewAt: nextReviewAt ?? this.nextReviewAt,
      reviewCount: reviewCount ?? this.reviewCount,
      lapseCount: lapseCount ?? this.lapseCount,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'english': english,
    'chinese': chinese,
    'course': course,
    'episode': episode,
    'time': time,
    'rating': rating,
    'needsReview': needsReview,
    'today': today,
    'courseId': courseId,
    'episodeId': episodeId,
    'startTime': startTime,
    'endTime': endTime,
    'note': note,
    'collectedAt': collectedAt,
    'lastReviewedAt': lastReviewedAt,
    'nextReviewAt': nextReviewAt,
    'reviewCount': reviewCount,
    'lapseCount': lapseCount,
  };
}

class PhraseBookNotifier extends Notifier<List<PhraseEntry>> {
  @override
  List<PhraseEntry> build() {
    if (!Hive.isBoxOpen('prefs')) return const <PhraseEntry>[];
    final String? stored = Hive.box<String>('prefs').get(_phraseBookStorageKey);
    if (stored == null || stored.isEmpty) return const <PhraseEntry>[];
    try {
      return (jsonDecode(stored) as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(PhraseEntry.fromJson)
          .where(
            (PhraseEntry item) => !_legacySamplePhraseIds.contains(item.id),
          )
          .toList(growable: false);
    } catch (_) {
      return const <PhraseEntry>[];
    }
  }

  static String _normalizeKey({
    required String english,
    required String course,
    required String episode,
    required String time,
  }) => '$course|$episode|$time|${english.trim().toLowerCase()}';

  void addPhrase({
    required String english,
    required String chinese,
    required String course,
    required String episode,
    required String time,
    int rating = 1,
    bool needsReview = true,
    bool today = true,
    String? courseId,
    String? episodeId,
    String? startTime,
    String? endTime,
    String? note,
    int reviewCount = 0,
    String? collectedAt,
  }) {
    state = <PhraseEntry>[
      PhraseEntry(
        id: 'phrase-${DateTime.now().microsecondsSinceEpoch}',
        english: english,
        chinese: chinese,
        course: course,
        episode: episode,
        time: time,
        rating: rating,
        needsReview: needsReview,
        today: today,
        courseId: courseId,
        episodeId: episodeId,
        startTime: startTime ?? time,
        endTime: endTime,
        note: note,
        collectedAt: collectedAt ?? DateTime.now().toIso8601String(),
        reviewCount: reviewCount,
      ),
      ...state,
    ];
    unawaited(_persist());
  }

  bool addPhraseIfMissing({
    required String english,
    required String chinese,
    required String course,
    required String episode,
    required String time,
    int rating = 1,
    bool needsReview = true,
    bool today = true,
    String? courseId,
    String? episodeId,
    String? startTime,
    String? endTime,
    String? note,
    String? collectedAt,
    int reviewCount = 0,
  }) {
    final String key = _normalizeKey(
      english: english,
      course: course,
      episode: episode,
      time: time,
    );
    if (state.any(
      (PhraseEntry item) =>
          _normalizeKey(
            english: item.english,
            course: item.course,
            episode: item.episode,
            time: item.time,
          ) ==
          key,
    )) {
      return false;
    }
    addPhrase(
      english: english,
      chinese: chinese,
      course: course,
      episode: episode,
      time: time,
      rating: rating,
      needsReview: needsReview,
      today: today,
      courseId: courseId,
      episodeId: episodeId,
      startTime: startTime,
      endTime: endTime,
      note: note,
      collectedAt: collectedAt,
      reviewCount: reviewCount,
    );
    return true;
  }

  void updatePhrase(
    String id,
    PhraseEntry Function(PhraseEntry current) update,
  ) {
    state = state
        .map((PhraseEntry item) => item.id == id ? update(item) : item)
        .toList(growable: false);
    unawaited(_persist());
  }

  void deletePhrase(String id) {
    state = state.where((PhraseEntry item) => item.id != id).toList();
    unawaited(_persist());
  }

  void markForReview(String id) {
    updatePhrase(
      id,
      (PhraseEntry item) => item.copyWith(
        needsReview: true,
        nextReviewAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  void recordReview(String id, PhraseReviewResult result, {DateTime? now}) {
    final DateTime reviewedAt = now ?? DateTime.now();
    updatePhrase(id, (PhraseEntry item) {
      final int reviewCount = item.reviewCount + 1;
      switch (result) {
        case PhraseReviewResult.needPractice:
          return item.copyWith(
            rating: item.rating > 1 ? item.rating - 1 : 1,
            needsReview: true,
            lastReviewedAt: reviewedAt.toIso8601String(),
            nextReviewAt: reviewedAt.toIso8601String(),
            reviewCount: reviewCount,
            lapseCount: item.lapseCount + 1,
          );
        case PhraseReviewResult.almost:
          return item.copyWith(
            needsReview: false,
            lastReviewedAt: reviewedAt.toIso8601String(),
            nextReviewAt: reviewedAt
                .add(const Duration(days: 1))
                .toIso8601String(),
            reviewCount: reviewCount,
          );
        case PhraseReviewResult.canUse:
          final int nextStage = item.rating < 5 ? item.rating + 1 : 5;
          return item.copyWith(
            rating: nextStage,
            needsReview: false,
            lastReviewedAt: reviewedAt.toIso8601String(),
            nextReviewAt: reviewedAt
                .add(Duration(days: _reviewIntervalDays[nextStage]!))
                .toIso8601String(),
            reviewCount: reviewCount,
          );
      }
    });
  }

  Future<void> _persist() async {
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>('prefs').put(
      _phraseBookStorageKey,
      jsonEncode(state.map((PhraseEntry item) => item.toJson()).toList()),
    );
  }
}

const Map<int, int> _reviewIntervalDays = <int, int>{
  1: 1,
  2: 3,
  3: 7,
  4: 14,
  5: 30,
};

enum PhraseReviewResult { needPractice, almost, canUse }
