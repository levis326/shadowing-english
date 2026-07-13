import 'package:common_learn_english/features/growth/presentation/growth_provider.dart';
import 'package:common_learn_english/features/home/presentation/learning_dashboard_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'user growth is deterministically derived from real learning activity',
    () {
      final DateTime now = DateTime.now();
      final String todayKey =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final LearningDailyRecord today = LearningDailyRecord(
        dayKey: todayKey,
        studyMilliseconds: const Duration(minutes: 20).inMilliseconds,
        learnedSentenceKeys: const <String>{
          'episode-1:line-1',
          'episode-1:line-2',
        },
        shadowingCount: 0,
        savedPhraseCount: 1,
        checkedIn: true,
      );
      final UserGrowth growth = UserGrowth.fromLearningActivity(
        activity: LearningActivityState(
          records: <String, LearningDailyRecord>{todayKey: today},
        ),
        phraseCount: 3,
        activeCourse: null,
        completedVideoCount: 1,
      );

      expect(growth.experience, 31);
      expect(growth.level, 1);
      expect(growth.currentXP, 31);
      expect(growth.today.studyMinutes, 20);
      expect(growth.completedVideoCount, 1);
    },
  );

  test('every level has a deterministic cumulative XP requirement', () {
    expect(UserGrowth.experienceToReachLevel(1), 0);
    expect(UserGrowth.experienceToReachLevel(2), 1847);
    expect(UserGrowth.experienceToReachLevel(3), 4094);
    expect(UserGrowth.experienceToReachLevel(4), 6741);
    expect(UserGrowth.experienceToReachLevel(5), 9788);
    expect(UserGrowth.experienceToReachLevel(10), 31023);
  });

  test('current-level and cumulative XP use the same next-level threshold', () {
    final DateTime now = DateTime.now();
    final String todayKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final Map<String, LearningDailyRecord> records =
        <String, LearningDailyRecord>{
          for (int index = 0; index < 140; index++)
            'day-$index': LearningDailyRecord(
              dayKey: 'day-$index',
              studyMilliseconds: const Duration(minutes: 30).inMilliseconds,
              learnedSentenceKeys: const <String>{},
              shadowingCount: 0,
              savedPhraseCount: 0,
              checkedIn: false,
            ),
          todayKey: LearningDailyRecord(
            dayKey: todayKey,
            studyMilliseconds: const Duration(minutes: 30).inMilliseconds,
            learnedSentenceKeys: List<String>.generate(
              10,
              (int index) => 'sentence-$index',
            ).toSet(),
            shadowingCount: 0,
            savedPhraseCount: 0,
            checkedIn: false,
          ),
        };
    final UserGrowth growth = UserGrowth.fromLearningActivity(
      activity: LearningActivityState(records: records),
      phraseCount: 0,
      activeCourse: null,
      completedVideoCount: 0,
    );

    expect(growth.experience, 4250);
    expect(growth.level, 3);
    expect(growth.currentXP, 156);
    expect(growth.nextLevelXP, 2647);
    expect(growth.nextLevelTotalXP, 6741);
    expect(growth.remainingXPToNextLevel, 2491);
  });

  test('daily growth values are capped to prevent one-session level jumps', () {
    final LearningDailyRecord record = LearningDailyRecord(
      dayKey: '2026-07-11',
      studyMilliseconds: const Duration(minutes: 120).inMilliseconds,
      learnedSentenceKeys: List<String>.generate(
        100,
        (int index) => 'sentence-$index',
      ).toSet(),
      shadowingCount: 0,
      savedPhraseCount: 50,
      checkedIn: true,
    );

    expect(UserGrowth.studyXPForMinutes(120), 30);
    expect(UserGrowth.sentenceXPForCount(100), 40);
    expect(UserGrowth.phraseXPForCount(50), 10);
    expect(UserGrowth.experienceForDailyRecord(record), 85);
  });
}
