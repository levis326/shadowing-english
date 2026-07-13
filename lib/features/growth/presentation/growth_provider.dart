import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/presentation/learning_dashboard_provider.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../phrases/presentation/phrase_book_provider.dart';

final Provider<UserGrowth> userGrowthProvider = Provider<UserGrowth>((Ref ref) {
  final LearningActivityState activity = ref.watch(learningActivityProvider);
  final List<PhraseEntry> phrases = ref.watch(phraseBookProvider);
  final List<LibraryCourseData> courses = ref.watch(libraryCatalogProvider);
  return UserGrowth.fromLearningActivity(
    activity: activity,
    phraseCount: phrases.length,
    activeCourse: _activeCourse(courses),
    completedVideoCount: courses.fold<int>(
      0,
      (int total, LibraryCourseData course) =>
          total +
          course.episodes
              .where((LibraryEpisodeItem item) => item.completed)
              .length,
    ),
  );
});

LibraryCourseData? _activeCourse(List<LibraryCourseData> courses) {
  if (courses.isEmpty) {
    return null;
  }
  return courses.reduce(
    (LibraryCourseData current, LibraryCourseData candidate) =>
        candidate.progressPercent > current.progressPercent
        ? candidate
        : current,
  );
}

class UserGrowth {
  const UserGrowth({
    required this.level,
    required this.experience,
    required this.currentXP,
    required this.nextLevelXP,
    required this.streakDays,
    required this.totalStudyMinutes,
    required this.learnedSentenceCount,
    required this.savedPhraseCount,
    required this.completedVideoCount,
    required this.activeCourseTitle,
    required this.activeCourseProgressPercent,
    required this.activeCourseCompletedEpisodes,
    required this.activeCourseTotalEpisodes,
    required this.today,
  });

  factory UserGrowth.fromLearningActivity({
    required LearningActivityState activity,
    required int phraseCount,
    required LibraryCourseData? activeCourse,
    required int completedVideoCount,
  }) {
    final int minutes = activity.records.values.fold<int>(
      0,
      (int total, LearningDailyRecord record) =>
          total + record.studyMilliseconds ~/ Duration.millisecondsPerMinute,
    );
    final int sentences = activity.records.values.fold<int>(
      0,
      (int total, LearningDailyRecord record) =>
          total + record.learnedSentenceKeys.length,
    );
    final int experience = activity.records.values.fold<int>(
      0,
      (int total, LearningDailyRecord record) =>
          total + experienceForDailyRecord(record),
    );
    int level = 1;
    int usedXP = 0;
    int nextLevelXP = _xpNeededForLevel(level);
    while (level < 10 && experience >= usedXP + nextLevelXP) {
      usedXP += nextLevelXP;
      level += 1;
      nextLevelXP = _xpNeededForLevel(level);
    }
    return UserGrowth(
      level: level,
      experience: experience,
      currentXP: experience - usedXP,
      nextLevelXP: nextLevelXP,
      streakDays: activity.streakDays,
      totalStudyMinutes: minutes,
      learnedSentenceCount: sentences,
      savedPhraseCount: phraseCount,
      completedVideoCount: completedVideoCount,
      activeCourseTitle: activeCourse?.title,
      activeCourseProgressPercent: activeCourse?.progressPercent ?? 0,
      activeCourseCompletedEpisodes: activeCourse?.completedEpisodes ?? 0,
      activeCourseTotalEpisodes: activeCourse?.totalEpisodes ?? 0,
      today: GrowthToday.fromRecord(activity.today),
    );
  }

  static const int _dailyStudyMinuteLimit = 30;
  static const int _dailySentenceLimit = 20;
  static const int _dailyPhraseLimit = 5;
  static const int _studyMinuteXP = 1;
  static const int _sentenceXP = 2;
  static const int _phraseXP = 2;
  static const int _checkInXP = 5;

  final int level;
  final int experience;
  final int currentXP;
  final int nextLevelXP;
  final int streakDays;
  final int totalStudyMinutes;
  final int learnedSentenceCount;
  final int savedPhraseCount;
  final int completedVideoCount;
  final String? activeCourseTitle;
  final int activeCourseProgressPercent;
  final int activeCourseCompletedEpisodes;
  final int activeCourseTotalEpisodes;
  final GrowthToday today;

  bool get hasReachedTopLevel => level == 10;

  double get levelProgress => hasReachedTopLevel ? 1 : currentXP / nextLevelXP;

  int? get nextLevelTotalXP =>
      hasReachedTopLevel ? null : experienceToReachLevel(level + 1);

  int get remainingXPToNextLevel =>
      hasReachedTopLevel ? 0 : nextLevelTotalXP! - experience;

  UserLevel get userLevel => UserLevel(
    level: level,
    title: title,
    englishTitle: englishTitle,
    xp: experience,
    nextLevelXp: nextLevelXP,
  );

  String get title {
    return growthLevelProfile(level).title;
  }

  String get englishTitle {
    return growthLevelProfile(level).englishTitle;
  }

  static int experienceToReachLevel(int level) {
    int total = 0;
    for (int item = 1; item < level; item++) {
      total += _xpNeededForLevel(item);
    }
    return total;
  }

