import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../domain/episode.dart';

final FutureProvider<List<Episode>> episodeCatalogProvider =
    FutureProvider<List<Episode>>((Ref ref) async {
      final List<Episode> importedEpisodes = ref
          .watch(libraryCatalogProvider)
          .expand(
            (LibraryCourseData course) => course.episodes
                .where(
                  (LibraryEpisodeItem item) =>
                      item.videoAsset != null ||
                      item.enSubtitleAsset != null ||
                      item.subtitleTracks.isNotEmpty,
                )
                .map(
                  (LibraryEpisodeItem item) => Episode(
                    id: item.id,
                    title: item.title,
                    videoAsset: item.videoAsset ?? '',
                    enSubtitleAsset: item.enSubtitleAsset ?? '',
                    subtitleTracks: item.subtitleTracks
                        .map(
                          (LibrarySubtitleTrackItem track) => EpisodeSubtitleTrack(
                            languageCode: track.languageCode,
                            languageLabel: track.languageLabel,
                            path: track.path,
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
          )
          .toList(growable: false);

      return importedEpisodes;
    });
