import 'package:common_learn_english/features/phrases/presentation/phrase_book_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 7, 10, 8);

  test('phrase book starts empty without persisted phrases', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(phraseBookProvider), isEmpty);
  });

  test('review results schedule the next review deterministically', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(phraseBookProvider.notifier)
        .addPhrase(
          english: 'Practice makes progress.',
          chinese: '练习带来进步。',
          course: '真实课程',
          episode: '第 1 集',
          time: '00:00',
          rating: 3,
        );
    final PhraseEntry target = container.read(phraseBookProvider).first;
    container
        .read(phraseBookProvider.notifier)
        .recordReview(target.id, PhraseReviewResult.almost, now: now);

    PhraseEntry updated = container
        .read(phraseBookProvider)
        .firstWhere((PhraseEntry item) => item.id == target.id);
    expect(updated.reviewCount, target.reviewCount + 1);
    expect(updated.rating, target.rating);
    expect(updated.isDue(now), isFalse);
    expect(updated.isDue(now.add(const Duration(days: 1))), isTrue);

    container
        .read(phraseBookProvider.notifier)
        .recordReview(target.id, PhraseReviewResult.needPractice, now: now);
    updated = container
        .read(phraseBookProvider)
        .firstWhere((PhraseEntry item) => item.id == target.id);
    expect(updated.isDue(now), isTrue);
    expect(updated.rating, target.rating - 1);
    expect(updated.lapseCount, 1);
  });

  test('got-it advances the learning stage and delete removes one phrase', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(phraseBookProvider.notifier)
        .addPhrase(
          english: 'Practice makes progress.',
          chinese: '练习带来进步。',
          course: '真实课程',
          episode: '第 1 集',
          time: '00:00',
          rating: 3,
        );
    final List<PhraseEntry> initial = container.read(phraseBookProvider);
    final PhraseEntry target = initial.first;
    container
        .read(phraseBookProvider.notifier)
        .recordReview(target.id, PhraseReviewResult.canUse, now: now);

    final PhraseEntry reviewed = container
        .read(phraseBookProvider)
        .firstWhere((PhraseEntry item) => item.id == target.id);
    expect(reviewed.rating, target.rating + 1);
    expect(
      reviewed.nextReviewAt,
      now.add(const Duration(days: 14)).toIso8601String(),
    );

    container.read(phraseBookProvider.notifier).deletePhrase(target.id);
    expect(container.read(phraseBookProvider), hasLength(initial.length - 1));
  });
}
