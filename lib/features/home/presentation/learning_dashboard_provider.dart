import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';

const int _checkInStudyMinuteTarget = 10;
const int _checkInSentenceTarget = 30;
const int _checkInShadowingTarget = 5;
const int _checkInPhraseTarget = 3;
const String _learningActivityStorageKey = 'learning_activity_v1';
const int _learningHistoryDays = 365;

final NotifierProvider<LearningActivityNotifier, LearningActivityState>
learningActivityProvider =
    NotifierProvider<LearningActivityNotifier, LearningActivityState>(
      LearningActivityNotifier.new,
    );

final Provider<LearningDashboardStats> learningDashboardProvider =
    Provider<LearningDashboardStats>((Ref ref) {
      final List<LibraryCourseData> courses = ref.watch(libraryCatalogProvider);
      final LearningActivityState activity = ref.watch(
        learningActivityProvider,
      );
      final LibraryCourseData currentCourse = courses.isEmpty
          ? emptyLibraryCourse
          : courses.first;

      return LearningDashboardStats(
        streakDays: activity.streakDays,
        totalStudyDays: activity.totalStudyDays,
        totalStudyMinutes: activity.totalStudyMinutes,
        todayStudyMinutes: activity.todayStudyMinutes,
        todaySentenceCount: activity.today.learnedSentenceKeys.length,
        todayShadowingCount: activity.today.shadowingCount,
        todaySavedPhrases: activity.today.savedPhraseCount,
        todayProgressPercent: _buildTodayProgressPercent(activity.today),
        checkedIn: activity.today.checkedIn,
        currentCourseTitle: currentCourse.title,
        currentCourseProgress: currentCourse.progressPercent,
        weeklyTrend: activity.buildTrend(days: 7, bucketDays: 1),
        monthlyTrend: activity.buildTrend(days: 30, bucketDays: 7),
        quarterlyTrend: activity.buildTrend(days: 90, bucketDays: 30),
      );
    });

int _buildTodayProgressPercent(LearningDailyRecord record) {
  final int studyScore = min(
    25,
    (record.studyMilliseconds * 25) ~/
        const Duration(minutes: _checkInStudyMinuteTarget).inMilliseconds,
  );
  final int sentenceScore = _buildProgressPart(
    value: record.learnedSentenceKeys.length,
    target: _checkInSentenceTarget,
  );
  final int shadowingScore = _buildProgressPart(
    value: record.shadowingCount,
    target: _checkInShadowingTarget,
  );
  final int phraseScore = _buildProgressPart(
    value: record.savedPhraseCount,
    target: _checkInPhraseTarget,
  );
  return min(100, studyScore + sentenceScore + shadowingScore + phraseScore);
}

int _buildProgressPart({required int value, required int target}) {
  return (value.clamp(0, target) * 25) ~/ target;
}

class LearningActivityNotifier extends Notifier<LearningActivityState> {
  Timer? _persistTimer;

  @override
  LearningActivityState build() {
    ref.onDispose(() => _persistTimer?.cancel());
    return LearningActivityState.fromJson(
      Hive.isBoxOpen('prefs')
          ? Hive.box<String>('prefs').get(_learningActivityStorageKey)
          : null,
    );
  }

  void recordPlayDuration({required Duration duration, DateTime? occurredAt}) {
    if (duration <= Duration.zero) {
      return;
    }
    _updateDay(occurredAt ?? DateTime.now(), (LearningDailyRecord record) {
      return record.copyWith(
        studyMilliseconds: record.studyMilliseconds + duration.inMilliseconds,
      );
    });
  }

  void recordSentenceStudy({
    required String sentenceKey,
    DateTime? occurredAt,
  }) {
    _updateDay(occurredAt ?? DateTime.now(), (LearningDailyRecord record) {
      if (record.learnedSentenceKeys.contains(sentenceKey)) {
        return record;
      }
      return record.copyWith(
        learnedSentenceKeys: <String>{
          ...record.learnedSentenceKeys,
          sentenceKey,
        },
      );
    });
  }

  void recordShadowingToggle({required bool enabled, DateTime? occurredAt}) {
    if (!enabled) {
      return;
    }
    _updateDay(occurredAt ?? DateTime.now(), (LearningDailyRecord record) {
      return record.copyWith(shadowingCount: record.shadowingCount + 1);
    });
  }

  void recordPhraseSaved({DateTime? occurredAt}) {
    _updateDay(occurredAt ?? DateTime.now(), (LearningDailyRecord record) {
      return record.copyWith(savedPhraseCount: record.savedPhraseCount + 1);
    });
  }