  static int _xpNeededForLevel(int level) => 1847 + ((level - 1) * 400);

  static int studyXPForMinutes(int minutes) =>
      minutes.clamp(0, _dailyStudyMinuteLimit) * _studyMinuteXP;

  static int sentenceXPForCount(int count) =>
      count.clamp(0, _dailySentenceLimit) * _sentenceXP;

  static int phraseXPForCount(int count) =>
      count.clamp(0, _dailyPhraseLimit) * _phraseXP;

  static int experienceForDailyRecord(LearningDailyRecord record) {
    final int minutes =
        record.studyMilliseconds ~/ Duration.millisecondsPerMinute;
    return studyXPForMinutes(minutes) +
        sentenceXPForCount(record.learnedSentenceKeys.length) +
        phraseXPForCount(record.savedPhraseCount) +
        (record.checkedIn ? _checkInXP : 0);
  }
}

class GrowthLevelProfile {
  const GrowthLevelProfile(
    this.level,
    this.title,
    this.englishTitle,
    this.ability,
    this.assetPath,
    this.colors,
  );
  final int level;
  final String title;
  final String englishTitle;
  final String ability;
  final String assetPath;
  final List<int> colors;
}

GrowthLevelProfile growthLevelProfile(int level) {
  const List<(String, String, String, String, List<int>)> profiles =
      <(String, String, String, String, List<int>)>[
        (
          '英语启程者',
          'English Starter',
          '听懂高频单词与基础短句',
          'assets/img/growth-companion.png',
          <int>[0xFF201044, 0xFF61329A],
        ),
        (
          '基础学习者',
          'Foundation Learner',
          '掌握高频词汇与常用短句',
          'assets/img/growth-companion.png',
          <int>[0xFF17345C, 0xFF286EAC],
        ),
        (
          '基础表达者',
          'Basic Speaker',
          '能使用简单句型表达需求',
          'assets/img/growth-companion-daily.png',
          <int>[0xFF0D3D49, 0xFF168B91],
        ),
        (
          '生活场景者',
          'Everyday Learner',
          '理解常见生活场景中的英语',
          'assets/img/growth-companion-daily.png',
          <int>[0xFF173B55, 0xFF4D7BB1],
        ),
        (
          '场景应答者',
          'Situation Responder',
          '能在熟悉场景作出简短回应',
          'assets/img/growth-companion-confident.png',
          <int>[0xFF3C174D, 0xFF8E3D9D],
        ),
        (
          '简单交流者',
          'Simple Communicator',
          '可完成简短的日常对话',
          'assets/img/growth-companion-confident.png',
          <int>[0xFF4A2633, 0xFFB35F3A],
        ),
        (
          '对话参与者',
          'Conversation Participant',
          '能跟上熟悉话题的基础对话',
          'assets/img/growth-companion-daily.png',
          <int>[0xFF173B5A, 0xFF2B8DA9],
        ),
        (
          '稳定交流者',
          'Steady Communicator',
          '能围绕熟悉话题持续交流',
          'assets/img/growth-companion-confident.png',
          <int>[0xFF34245D, 0xFF7657BB],
        ),
        (
          '自信沟通者',
          'Confident Communicator',
          '可清晰表达经历、计划与观点',
          'assets/img/growth-companion.png',
          <int>[0xFF513517, 0xFFB98632],
        ),
        (
          '日常沟通者',
          'Daily Communicator',
          '能够理解并完成大多数日常沟通',
          'assets/img/growth-companion-confident.png',
          <int>[0xFF282A35, 0xFF8A784E],
        ),
      ];
  final int normalizedLevel = level.clamp(1, 10);
  final (String, String, String, String, List<int>) item =
      profiles[normalizedLevel - 1];
  return GrowthLevelProfile(
    normalizedLevel,
    item.$1,
    item.$2,
    item.$3,
    item.$4,
    item.$5,
  );
}

class UserLevel {
  const UserLevel({
    required this.level,
    required this.title,
    required this.englishTitle,
    required this.xp,
    required this.nextLevelXp,
  });

  final int level;
  final String title;
  final String englishTitle;
  final int xp;
  final int nextLevelXp;
}

class Achievement {
  const Achievement({
    required this.title,
    required this.description,
    required this.progress,
    required this.target,
    required this.rewardXp,
    required this.unlocked,
  });

  final String title;
  final String description;
  final int progress;
  final int target;
  final int rewardXp;
  final bool unlocked;
}

class GrowthActivity {
  const GrowthActivity({
    required this.type,
    required this.xp,
    required this.timestamp,
  });

  final String type;
  final int xp;
  final DateTime timestamp;
}

class GrowthToday {
  const GrowthToday({
    required this.studyMinutes,
    required this.sentenceCount,
    required this.phraseCount,
    required this.checkedIn,
  });

  factory GrowthToday.fromRecord(LearningDailyRecord record) => GrowthToday(
    studyMinutes: record.studyMilliseconds ~/ Duration.millisecondsPerMinute,
    sentenceCount: record.learnedSentenceKeys.length,
    phraseCount: record.savedPhraseCount,
    checkedIn: record.checkedIn,
  );

  final int studyMinutes;
  final int sentenceCount;
  final int phraseCount;
  final bool checkedIn;
}
