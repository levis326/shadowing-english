import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/data/word_pronunciation_service.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import 'phrase_book_provider.dart';
import 'widgets/phrase_review_panel.dart';

class PhraseReviewScreen extends ConsumerStatefulWidget {
  const PhraseReviewScreen({super.key});

  @override
  ConsumerState<PhraseReviewScreen> createState() => _PhraseReviewScreenState();
}

class _PhraseReviewScreenState extends ConsumerState<PhraseReviewScreen> {
  List<String>? sessionIds;
  int currentIndex = 0;
  int initialTotal = 0;
  bool revealed = false;

  @override
  Widget build(BuildContext context) {
    final List<PhraseEntry> phrases = ref.watch(phraseBookProvider);
    final List<LibraryCourseData> catalog = ref.watch(libraryCatalogProvider);
    sessionIds ??= _buildSessionIds(phrases);
    initialTotal = initialTotal == 0 ? sessionIds!.length : initialTotal;

    final Map<String, PhraseEntry> byId = <String, PhraseEntry>{
      for (final PhraseEntry phrase in phrases) phrase.id: phrase,
    };
    sessionIds!.removeWhere((String id) => !byId.containsKey(id));
    final bool complete = sessionIds!.isEmpty;
    final int completedCount = initialTotal - sessionIds!.length;
    final PhraseEntry? current = complete
        ? null
        : byId[sessionIds![currentIndex % sessionIds!.length]];

    return PadScaffold(
      currentDestination: AppNavDestination.phrases,
      showNavigation: false,
      topBar: _ReviewHeader(
        current: complete ? initialTotal : completedCount + 1,
        total: initialTotal,
        onBack: () => context.pop(),
      ),
      body: current == null
          ? _ReviewComplete(
              reviewedCount: completedCount,
              onBack: () => context.pop(),
              onReviewAgain: phrases.isEmpty
                  ? null
                  : () => setState(() {
                      sessionIds = phrases
                          .map((PhraseEntry item) => item.id)
                          .toList();
                      currentIndex = 0;
                      initialTotal = sessionIds!.length;
                      revealed = false;
                    }),
            )
          : PhraseReviewPanel(
              phrase: current,
              reviewIndex: completedCount,
              total: initialTotal,
              revealed: revealed,
              onReveal: () => setState(() => revealed = true),
              onPrevious: currentIndex > 0 ? _showPrevious : null,
              onSkip: sessionIds!.length > 1 ? _skipCurrent : null,
              onPlaySource: () => _playSource(current),
              onListenToSource: () => _jumpToSource(context, catalog, current),
              onResult: (PhraseReviewResult result) =>
                  _recordReview(current.id, result),
            ),
    );
  }

  List<String> _buildSessionIds(List<PhraseEntry> phrases) {
    final List<String> due = phrases
        .where((PhraseEntry item) => item.isDue())
        .map((PhraseEntry item) => item.id)
        .toList(growable: true);
    return due.isEmpty
        ? phrases.map((PhraseEntry item) => item.id).toList(growable: true)
        : due;
  }

  void _recordReview(String phraseId, PhraseReviewResult result) {
    ref.read(phraseBookProvider.notifier).recordReview(phraseId, result);
    setState(() {
      revealed = false;
      if (result == PhraseReviewResult.needPractice) {
        currentIndex = sessionIds!.length > 1
            ? (currentIndex + 1) % sessionIds!.length
            : 0;
        return;
      }
      sessionIds!.remove(phraseId);
      if (sessionIds!.isEmpty) {
        currentIndex = 0;
      } else {
        currentIndex %= sessionIds!.length;
      }
    });
  }

  void _showPrevious() {
    setState(() {
      currentIndex -= 1;
      revealed = false;
    });
  }

  void _skipCurrent() {
    setState(() {
      currentIndex = (currentIndex + 1) % sessionIds!.length;
      revealed = false;
    });
  }

  Future<void> _playSource(PhraseEntry phrase) async {
    try {
      await ref.read(wordPronunciationServiceProvider).speak(phrase.english);
    } on WordPronunciationException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  void _jumpToSource(
    BuildContext context,
    List<LibraryCourseData> catalog,
    PhraseEntry phrase,
  ) {
    final String? episodeId = _resolveEpisodeId(catalog, phrase);
    if (episodeId == null) {
      _showMessage('原视频已不存在，已改用语音朗读。');
      return;
    }
    context.pushNamed(
      SGRoute.player.name,
      pathParameters: <String, String>{'episodeId': episodeId},
      queryParameters: <String, String>{
        'startTime': phrase.startTime ?? phrase.time,
        'autoplay': '1',
      },
    );
  }

  String? _resolveEpisodeId(
    List<LibraryCourseData> catalog,
    PhraseEntry phrase,
  ) {
    if (phrase.episodeId != null &&
        catalog.any(
          (LibraryCourseData course) => course.episodes.any(
            (LibraryEpisodeItem episode) => episode.id == phrase.episodeId,
          ),
        )) {
      return phrase.episodeId;
    }
    for (final LibraryCourseData course in catalog) {
      if (course.title != phrase.course) continue;
      for (final LibraryEpisodeItem episode in course.episodes) {
        if (phrase.episode.contains(episode.numberStr)) return episode.id;
      }
    }
    return null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ReviewHeader extends StatelessWidget {
  const _ReviewHeader({
    required this.current,
    required this.total,
    required this.onBack,
  });

  final int current;
  final int total;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final double progress = total == 0 ? 0 : current / total;
    final double topInset = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, topInset + 8, 16, 12),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              PadBackButton(tooltip: '返回短语库', onPressed: onBack),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '今日复习',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
              ),
              Text(
                '$current / $total',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: progress.clamp(0, 1),
              backgroundColor: AppDesignTokens.borderGray,
              color: AppDesignTokens.brandGreen,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewComplete extends StatelessWidget {
  const _ReviewComplete({
    required this.reviewedCount,
    required this.onBack,
    required this.onReviewAgain,
  });

  final int reviewedCount;
  final VoidCallback onBack;
  final VoidCallback? onReviewAgain;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircleAvatar(
                radius: 38,
                backgroundColor: AppDesignTokens.brandGreen,
                child: Icon(Icons.check_rounded, size: 42, color: Colors.white),
              ),
              const SizedBox(height: 18),
              const Text(
                '今日复习已完成',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                '完成 $reviewedCount 条短语，新的复习时间已经安排好了。',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppDesignTokens.textSecondary),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onBack,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                child: const Text('返回短语库'),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: onReviewAgain, child: const Text('继续自由复习')),
            ],
          ),
        ),
      ),
    );
  }
}