  void _updateDay(
    DateTime occurredAt,
    LearningDailyRecord Function(LearningDailyRecord record) update,
  ) {
    final String dayKey = _dayKey(occurredAt);
    final LearningDailyRecord previous =
        state.records[dayKey] ?? LearningDailyRecord.empty(dayKey);
    LearningDailyRecord next = update(previous);
    next = next.copyWith(checkedIn: _meetsCheckInRequirements(next));
    if (next == previous) {
      return;
    }
    final Map<String, LearningDailyRecord> records =
        <String, LearningDailyRecord>{...state.records, dayKey: next};
    final DateTime oldestDay = DateTime.now().subtract(
      const Duration(days: _learningHistoryDays),
    );
    records.removeWhere(
      (String key, _) => DateTime.tryParse(key)?.isBefore(oldestDay) ?? true,
    );
    state = LearningActivityState(records: records);
    _schedulePersist();
  }

  bool _meetsCheckInRequirements(LearningDailyRecord record) {
    return record.studyMilliseconds >=
            const Duration(minutes: _checkInStudyMinuteTarget).inMilliseconds ||
        record.learnedSentenceKeys.length >= _checkInSentenceTarget ||
        record.shadowingCount >= _checkInShadowingTarget ||
        record.savedPhraseCount >= _checkInPhraseTarget;
  }

  void _schedulePersist() {
    if (!Hive.isBoxOpen('prefs') || _persistTimer != null) {
      return;
    }
    _persistTimer = Timer(const Duration(seconds: 1), () {
      _persistTimer = null;
      unawaited(
        Hive.box<String>(
          'prefs',
        ).put(_learningActivityStorageKey, state.toJson()),
      );
    });
  }

  /// Clears all learning activity records (used by
  /// 设置 → 清除应用缓存与生词记录).
  Future<void> clearAll() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    state = const LearningActivityState(
      records: <String, LearningDailyRecord>{},
    );
    if (Hive.isBoxOpen('prefs')) {
      await Hive.box<String>('prefs').delete(_learningActivityStorageKey);
    }
  }
}

class LearningActivityState {
  const LearningActivityState({required this.records});

  factory LearningActivityState.fromJson(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const LearningActivityState(
        records: <String, LearningDailyRecord>{},
      );
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?> || decoded['records'] is! Map) {
        return const LearningActivityState(
          records: <String, LearningDailyRecord>{},
        );
      }
      final Map<Object?, Object?> values =
          decoded['records']! as Map<Object?, Object?>;
      return LearningActivityState(
        records: <String, LearningDailyRecord>{
          for (final MapEntry<Object?, Object?> entry in values.entries)
            if (entry.key is String && entry.value is Map)
              entry.key! as String: LearningDailyRecord.fromJson(
                entry.key! as String,
                Map<String, Object?>.from(
                  entry.value! as Map<Object?, Object?>,
                ),
              ),
        },
      );
    } catch (_) {
      return const LearningActivityState(
        records: <String, LearningDailyRecord>{},
      );
    }
  }

  final Map<String, LearningDailyRecord> records;

  LearningDailyRecord get today =>
      records[_dayKey(DateTime.now())] ??
      LearningDailyRecord.empty(_dayKey(DateTime.now()));

  int get todayStudyMinutes => today.studyMilliseconds ~/ 60000;

  int get totalStudyDays => records.values
      .where((LearningDailyRecord record) => record.checkedIn)
      .length;

  int get totalStudyMinutes => records.values.fold<int>(
    0,
    (int total, LearningDailyRecord record) =>
        total + record.studyMilliseconds ~/ 60000,
  );

  int get streakDays {
    DateTime day = DateTime.now();
    if (records[_dayKey(day)]?.checkedIn != true) {
      day = day.subtract(const Duration(days: 1));
    }
    int streak = 0;
    while (records[_dayKey(day)]?.checkedIn ?? false) {
      streak += 1;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  List<LearningTrendPoint> buildTrend({
    required int days,
    required int bucketDays,
  }) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime firstDay = today.subtract(Duration(days: days - 1));
    final List<LearningTrendPoint> result = <LearningTrendPoint>[];
    for (int offset = 0; offset < days; offset += bucketDays) {
      final DateTime start = firstDay.add(Duration(days: offset));
      final DateTime end = DateTime(
        start.year,
        start.month,
        start.day + min(bucketDays - 1, days - offset - 1),
      );
      int milliseconds = 0;
      int activeDays = 0;
      for (
        DateTime day = start;
        !day.isAfter(end);
        day = day.add(const Duration(days: 1))
      ) {
        final LearningDailyRecord record =
            records[_dayKey(day)] ?? LearningDailyRecord.empty(_dayKey(day));
        milliseconds += record.studyMilliseconds;
        if (record.hasActivity) {
          activeDays += 1;
        }
      }
      result.add(
        LearningTrendPoint(
          label: '${start.month}/${start.day}',
          studyMinutes: milliseconds ~/ 60000,
          activeDays: activeDays,
        ),
      );
    }
    return result;
  }

  String toJson() {
    return jsonEncode(<String, Object?>{
      'records': records.map(
        (String key, LearningDailyRecord value) =>
            MapEntry<String, Object?>(key, value.toJson()),
      ),
    });
  }
}

