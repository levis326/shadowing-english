import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../episodes/data/episode_catalog_provider.dart';
import '../../episodes/domain/episode.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/app_shell.dart';
import '../../shared/presentation/pill_segmented_control.dart';
import '../../shared/presentation/state_views.dart';
import 'widgets/story_card.dart';

enum _HomeSegment { recent, allStories }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  _HomeSegment _segment = _HomeSegment.recent;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Episode>> catalog = ref.watch(episodeCatalogProvider);

    return AppShell(
      currentDestination: AppNavDestination.home,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(28, 18, 28, 8),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_outline_rounded),
                ),
                const Expanded(
                  child: Center(
                    child: Text(
                      'Learn',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const Gap(18),
            PillSegmentedControl<_HomeSegment>(
              value: _segment,
              options: const <SegmentOption<_HomeSegment>>[
                SegmentOption<_HomeSegment>(
                  value: _HomeSegment.recent,
                  label: 'Recent',
                ),
                SegmentOption<_HomeSegment>(
                  value: _HomeSegment.allStories,
                  label: 'All Stories',
                ),
              ],
              onValueChanged: (_HomeSegment nextValue) {
                setState(() {
                  _segment = nextValue;
                });
              },
            ),
          ],
        ),
      ),
      body: catalog.when(
        data: (List<Episode> episodes) {
          if (episodes.isEmpty) {
            return const AppEmptyState(
              title: 'No stories yet',
              message:
                  'Import your own video and subtitle files to start line-by-line listening practice.',
            );
          }

          final Episode featured = episodes.first;
          final List<Episode> visibleEpisodes = _segment == _HomeSegment.recent
              ? <Episode>[featured, ...episodes.skip(1)]
              : episodes;

          return ListView(
            padding: const EdgeInsets.fromLTRB(28, 10, 28, 20),
            children: <Widget>[
              const Text(
                'Continue listening',
                style: TextStyle(
                  fontSize: 40,
                  height: 0.98,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF050505),
                ),
              ),
              const Gap(14),
              const Text(
                'Continue your story-driven listening practice with calm, mobile-first controls built for line-by-line repetition.',
                style: TextStyle(
                  color: Color(0xFF68686D),
                  fontSize: 16,
                  height: 1.45,
                ),
              ),
              const Gap(24),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xFF101522), Color(0xFF2D4B75)],
                  ),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x18000000),
                      blurRadius: 26,
                      offset: Offset(0, 16),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          'Featured session',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Gap(18),
                      Text(
                        featured.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Gap(10),
                      const Text(
                        'Stay with one sentence until the sound and rhythm click.',
                        style: TextStyle(
                          color: Color(0xFFD9E1EE),
                          fontSize: 15,
                          height: 1.45,
                        ),
                      ),
                      const Gap(18),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF101522),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              onPressed: null,
                              child: const Text(
                                'Warm up with the latest line',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Gap(28),
              const Text(
                'Stories',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const Gap(14),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: visibleEpisodes.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 0.72,
                ),
                itemBuilder: (BuildContext context, int index) => StoryCard(
                  episode: visibleEpisodes[index],
                  tone: index.isEven
                      ? const Color(0xFFEAB98E)
                      : const Color(0xFFA9BFDD),
                ),
              ),
            ],
          );
        },
        loading: () => const AppLoadingState(),
        error: (Object error, StackTrace stackTrace) =>
            AppErrorState(message: error.toString()),
      ),
    );
  }
}
