import 'package:common_learn_english/features/home/presentation/learning_dashboard_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('learning dashboard reflects activity changes', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    final LearningDashboardStats initial = container.read(
      learningDashboardProvider,
    );

    expect(initial.todayStudyMinutes, 0);
    expect(initial.todaySentenceCount, 0);
    expect(initial.todayShadowingCount, 0);
    expect(initial.todayProgressPercent, 0);
    expect(initial.checkedIn, false);
    expect(initial.streakDays, 0);

    container.read(learningActivityProvider.notifier)
      ..recordPlayDuration(duration: const Duration(minutes: 10))
      ..recordSentenceStudy(sentenceKey: 'line-1')
      ..recordShadowingToggle(enabled: true);

    final LearningDashboardStats updated = container.read(
      learningDashboardProvider,
    );

    expect(updated.todayStudyMinutes, 10);
    expect(updated.todaySentenceCount, 1);
    expect(updated.todayShadowingCount, 1);
    expect(updated.todayProgressPercent, 30);
    expect(updated.checkedIn, true);
    expect(updated.streakDays, 1);
  });

  test('learning dashboard aggregates daily trends and streaks', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    final LearningActivityNotifier notifier = container.read(
      learningActivityProvider.notifier,
    );
    final DateTime today = DateTime.now();

    for (int offset = 0; offset < 3; offset++) {
      notifier.recordPlayDuration(
        duration: const Duration(minutes: 10),
        occurredAt: today.subtract(Duration(days: offset)),
      );
    }

    final LearningDashboardStats stats = container.read(
      learningDashboardProvider,
    );

    expect(stats.streakDays, 3);
    expect(stats.totalStudyDays, 3);
    expect(stats.totalStudyMinutes, 30);
    expect(stats.weeklyTrend.last.studyMinutes, 10);
    expect(
      stats.monthlyTrend.where(
        (LearningTrendPoint item) => item.studyMinutes > 0,
      ),
      isNotEmpty,
    );
    final LearningActivityState restored = LearningActivityState.fromJson(
      container.read(learningActivityProvider).toJson(),
    );
    expect(restored.streakDays, 3);
    expect(restored.todayStudyMinutes, 10);
  });
}