class LearningDailyRecord {
  const LearningDailyRecord({
    required this.dayKey,
    required this.studyMilliseconds,
    required this.learnedSentenceKeys,
    required this.shadowingCount,
    required this.savedPhraseCount,
    required this.checkedIn,
  });

  factory LearningDailyRecord.fromJson(
    String dayKey,
    Map<String, Object?> json,
  ) {
    return LearningDailyRecord(
      dayKey: dayKey,
      studyMilliseconds: json['studyMilliseconds'] as int? ?? 0,
      learnedSentenceKeys:
          ((json['learnedSentenceKeys'] as List<Object?>?) ?? const <Object?>[])
              .cast<String>()
              .toSet(),
      shadowingCount: json['shadowingCount'] as int? ?? 0,
      savedPhraseCount: json['savedPhraseCount'] as int? ?? 0,
      checkedIn: json['checkedIn'] as bool? ?? false,
    );
  }

  factory LearningDailyRecord.empty(String dayKey) => LearningDailyRecord(
    dayKey: dayKey,
    studyMilliseconds: 0,
    learnedSentenceKeys: const <String>{},
    shadowingCount: 0,
    savedPhraseCount: 0,
    checkedIn: false,
  );

  final String dayKey;
  final int studyMilliseconds;
  final Set<String> learnedSentenceKeys;
  final int shadowingCount;
  final int savedPhraseCount;
  final bool checkedIn;

  bool get hasActivity =>
      studyMilliseconds > 0 ||
      learnedSentenceKeys.isNotEmpty ||
      shadowingCount > 0 ||
      savedPhraseCount > 0;

  LearningDailyRecord copyWith({
    int? studyMilliseconds,
    Set<String>? learnedSentenceKeys,
    int? shadowingCount,
    int? savedPhraseCount,
    bool? checkedIn,
  }) {
    return LearningDailyRecord(
      dayKey: dayKey,
      studyMilliseconds: studyMilliseconds ?? this.studyMilliseconds,
      learnedSentenceKeys: learnedSentenceKeys ?? this.learnedSentenceKeys,
      shadowingCount: shadowingCount ?? this.shadowingCount,
      savedPhraseCount: savedPhraseCount ?? this.savedPhraseCount,
      checkedIn: checkedIn ?? this.checkedIn,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'studyMilliseconds': studyMilliseconds,
    'learnedSentenceKeys': learnedSentenceKeys.toList(growable: false),
    'shadowingCount': shadowingCount,
    'savedPhraseCount': savedPhraseCount,
    'checkedIn': checkedIn,
  };
}

class LearningTrendPoint {
  const LearningTrendPoint({
    required this.label,
    required this.studyMinutes,
    required this.activeDays,
  });

  final String label;
  final int studyMinutes;
  final int activeDays;
}

class LearningDashboardStats {
  const LearningDashboardStats({
    required this.streakDays,
    required this.totalStudyDays,
    required this.totalStudyMinutes,
    required this.todayStudyMinutes,
    required this.todaySentenceCount,
    required this.todayShadowingCount,
    required this.todaySavedPhrases,
    required this.todayProgressPercent,
    required this.checkedIn,
    required this.currentCourseTitle,
    required this.currentCourseProgress,
    required this.weeklyTrend,
    required this.monthlyTrend,
    required this.quarterlyTrend,
  });

  final int streakDays;
  final int totalStudyDays;
  final int totalStudyMinutes;
  final int todayStudyMinutes;
  final int todaySentenceCount;
  final int todayShadowingCount;
  final int todaySavedPhrases;
  final int todayProgressPercent;
  final bool checkedIn;
  final String currentCourseTitle;
  final int currentCourseProgress;
  final List<LearningTrendPoint> weeklyTrend;
  final List<LearningTrendPoint> monthlyTrend;
  final List<LearningTrendPoint> quarterlyTrend;

  int get remainingMinutesToCheckIn {
    final int left = _checkInStudyMinuteTarget - todayStudyMinutes;
    return left > 0 ? left : 0;
  }
}

String _dayKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
